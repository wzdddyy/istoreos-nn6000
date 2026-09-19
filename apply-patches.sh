#!/bin/bash
# apply-patches.sh
# 将 Link NN6000 v1/v2 移植到 iStoreOS 25.12
# 用法: cd istoreos && bash ../apply-patches.sh
set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"

# 必须在 iStoreOS 源码根目录执行
if [ ! -f "target/linux/qualcommax/Makefile" ]; then
    echo "ERROR: 请在 iStoreOS 源码根目录下运行此脚本"
    exit 1
fi

echo "==== 移植 Link NN6000 v1/v2 ===="

# 1. 复制 DTS
DTS_DST="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"
echo "[1/5] 复制 DTS..."
cp "${FILES_DIR}/ipq6000-link.dtsi"      "${DTS_DST}/"
cp "${FILES_DIR}/ipq6000-nn6000-v1.dts" "${DTS_DST}/"
cp "${FILES_DIR}/ipq6000-nn6000-v2.dts" "${DTS_DST}/"

# 2. 追加设备定义
IMAGE_MK="target/linux/qualcommax/image/ipq60xx.mk"
echo "[2/5] 追加设备定义..."
if ! grep -q "link_nn6000" "${IMAGE_MK}"; then
    cat "${FILES_DIR}/ipq60xx.mk.fragment" >> "${IMAGE_MK}"
fi

# 3. 02_network 插入网络配置（改写收尾行保证幂等）
NETWORK_FILE="target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network"
echo "[3/5] 更新 02_network..."
if ! grep -q "link,nn6000-v1" "${NETWORK_FILE}"; then
    sed -i 's#^\tglinet,gl-axt1800)$#\tglinet,gl-axt1800|\\\n\tlink,nn6000-v1)#' "${NETWORK_FILE}"
    sed -i 's#^\tyuncore,fap650)$#\tyuncore,fap650|\\\n\tlink,nn6000-v2)#' "${NETWORK_FILE}"
    grep -q "link,nn6000-v1" "${NETWORK_FILE}" || { echo "ERROR: 02_network 插入失败"; exit 1; }
fi

# 4. platform.sh 添加 eMMC 升级分支
UPGRADE_SH="target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh"
echo "[4/5] 更新 platform.sh..."
if ! grep -q "link,nn6000-v2)" "${UPGRADE_SH}"; then
    python3 - "${UPGRADE_SH}" <<'PYEOF'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding='utf-8').read()

# 必须插在 "*)" 通配分支之前，否则永不命中
anchor = '\t*)\n\t\tdefault_do_upgrade "$1"\n'
if anchor not in src:
    sys.exit('ERROR: anchor not found in ' + path)

case_block = (
    '\tlink,nn6000-v1)|\\\n'
    '\tlink,nn6000-v2)\n'
    '\t\tCI_KERNPART="0:HLOS"\n'
    '\t\tCI_ROOTPART="rootfs"\n'
    '\t\temmc_do_upgrade "$1"\n'
    '\t\t;;\n'
)
src = src.replace(anchor, case_block + anchor, 1)

copy_config = (
    '\nplatform_copy_config() {\n'
    '\tcase "$(board_name)" in\n'
    '\tlink,nn6000-v1)|\\\n'
    '\tlink,nn6000-v2)\n'
    '\t\temmc_copy_config\n'
    '\t\t;;\n'
    '\tesac\n'
    '}\n'
)
src = src.rstrip('\n') + '\n' + copy_config

io.open(path, 'w', encoding='utf-8').write(src)
PYEOF
fi

# 5. ipq-wifi 添加校准包
WIFI_MK="package/firmware/ipq-wifi/Makefile"
echo "[5/5] 更新 ipq-wifi Makefile..."

if ! grep -q "link_nn6000" "${WIFI_MK}"; then
    sed -i '/iodata_wn-dax3000gr \\/a\\tlink_nn6000 \\' "${WIFI_MK}"
    grep -qP '^\tlink_nn6000 \\$' "${WIFI_MK}" || { echo "ERROR: ALLWIFIBOARDS 插入失败"; exit 1; }
fi

if ! grep -q "generate-ipq-wifi-package,link_nn6000" "${WIFI_MK}"; then
    # 只匹配 eval 行，避免误改 ALLWIFIBOARDS 列表
    sed -i '/generate-ipq-wifi-package,linksys_homewrk/i\$(eval $(call generate-ipq-wifi-package,link_nn6000,Link NN6000))' "${WIFI_MK}"
    grep -q "generate-ipq-wifi-package,link_nn6000" "${WIFI_MK}" || { echo "ERROR: eval 插入失败"; exit 1; }
fi

# 检查 BDF 是否已包含（nn6000 于 2026-01-31 合入）
WIFI_SOURCE_DATE=$(grep 'PKG_SOURCE_DATE' "${WIFI_MK}" | head -1 | cut -d: -f2 | tr -d ' ')
echo "ipq-wifi 源日期: ${WIFI_SOURCE_DATE}"
if [[ "${WIFI_SOURCE_DATE}" < "2026-01-31" ]]; then
    echo "警告: 固件源可能不包含 nn6000 BDF，需更新 PKG_SOURCE_DATE"
fi

echo "==== 移植完成 ===="
