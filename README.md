# OpenWrt 25.12 定制固件

GitHub Actions 在线自动构建 OpenWrt 25.12 x86_64 固件（基于官方 ImageBuilder）。

## 功能

- **OpenWrt 25.12** (x86_64 / UEFI, squashfs + ext4)
- **OpenClash** 科学上网插件
- **OpenAppFilter (OAF)** 应用过滤
- **Realtek RTL8111/8168** 内置有线网卡驱动 (r8169)
- **RTL8153** USB 网卡驱动 (`kmod-usb-net-rtl8152`)
- **MT7922** 无线网卡驱动 (mt7921e + 固件)
- **USB / SATA / NVMe** 存储与内置盘支持
- **LuCI 中文界面 + HTTPS**
- **rootfs 分区 1024 MiB**（官方默认仅约 104 MiB，见下文「空间与扩容」）
- **内置 `resize2fs` + `sfdisk`**，装到内置盘后可直接扩容
- **内置 `openwrt-install`** 一键安装到内置硬盘命令

## 网络默认

| 接口 | 网卡 | 用途 |
|------|------|------|
| LAN | eth1 | 桥接, 管理地址 `10.0.0.1` |
| WAN | eth0 | DHCP 自动获取 |

防火墙为 OpenWrt 默认策略（WAN 拒绝入站，仅内网可管理）。

## 为什么用 ImageBuilder 而不是源码编译

原先的 `make world` 流程每次都从源码编译整个工具链，其中 `tools/llvm-bpf` 会编译
**LLVM 21.1.6**（3898 个 C++ 目标单元）。实测在 4 核 runner 上光 LLVM 就需约
**4.5 小时**，而 workflow 给该步的超时是 280 分钟 —— **必然超时**。现象是日志长时间
静止、看起来像卡死（LLVM 编译是长时间无输出的单次编译，并非进程死亡）。

改用官方 **ImageBuilder** 组装固件后，实测**几分钟**完成，功能完全等价：
可自由选包、可加第三方插件、可注入自定义文件。

## 自动构建

- `push` 到 `main`（修改 `workflow` / `files/**` / `scripts/**` / `README.md` 时）
- 手动触发：Actions → Build OpenWrt 25.12 (ImageBuilder) → Run workflow
- 定时：每周日北京时间 11:00 检查上游是否有新 release，有才构建

产物在每次 Run 的 **Artifacts** 和 **Release (`firmware` tag)** 中，同时包含两个变体：

| 文件 | 根文件系统 | 说明 |
|------|-----------|------|
| `*squashfs-combined-efi.img.gz` | squashfs（只读） | 抗写坏，支持一键恢复出厂 |
| `*ext4-combined-efi.img.gz` | ext4（可写） | 可直接扩容，适合内置盘长期使用 |

两者都能启动，按需求选一个刷。

## 刷机

1. 下载 `*combined-efi.img.gz`
2. 用 Rufus（DD 模式）/ Etcher / dd 写入 U 盘
3. U 盘启动，系统起来后执行 `openwrt-install` 安装到内置硬盘
4. 默认登录：`http://10.0.0.1`，首次需 `passwd` 设置密码

## 空间与扩容

固件内嵌的 GPT 只描述镜像自身大小，**写入大容量硬盘后分区不会自动占满整盘** ——
必须重写 GPT + 扩分区 + 扩文件系统三步。

本固件已把 rootfs 分区做到 **1024 MiB**（官方默认仅约 104 MiB），并且内置了
`resize2fs` 与 `sfdisk`，因此**可以直接在路由器上扩容**。

`openwrt-install` 写盘后会**只读检测**并给出针对你磁盘的具体命令（不会自动改分区表）。
例如 120 GiB 盘会输出：

```
[INFO] 系统分区     : /dev/sda2  (1024 MiB, ext4)
[WARN] 分区未占满磁盘: 可再扩约 121840 MiB
[INFO]             分区 1024 MiB -> 122864 MiB
```

### 扩容步骤（ext4 版）

> 已在 `openwrt-25.12.5 combined-efi` 镜像上实测通过。squashfs 版扩容语义不同，脚本会另行提示。

按脚本输出的命令执行即可。整盘设备指分区所属的那块盘（系统分区 `/dev/sda2`
则整盘是 `/dev/sda`）。**起点必须与脚本显示的一致，否则会损坏文件系统**：

```sh
# 起点与尺寸由 openwrt-install 的检测结果给出，请照抄它的输出
echo 'start=33280, size=251624927' | sfdisk -N 2 --force /dev/sda
e2fsck -fy /dev/sda2
resize2fs /dev/sda2
```

`sfdisk -N` 会自动修正 GPT：把备份分区表移到盘尾、更新保护性 MBR、抬高可用末 LBA，
无需手工计算扇区。若提示设备忙，给它加 `--no-reread`，之后用 `partx -u /dev/sda`
让内核重读分区表。

重启后用 `df -h /` 确认根分区已变为整盘大小。

## 仓库结构

| 路径 | 作用 |
|------|------|
| `.github/workflows/build-openwrt.yml` | ImageBuilder 构建流程 |
| `scripts/packages.list` | 固件包含的软件包清单（唯一来源） |
| `files/` | 注入固件的自定义文件（`/etc/config/network`、`/usr/bin/openwrt-install`） |

## 注意事项

- **镜像版本与 OAF 内核模块必须匹配**：OAF 的预编译内核模块按特定内核版本编译，
  版本不一致会因 ABI 不匹配而安装失败。workflow 会先校验并在不匹配时明确报错。
  已知组合：`OAF v7.0.1` ↔ `25.12.5`(内核 6.12.94)，`v6.1.7` ↔ `25.12.0`(6.12.71)。
- 原 `diy-part1.sh` / `diy-part2.sh` / `.config` 已移除：第三方源与自定义文件由
  workflow 和 `files/` 直接处理，`scripts/packages.list` 取代了 `.config` 的包选择。
