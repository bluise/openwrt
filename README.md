# OpenWrt 25.12 定制固件 (Lenovo U35)

GitHub Actions 在线自动编译 OpenWrt 25.12 x86_64 固件。

## 功能

- **OpenWrt 25.12** (x86_64 / UEFI, squashfs + ext4)
- **OpenClash** 科学上网插件
- **OpenAppFilter (OAF)** 应用过滤
- **MT7922** 无线网卡驱动 (mt7921e + firmware)
- **RTL8153** USB 网卡驱动 (r8152) + USB3/storage
- **LuCI 中文界面 + HTTPS**
- **内置 `openwrt-install`** 一键安装到内置硬盘命令
- **上游自动更新**：每周日自动检查 OpenWrt/OpenClash/OAF 上游仓库，有新提交自动重新编译

## 网络默认

| 接口 | 网卡 | 用途 |
|------|------|------|
| LAN | eth1 | 桥接, 管理地址 `10.0.0.1` |
| WAN | eth0 | DHCP 自动获取 |

防火墙为 OpenWrt 默认策略（WAN 拒绝入站，仅内网可管理）。

## 自动构建

- `push` 到 `main`（修改 `.config` / `diy-*.sh` / `files/**` 时）
- 手动触发：Actions → Build OpenWrt → Run workflow
- 定时：每周日北京时间 11:00 检查上游

固件产物在每次 Run 的 **Artifacts** 和 **Release (firmware tag)** 中：
`openwrt-x86-64-generic-squashfs-combined-efi.img.gz`

## 刷机

1. 下载 `*combined-efi.img.gz`
2. 用 Rufus（DD 模式）/ Etcher / dd 写入U盘
3. U盘启动，系统起来后执行 `openwrt-install` 安装到内置硬盘
4. 默认登录：`http://10.0.0.1`，首次需 `passwd` 设置密码