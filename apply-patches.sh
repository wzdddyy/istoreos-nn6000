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

echo "[1/4] 复制 DTS 设备树文件..."
cp "${FILES_DIR}/ipq6000-link.dtsi"    "${DTS_DST}/"
cp "${FILES_DIR}/ipq6000-nn6000-v1.dts" "${DTS_DST}/"
cp "${FILES_DIR}/ipq6000-nn6000-v2.dts" "${DTS_DST}/"
echo "  -> DTS 文件已复制到 ${DTS_DST}/"

# ------------------------------------------------------------
# 2. 追加设备定义到 ipq60xx.mk
# ------------------------------------------------------------
IMAGE_MK="target/linux/qualcommax/image/ipq60xx.mk"

echo "[2/4] 追加设备定义到 ipq60xx.mk..."
# 检查是否已存在，避免重复添加
if grep -q "link_nn6000" "${IMAGE_MK}"; then
    echo "  -> ipq60xx.mk 已包含 nn6000 定义，跳过"
else
    cat "${FILES_DIR}/ipq60xx.mk.fragment" >> "${IMAGE_MK}"
    echo "  -> 设备定义已追加到 ipq60xx.mk"
fi

# ------------------------------------------------------------
# 3. 替换 02_network 网络配置
# ------------------------------------------------------------
NETWORK_FILE="target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network"

echo "[3/4] 更新 02_network 网络配置..."
cp "${FILES_DIR}/02_network" "${NETWORK_FILE}"
echo "  -> 02_network 已更新（添加 nn6000-v1/v2 LAN/WAN 配置）"

# ------------------------------------------------------------
# 4. 修改 ipq-wifi Makefile（添加 WiFi 校准包）
# ------------------------------------------------------------
WIFI_MK="package/firmware/ipq-wifi/Makefile"

echo "[4/4] 更新 ipq-wifi Makefile..."

# 4a. 在 ALLWIFIBOARDS 列表中添加 link_nn6000
if grep -q "link_nn6000" "${WIFI_MK}"; then
    echo "  -> ipq-wifi Makefile 已包含 link_nn6000，跳过"
else
    # 在 iodata_wn-dax3000gr 后面插入 link_nn6000
    sed -i '/iodata_wn-dax3000gr \\/a\\tlink_nn6000 \\' "${WIFI_MK}"
    echo "  -> ALLWIFIBOARDS 已添加 link_nn6000"
fi

# 4b. 在文件末尾添加 generate-ipq-wifi-package 调用
if grep -q "generate-ipq-wifi-package,link_nn6000" "${WIFI_MK}"; then
    echo "  -> generate-ipq-wifi-package 调用已存在，跳过"
else
    # 在 linksys_homewrk 的 generate-ipq-wifi-package 行前面插入
    # 注意：不能用 /linksys_homewrk/ 作为匹配，因为 ALLWIFIBOARDS 列表中
    # 也有 linksys_homewrk 行，会导致在列表中间插入 eval 调用，破坏 Makefile
    sed -i '/generate-ipq-wifi-package,linksys_homewrk/i\$(eval $(call generate-ipq-wifi-package,link_nn6000,Link NN6000))' "${WIFI_MK}"
    echo "  -> generate-ipq-wifi-package 调用已添加"
fi

# 4c. 检查固件源是否包含 nn6000 BDF
# iStoreOS 25.12 使用 PKG_SOURCE_DATE:=2026-05-18
# nn6000 BDF 于 2026-02-17 合入，理论上已包含
# 如果编译时报 board-link_nn6000.* 找不到，需要更新固件源版本
WIFI_SOURCE_DATE=$(grep 'PKG_SOURCE_DATE' "${WIFI_MK}" | head -1 | cut -d: -f2 | tr -d ' ')
echo "  -> ipq-wifi 固件源日期: ${WIFI_SOURCE_DATE}"
if [[ "${WIFI_SOURCE_DATE}" > "2026-02-17" ]]; then
    echo "  -> 固件源应已包含 nn6000 BDF"
else
    echo "  -> 警告: 固件源可能不包含 nn6000 BDF，编译时可能需要更新 PKG_SOURCE_DATE"
    echo "     更新方法: 将 PKG_SOURCE_DATE 改为 2026-09-10"
    echo "              将 PKG_SOURCE_VERSION 改为 04dff0ab979f153a4605095b5e449a9ac5494a17"
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
