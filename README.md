# OpenWrt 25.12 定制固件

GitHub Actions 在线自动编译 OpenWrt 25.12 x86_64 固件。

## 功能

- **OpenWrt 25.12** (x86_64 / UEFI, squashfs + ext4)
- **OpenClash** 科学上网插件
- **OpenAppFilter (OAF)** 应用过滤
- **MT7922** 无线网卡驱动 (mt7921e + firmware)
- **RTL8153** USB 网卡驱动 (r8152) + USB3/storage
- **LuCI 中文界面 + HTTPS**
- **内置 `openwrt-install`** 一键安装到内置硬盘命令（含剩余空间检测与扩容指引）
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

固件产物在每次 Run 的 **Artifacts** 和 **Release (firmware tag)** 中，同时包含两个变体：

| 文件 | 根文件系统 | 说明 |
|------|-----------|------|
| `openwrt-x86-64-generic-squashfs-combined-efi.img.gz` | squashfs（只读） | 抗写坏，支持一键恢复出厂 |
| `openwrt-x86-64-generic-ext4-combined-efi.img.gz` | ext4（可写） | 可直接扩容，适合内置盘长期使用 |

两者都能启动，按需求选一个刷。

## 刷机

1. 下载 `*combined-efi.img.gz`
2. 用 Rufus（DD 模式）/ Etcher / dd 写入U盘
3. U盘启动，系统起来后执行 `openwrt-install` 安装到内置硬盘
4. 默认登录：`http://10.0.0.1`，首次需 `passwd` 设置密码

## 空间与扩容（重要）

**装完系统只占约 104 MiB，与硬盘大小无关**，需要手动扩容一次才能用满整盘。

原因：官方 `combined-efi` 镜像内嵌的 GPT 只描述镜像自身大小（约 120 MiB），
写入大容量硬盘后 GPT 的 `LastUsableLBA` 仍停在镜像末尾，因此 rootfs 分区固定为
104 MiB，磁盘剩余空间处于未分配状态。必须**重写 GPT + 扩分区 + 扩文件系统**三步才能占满。

`openwrt-install` 写盘后会**只读检测**并给出针对你磁盘的具体命令（不会自动改分区表）。
例如 2 GiB 盘会输出：

```
[INFO] 系统分区     : /dev/sda2  (104 MiB, ext4)
[WARN] 分区未占满磁盘: 可再扩约 1928 MiB
[INFO]             分区 104 MiB -> 2032 MiB
[INFO]             (分区尺寸; 文件系统实际可用空间会略小, 扩容后用 df -h / 查看)
```

### 扩容步骤（ext4 版）

> 已在 `openwrt-25.12 combined-efi` 镜像上实测通过。squashfs 版扩容语义不同，脚本会另行提示。

在路由上执行时，先装工具（基础固件内**没有** `resize2fs`，且 25.12 源里**没有** `sgdisk`/`parted`）：

```sh
apk update && apk add resize2fs sfdisk
```

再用脚本输出的那一行命令扩分区。**整盘设备**指分区所属的那块盘（如系统分区是 `/dev/sda2`，
整盘就是 `/dev/sda`）。**起点必须与脚本显示的一致，否则会损坏文件系统**：

```sh
# 起点 33280、尺寸 4160991 由 openwrt-install 的检测结果给出，请照抄
echo 'start=33280, size=4160991' | sfdisk -N 2 --force /dev/sda
```

`sfdisk -N` 会自动修正 GPT：把备份分区表移到盘尾、更新保护性 MBR、抬高可用末 LBA，
无需手工计算扇区。最后扩文件系统：

```sh
e2fsck -fy /dev/sda2
resize2fs /dev/sda2
```

**也可以在 Linux 主机上做**（工具齐全，更稳妥）：把盘接到 Linux 主机或 U 盘启动 Linux，
把 `/dev/sda` / `/dev/sda2` 换成实际盘符后执行同样三条命令即可。

重启后用 `df -h /` 确认根分区已变为整盘大小。
