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
- **rootfs 分区 2048 MiB**（官方默认仅约 104 MiB，见下文「空间与扩容」）
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

固件内嵌的 GPT 只描述镜像自身大小，**写入大容量硬盘后分区不会自动占满整盘**。

本固件的约定是：**rootfs 分区固定 2048 MiB**（官方默认仅约 104 MiB），
磁盘剩余空间**保持未分配**，不扩满整盘、也不自动建数据分区。
需要的话你可以自己把剩余空间建成数据分区（见文末）。

由于镜像内 rootfs 已经是 2 GiB，且已内置 `resize2fs` 与 `sfdisk`，
正常情况下**装完无需任何操作**。`openwrt-install` 写盘后会只读检测并说明：

```
[INFO] 系统分区     : /dev/sda2  (2048 MiB, ext4)
[INFO] rootfs 分区 2048 MiB (已达目标 2048 MiB) ✅
[INFO] 剩余空间保持未分配, 未创建数据分区(本固件的约定)
```

### 什么时候需要扩容

只有当你刷入的镜像 rootfs 小于 2 GiB（例如官方原版镜像）时，脚本才会给出扩容命令：

```sh
# 起点与尺寸由 openwrt-install 的检测结果给出，请照抄它的输出
echo 'start=33280, size=4194304' | sfdisk -N 2 --force /dev/sda
e2fsck -fy /dev/sda2
resize2fs /dev/sda2
```

**起点必须与脚本显示的一致，否则会损坏文件系统。** `sfdisk -N` 会自动修正 GPT
（把备份分区表移到盘尾、更新保护性 MBR、抬高可用末 LBA），无需手工计算扇区；
若提示设备忙，追加 `--no-reread`，之后用 `partx -u /dev/sda` 让内核重读。

> squashfs 版根文件系统为只读，扩容语义不同（需把新空间做成 overlay），脚本会另行提示。

### 想用剩余空间建数据分区（可选，手动）

`openwrt-install` 不会自动做这件事，按下面步骤自行操作（把 `/dev/sda` 换成实际盘符；
起始扇区请取 `openwrt-install` 输出里的 rootfs 末端 + 1）：

```sh
# 建分区 3（起始扇区留出前两个分区，尺寸留 33 个扇区给备份 GPT）
echo 'start=4227584, size=<根据磁盘大小填写>' | sfdisk -N 3 --force /dev/sda
mkfs.ext4 -F /dev/sda3
blkid /dev/sda3                      # 记下 UUID
mkdir -p /mnt/data
mount /dev/sda3 /mnt/data
```

开机自动挂载：在 `/etc/config/fstab` 写入

```
config mount
    option target   '/mnt/data'
    option uuid     '<上面的UUID>'
    option enabled  '1'
```

然后 `/etc/init.d/fstab enable && /etc/init.d/fstab restart`。
用 UUID 而非 `/dev/sda3` 更稳妥（设备名可能变化）。
