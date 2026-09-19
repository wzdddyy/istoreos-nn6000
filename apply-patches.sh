#!/bin/bash
# ============================================================
# apply-patches.sh
# 将 Link NN6000 v1/v2 设备支持移植到 iStoreOS 25.12 源码树
# 用法: 在 iStoreOS 源码根目录下执行
#   cd istoreos && bash ../apply-patches.sh
# ============================================================
set -ex

# 获取补丁文件所在目录（脚本自身的目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"

# 确保在 iStoreOS 源码根目录
if [ ! -f "target/linux/qualcommax/Makefile" ]; then
    echo "ERROR: 请在 iStoreOS 源码根目录下运行此脚本"
    exit 1
fi

echo "========================================"
echo "  移植 Link NN6000 v1/v2 到 iStoreOS"
echo "========================================"

# ------------------------------------------------------------
# 1. 复制 DTS 文件
# ------------------------------------------------------------
DTS_DST="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"

echo "[1/5] 复制 DTS 设备树文件..."
cp "${FILES_DIR}/ipq6000-link.dtsi"    "${DTS_DST}/"
cp "${FILES_DIR}/ipq6000-nn6000-v1.dts" "${DTS_DST}/"
cp "${FILES_DIR}/ipq6000-nn6000-v2.dts" "${DTS_DST}/"
echo "  -> DTS 文件已复制到 ${DTS_DST}/"

# ------------------------------------------------------------
# 2. 追加设备定义到 ipq60xx.mk
# ------------------------------------------------------------
IMAGE_MK="target/linux/qualcommax/image/ipq60xx.mk"

echo "[2/5] 追加设备定义到 ipq60xx.mk..."
# 检查是否已存在，避免重复添加
if grep -q "link_nn6000" "${IMAGE_MK}"; then
    echo "  -> ipq60xx.mk 已包含 nn6000 定义，跳过"
else
    cat "${FILES_DIR}/ipq60xx.mk.fragment" >> "${IMAGE_MK}"
    echo "  -> 设备定义已追加到 ipq60xx.mk"
fi

# ------------------------------------------------------------
# 3. 在 02_network 中插入 nn6000 网络配置（片段插入，不覆盖原文件）
# ------------------------------------------------------------
NETWORK_FILE="target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network"

echo "[3/5] 更新 02_network 网络配置..."
if grep -q "link,nn6000-v1" "${NETWORK_FILE}" && grep -q "link,nn6000-v2" "${NETWORK_FILE}"; then
    echo "  -> 02_network 已包含 nn6000-v1/v2，跳过"
else
    # v1：加入 2-LAN 组（改写 gl-axt1800) 收尾行，锚点行消失保证幂等）
    sed -i 's#^\tglinet,gl-axt1800)$#\tglinet,gl-axt1800|\\\n\tlink,nn6000-v1)#' "${NETWORK_FILE}"
    # v2：加入 4-LAN 组（改写 yuncore,fap650) 收尾行）
    sed -i 's#^\tyuncore,fap650)$#\tyuncore,fap650|\\\n\tlink,nn6000-v2)#' "${NETWORK_FILE}"
    # 验证插入结果，避免半完成
    grep -q "link,nn6000-v1" "${NETWORK_FILE}" || { echo "ERROR: nn6000-v1 插入失败"; exit 1; }
    grep -q "link,nn6000-v2" "${NETWORK_FILE}" || { echo "ERROR: nn6000-v2 插入失败"; exit 1; }
    echo "  -> 02_network 已插入 nn6000-v1/v2 LAN/WAN 配置"
fi

# ------------------------------------------------------------
# 4. 修改 ipq60xx 升级脚本（eMMC sysupgrade / OTA 支持）
# ------------------------------------------------------------
# Link NN6000 是 eMMC 设备，设备定义用了 Device/EmmcImage。
# ipq60xx 的 platform.sh 里原本只有 nand_do_upgrade 系列分支，没有 nn6000，
# platform_do_upgrade() 会落到 default_do_upgrade()（MTD/NAND 路径），
# 在 eMMC 上 sysupgrade 会失败，iStoreOS 的 OTA
#（package/istoreos-files/files/etc/init.d/isos_upgrade）同样依赖它。
#
# CI_KERNPART / CI_ROOTPART 的分区名取自 ipq807x 中同为
# FitImage + EmmcImage + f2fs 的 eMMC 设备（prpl,haze / qnap,301w）。
# 如果 NN6000 的 eMMC GPT 分区名不是 0:HLOS / rootfs，请改成实际名字。
UPGRADE_SH="target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh"

echo "[4/5] 更新 platform.sh（eMMC 升级支持）..."

if grep -q "link,nn6000-v2)" "${UPGRADE_SH}"; then
    echo "  -> platform.sh 已包含 nn6000 分支，跳过"
else
    python3 - "${UPGRADE_SH}" <<'PYEOF'
import io
import sys

path = sys.argv[1]
src = io.open(path, encoding='utf-8').read()

