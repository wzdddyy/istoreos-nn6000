# iStoreOS NN6000 固件

基于 iStoreOS 25.12 源码，为 Link NN6000 v1 / v2 编译的固件。

## ⚠️ 当前状态：测试中

固件仍在测试阶段，欢迎在 [Issues](https://github.com/ZZJ/istoreos-nn6000/issues) 反馈使用中遇到的问题，例如无法启动、网口异常、WiFi 不稳定等，反馈时请注明设备版本（v1 / v2）和刷机方式。

## 固件特点

- iStoreOS 25.12（内核 6.12）
- 内置 Docker（dockerd + LuCI 管理界面）
- 内置 iStore 应用商店
- 存储为 eMMC，支持双分区 A/B 升级

## 默认信息

| 项目 | 值 |
|------|-----|
| LAN 地址 | `192.168.100.1` |
| 用户名 / 密码 | `root` / `password` |
| WiFi 名称 | `iStoreOS` / `iStoreOS-5G` |

## 如何编译

使用 GitHub Actions 手动触发：

1. Fork 本仓库
2. 进入 **Actions** 页面
3. 选择 **Build iStoreOS NN6000 Firmware**
4. 点击 **Run workflow**

编译完成后固件会自动发布到 Releases（首次编译约需 2~4 小时，之后有工具链缓存会更快）。

## 刷写说明

| 文件 | 用途 |
|------|------|
| `*-initramfs-uImage.itb` | TFTP 引导测试，不写入 Flash |
| `*-factory.bin` | 从原厂固件首次刷入 |
| `*-sysupgrade.bin` | 从 OpenWrt/iStoreOS 升级 |

建议**先用 initramfs 测试**，确认网口、WiFi、USB 正常后再刷入 factory.bin。

## 免责声明

此固件为非官方构建，刷写有风险，请自行承担后果。
