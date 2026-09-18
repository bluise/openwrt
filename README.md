# OpenWrt 25.12 定制固件

GitHub Actions 在线自动构建 OpenWrt 25.12 x86_64 固件（基于官方 ImageBuilder）。

## 功能

- **OpenWrt 25.12** (x86_64 / UEFI, squashfs + ext4)
- **OpenClash** 科学上网插件
- **OpenAppFilter (OAF)** 应用过滤（含中文界面：内置 `luci-i18n-oaf-zh-cn` 语言包）
- **Realtek RTL8111/8168** 内置有线网卡驱动 (r8169)
- **RTL8153** USB 网卡驱动 (`kmod-usb-net-rtl8152`)
- **MT7922** 无线网卡驱动 (mt7921e + 固件)
- **USB / SATA / NVMe** 存储与内置盘支持
- **LuCI 中文界面 + HTTPS**
- **rootfs 分区 2048 MiB**（官方默认仅约 104 MiB，见下文「空间与扩容」）
- **内置 `resize2fs` + `sfdisk`**，装到内置盘后可直接扩容
- **内置 `block-mount`**，自建的数据分区可开机自动挂载（见文末）
- **内置 `openwrt` 命令**（`openwrt-install` 的快捷入口）打开交互式安装助手（装到内置硬盘 / 改 LAN IP / 改密码 / 网口模式 / 查看磁盘与网口）

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

## 安装步骤

### 一、准备固件

从 **Release（`firmware` tag）** 或某次 Run 的 **Artifacts** 下载，二选一：

| 文件 | 根文件系统 | 适合 |
|------|-----------|------|
| `*ext4-combined-efi.img.gz` | ext4（可写） | 内置盘长期使用（推荐） |
| `*squashfs-combined-efi.img.gz` | squashfs（只读） | 抗写坏、可一键恢复出厂 |

两者均支持 **UEFI 与传统 BIOS** 双启动。

### 二、写入 U 盘（≥ 512 MB 即可）

Linux / macOS：

```sh
gunzip -c openwrt-*-combined-efi.img.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

⚠️ `/dev/sdX` 是**整个 U 盘设备**（如 `/dev/sdb`），**不要**写成分区（`/dev/sdb1`）。

Windows：用 **Rufus** 选 **DD 模式**（不要用 ISO 模式，会破坏分区表），或 Etcher。

### 三、U 盘启动

开机按 F2 / F11 / Del 进启动菜单，选择 U 盘。UEFI 机器选带 `UEFI:` 前缀的那一项。

### 四、安装到内置硬盘

系统起来后（默认地址 `http://10.0.0.1`），SSH 或接显示器登录，执行：

```sh
openwrt
```

（`openwrt` 是快捷入口，等价于 `openwrt-install`；也可用后者，或 `openwrt-install --no-menu` 直接安装）

会显示**交互式菜单**（类似 iStoreOS 的 `quickstart`）：

```
┌──────────── OpenWrt 安装助手 ────────────┐
│  1) 安装系统到内置硬盘 (会清空目标盘!)    │
│  2) 查看磁盘与空间状态                    │
│  3) 修改 LAN 口 IP 地址                   │
│  4) 修改 root 密码                        │
│  5) 查看网络接口                          │
│  6) 显示扩容命令(如需要)                  │
│  7) 设置网口模式(单网卡/双网卡)           │
│  8) 诊断(装不上时先看这个)                │
│  0) 退出                                  │
└───────────────────────────────────────────┘
```

**退出菜单**：选 `0`、按 `Esc`、或点"退出"按钮都可以（纯文本菜单还可以输 `q`，
Ctrl+D 也行）—— 不会出现"退不出去"的情况。

**安装失败一定会看得到原因**：安装过程既实时显示，也同步存一份日志，结束后用对话框
把**完整过程**呈现出来（可上下翻页），标题会写 `安装完成` 还是 `安装失败 / 返回码 N`。
以前失败信息会被菜单重绘立刻刷掉，看着就像"装不上但没有任何提示"。

### 菜单里中文是乱码怎么办

> 一句话：**本机控制台（`TERM=linux`）永远显示不了中文**——那种终端没有中文字形，
> 脚本会自动改用纯 ASCII 英文界面。乱码只会出现在"该终端不支持中文"的情况下。