# 插入锚点必须同时包含 case 的通配分支行 "*)"：
# shell 的 case 按顺序匹配，如果把 nn6000 分支插在 "*)" 之后，
# 它永远不会被命中（"*)" 会抢先匹配一切）。
anchor = '\t*)\n\t\tdefault_do_upgrade "$1"\n'
if anchor not in src:
    sys.exit('ERROR: anchor "*)/default_do_upgrade" not found in ' + path)

case_block = (
    '\tlink,nn6000-v1)|\\\n'
    '\tlink,nn6000-v2)\n'
    '\t\tCI_KERNPART="0:HLOS"\n'
    '\t\tCI_ROOTPART="rootfs"\n'
    '\t\temmc_do_upgrade "$1"\n'
    '\t\t;;\n'
)
src = src.replace(anchor, case_block + anchor, 1)

# ipq60xx 原本没有 platform_copy_config()，补一个（配置保留走 eMMC 路径）
copy_config = (
    '\n'
    'platform_copy_config() {\n'
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
print('  -> platform.sh updated')
PYEOF
    echo "  -> 已添加 nn6000 eMMC 升级分支 + platform_copy_config()"
fi

# ------------------------------------------------------------
# 5. 修改 ipq-wifi Makefile（添加 WiFi 校准包）
# ------------------------------------------------------------
WIFI_MK="package/firmware/ipq-wifi/Makefile"

echo "[5/5] 更新 ipq-wifi Makefile..."

# 5a. 在 ALLWIFIBOARDS 列表中添加 link_nn6000
if grep -q "link_nn6000" "${WIFI_MK}"; then
    echo "  -> ipq-wifi Makefile 已包含 link_nn6000，跳过"
else
    # 在 iodata_wn-dax3000gr 后面插入 link_nn6000
    sed -i '/iodata_wn-dax3000gr \\/a\\tlink_nn6000 \\' "${WIFI_MK}"
    # 后置校验：sed 锚点一旦失效就是静默失败，必须确认真的插进去了
    if ! grep -qE '^link_nn6000 \\$' "${WIFI_MK}"; then
        echo "ERROR: 未能把 link_nn6000 插入 ALLWIFIBOARDS（sed 锚点可能已失效）"
        exit 1
    fi
    echo "  -> ALLWIFIBOARDS 已添加 link_nn6000"
fi

# 5b. 在文件末尾添加 generate-ipq-wifi-package 调用
if grep -q "generate-ipq-wifi-package,link_nn6000" "${WIFI_MK}"; then
    echo "  -> generate-ipq-wifi-package 调用已存在，跳过"
else
    # 在 linksys_homewrk 的 generate-ipq-wifi-package 行前面插入
    # 注意：不能用 /linksys_homewrk/ 作为匹配，因为 ALLWIFIBOARDS 列表中
    # 也有 linksys_homewrk 行，会导致在列表中间插入 eval 调用，破坏 Makefile
    sed -i '/generate-ipq-wifi-package,linksys_homewrk/i\$(eval $(call generate-ipq-wifi-package,link_nn6000,Link NN6000))' "${WIFI_MK}"
    if ! grep -q "generate-ipq-wifi-package,link_nn6000" "${WIFI_MK}"; then
        echo "ERROR: 未能插入 generate-ipq-wifi-package,link_nn6000（sed 锚点可能已失效）"
        exit 1
    fi
    echo "  -> generate-ipq-wifi-package 调用已添加"
fi

# 5c. 检查固件源是否包含 nn6000 BDF
# iStoreOS 25.12 使用 PKG_SOURCE_DATE:=2026-05-18
# nn6000 BDF 于 2026-01-31 合入 qca-wireless（commit 97af8a2a2dcb）
# 注意：ipq-wifi 的安装用 $(wildcard .../board-link_nn6000.*)，
# 文件缺失不会报错，只会装出空包（WiFi 起不来），所以这里必须显式确认。
WIFI_SOURCE_DATE=$(grep 'PKG_SOURCE_DATE' "${WIFI_MK}" | head -1 | cut -d: -f2 | tr -d ' ')
echo "  -> ipq-wifi 固件源日期: ${WIFI_SOURCE_DATE}"
if [[ "${WIFI_SOURCE_DATE}" > "2026-01-31" ]]; then
    echo "  -> 固件源应已包含 nn6000 BDF"
    echo "     若编译后 WiFi 不工作，用以下命令确认 BDF 是否真的装进去了："
    echo "       find build_dir -name 'board-link_nn6000.*' -o -name 'board-2.bin' | grep IPQ6018"
else
    echo "  -> 警告: 固件源可能不包含 nn6000 BDF"
    echo "     更新方法: 将 PKG_SOURCE_DATE 改为 2026-05-18"
    echo "              将 PKG_SOURCE_VERSION 改为 e20f4c6ff197823762319e4b7e31af01816503cf"
    echo "              将 PKG_MIRROR_HASH 改为 skip"
fi

echo "========================================"
echo "  移植完成！"
echo "========================================"
echo ""
echo "下一步:"
echo "  1. ./scripts/feeds update -a"
echo "  2. ./scripts/feeds install -a"
echo "  3. make defconfig  (选择 qualcommax -> ipq60xx -> Link NN6000 v2)"
echo "  4. make -j\$(nproc) V=s"