`whiptail` 基于 newt + slang，而 musl **没有 locale 数据**、固件默认也不设 `LANG`。
slang 是靠 `setlocale`/`nl_langinfo`/`LC_ALL`/`LC_CTYPE` 判断"要不要进 UTF-8 模式"的：
判定失败时它把每个汉字当成两个单字节字符，宽度算错，于是边框画歪、条目串行
（看着就是乱码），底部的"退出"也可能看不到、点不准。

脚本现在会自己设 `LC_ALL=C.UTF-8`，让 slang 进入 UTF-8 模式（libnewt 编译时带了
`_newt_wstrlen`，会用 `mbrtowc`/`wcwidth` 按双宽计算），中文就正常了。

如果还有乱码，说明**终端本身显示不了中文**（本机控制台没有中文字形，或 SSH 客户端
用的是 GBK 编码），此时用纯 ASCII 英文界面：

```sh
openwrt-install --en     # 或 OPENWRT_UI=en openwrt-install
```

`TERM` 为 `linux`/`dumb`/空（通常就是本机控制台）时会**自动**用英文界面；
用 `--zh` 可以强制回中文。哪一种是你的情况，看 `echo $TERM` 和 SSH 客户端的编码设置。

**英文界面是"全英文"**：菜单、对话框、倒计时、磁盘/固件搜索日志、空间报告、
用法说明全部是 ASCII，不会再夹着汉字乱码。

### 装不上时怎么排查

菜单里选 `8`（或跑 `openwrt-install --diag`）会打印一份诊断，一眼看清哪一步不满足：

- 识别到的整盘、各自容量型号
- 启动盘解析结果（`/rom` 的源设备 → 整盘）与**每块盘为什么被排除/入选**
- 所有分区归属哪块盘、是不是 USB
- 固件镜像在 `/mnt`、`/media`、`/boot`、`/mnt/usb` 里到底找到没有
- `whiptail`/`sfdisk`/`resize2fs`/`e2fsck`/`gunzip` 等工具在不在
- 磁盘挂载情况与空闲空间

两个最常见的失败原因：

1. **找不到固件**：`openwrt-*-combined-efi.img.gz` 没放在设备上。
   安装器只负责"把某个镜像文件写到某块盘"，**它里面不含固件**。它会按顺序找：
   `/mnt` `/media` `/boot` `/mnt/usb` `/root` `/home` `/tmp` `/var/tmp` `/opt`
   和当前目录，还会尝试自动挂载 USB 分区。

   都找不到时（有终端的情况下）它会**一步步带你解决**，而不是丢一句错误：
   - 先把整个系统扫一遍（`*.img.gz` / `*.img`），用可滚动的框列出候选，
     你可以**输编号**挑，或直接**输完整路径**、甚至**输一个目录**（会在里面找）
   - 还是没有？直接问你要不要**从 GitHub 下载**（自动按 `/etc/openwrt_release`
     的版本拼出正确文件名，ext4 还是 squashfs 由你选；需要设备能联网，存到 `/tmp`）
   - 非交互场景（`--no-menu`）不提问，只打印可照抄的命令并返回菜单

   任何时候也可以显式指定：`openwrt-install --no-menu --fw /root/xxx.img.gz`
   （`--fw` 与"把路径作为最后一个参数"等价）
2. **只有一块盘、而它正是当前启动盘**：脚本会**拒绝**写它（避免把正在运行的
   系统就地清空）。要么从 U 盘启动后再装，要么用 `sysupgrade` 升级。

**目标盘要够大**：镜像解压后是 **2064 MiB**，所以目标盘至少 2.2 GB（VirtualBox 里
挂个 "2 GB" 的虚拟盘是 2048 MB，**正好写不下**——建议直接给 4 GB）。
写入前脚本会预检容量，不足时明确告诉你"需要 X MiB，而 /dev/sdX 只有 Y MiB"，
不会再让你对着 `dd: No space left on device` 猜。

选 `1` 安装，脚本会：
1. 自动识别**可写入的硬盘**：排除当前启动盘与所有 USB 设备（判据直接读 sysfs，
   不依赖固件里根本没有的 `lsblk`）
2. 自动查找 U 盘上的固件镜像
3. 显示目标盘（型号 + 容量）并**倒计时 5 秒**（此时 Ctrl+C 可取消）—— **会清空目标盘所有数据**
4. 写入镜像
5. 只读检测空间并说明结果

### 目标盘是怎么选的（多块盘必看）

```
--disk 显式指定  >  唯一候选盘  >  列出让你选
排除项: 当前启动盘(经 sysfs slaves 解析 dm/md 叠加) + 所有 USB 设备
```

- **唯一候选**：直接用，日志里会打印它是哪块盘、多大、什么型号
- **多块候选**：列出编号让你输入，**不会替你猜**
- **非交互环境**（脚本里跑 `--no-menu`，没有终端）：多块候选时**直接报错退出**，
  必须用 `--disk /dev/sdX` 指定 —— 宁可失败，不押注哪块盘
- **`--disk` 指定了启动盘**会被拒绝（避免把正在运行的系统就地清空）
- 指定 USB 设备是允许的（比如你要装到 USB 硬盘盒），但会打印警告

> 判断"是不是 USB"读的是 sysfs 路径里有没有 `/usbN` 这一段，不是 `removable`：
> USB 硬盘盒的 `removable` 常为 0、读卡器又常为 1，都不能当判据。

### 命令行用法（非交互）

```sh
openwrt                            # 打开菜单(带方向键选择)
openwrt-install --no-menu          # 跳过菜单, 直接一键安装
openwrt-install --change-ip        # 只改 LAN 口 IP
openwrt-install --en               # 英文(纯 ASCII)菜单与全部输出, 中文乱码时用
openwrt-install --diag             # 诊断: 磁盘/启动盘/候选判定/固件搜索/工具
openwrt-install -h                 # 查看全部用法
openwrt-install --no-menu /path/to/openwrt-*.img.gz   # 指定固件
openwrt-install --no-menu --fw /root/openwrt-*.img.gz # 同上, 用 --fw 指定固件
openwrt-install --no-menu --disk /dev/sdb             # 指定目标盘(多块盘时必用)
```

> 菜单界面由 `whiptail` 提供（已内置）。若在没有终端的环境调用，脚本会自动回退为纯文本交互，不会卡住。

### 五、重启与首次登录

```sh
# 拔掉 U 盘后重启
reboot
```

重启后访问 **http://10.0.0.1**（LAN 口 **eth1**），**首次必须设置密码**：

```sh
passwd
```

然后即可用 `root` + 新密码登录 LuCI（`https://10.0.0.1`）。

### 六、确认空间

本固件 rootfs 已固定 **2048 MiB**，正常情况下**装完无需任何操作**，脚本会显示：

```
[INFO] rootfs 分区 2048 MiB (已达目标 2048 MiB) ✅
[INFO] 剩余空间保持未分配, 未创建数据分区(本固件的约定)
```

若显示的是扩容提示，见下一节。

## 网口模式（单网卡 / 双网卡）

镜像默认网络配置是 **eth1 = LAN、eth0 = WAN**（双网卡机型的常见布局）。
但**单网卡机器**（只有一个网口，或该口不叫 eth1）会出现"只有 WAN、没有 LAN 口"，
表现为插上网线访问不了 `10.0.0.1` 管理页面。

菜单里选 `7`（**设置网口模式**），脚本会自动列出检测到的物理网口，然后按需切换：

| 模式 | 行为 | 适用 |
|------|------|------|
| **单网卡模式** | 唯一网口作为 **LAN**（静态 IP，直接可管理） | 单网口小主机、软路由 |
| **双网卡模式** | 第一个口作 **WAN**(DHCP)，其余口作 **LAN** 桥 | 多网口机型 |
| **自动判断** | 按实际网口数量自动选上面之一 | 不确定时用这个 |

被测到的物理网口会排除 `lo`、网桥（`br-*`）、Docker 虚拟口等，只保留真网卡。

> 需要 USB 网卡时已内置 `kmod-usb-net-rtl8152`(RTL8153) 等驱动。

手动等价操作（单网卡为例）：

```sh
uci delete network.wan
uci delete network.wan6
uci set network.lan.device='eth0'
uci commit network
/etc/init.d/network reload
```

## 修改 LAN 口 IP

菜单里选 `3`（或执行 `openwrt-install --change-ip`），输入新 IP 即可：

```
请输入新的 LAN 口 IP 地址 (当前 10.0.0.1): 192.168.2.1
```

脚本会校验地址合法性，确认后写入 `uci` 并热重载网络。**修改后当前连接会断开**，
需要访问新地址（或让电脑重新获取 DHCP）。

手动等价操作：

```sh
uci set network.lan.ipaddr='192.168.2.1'
uci commit network
/etc/init.d/network reload
```

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

> 这一步依赖 **`block-mount`**（提供 `/etc/config/fstab` 与 `/etc/init.d/fstab`），
> 本固件已内置；`mkfs.ext4` / `e2fsck` 由缺省已装的 `e2fsprogs` 提供。
