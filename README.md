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

## 瘦客户机启动卡在 "Booting OpenWrt"（Dell Wyse 3040 / HP t640 等）

**已修**。官方 x86 镜像生成的内核命令行是：

```
console=tty1 console=ttyS0,115200n8
```

某些瘦客户机/嵌入式固件会**谎报"存在串口"**：内核把 `ttyS0` 注册成 console 之后，
`printk` 写这个实际不工作的 UART 会卡住 —— 现象就是 GRUB 之后停在
`Booting OpenWrt` 再也不动，连内核日志都出不来。

- 上游已知问题：[openwrt/openwrt#22598](https://github.com/openwrt/openwrt/issues/22598)
  （Dell Wyse 3040 / HP t640 / ESXi 都有复现；VirtualBox 正常，因为它的固件不会谎报串口；
  iStoreOS 的盘也正常，因为它的命令行里没有 `ttyS0`）
- 本固件在 `make image` **之前**删掉 ImageBuilder 里生成这半截命令行的那一行
  （`target/linux/x86/image/Makefile`），于是镜像里直接生成干净的 `console=tty1`；
  **GRUB 自己的串口终端保留**，接了串口线的人仍能在 GRUB 阶段看到菜单
- 构建末尾有自检：把镜像的 ESP 分区抠出来读真正的 `/boot/grub/grub.cfg`，
  一旦又出现 `ttyS0` 就让构建**失败**，不会悄悄发出一个会卡的固件
- 如果你确实想要内核串口输出：在 GRUB 菜单按 `e`，给启动项补回
  `console=ttyS0,115200n8` 即可（只对这一次启动生效）
- 刷**旧版镜像**（本次修复之前构建的）遇到这个卡顿：同样按 `e` 删掉
  `console=ttyS0,115200n8` 再按 F10 就能启动

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
│  1) 安装系统到内置硬盘 (克隆, 会清空!)    │
│  2) 修改 LAN 口 IP 地址                   │
│  3) 修改 root 密码                        │
│  4) 查看网络接口                          │
│  5) 设置网口模式(单网卡/双网卡)           │
│  6) 诊断(装不上时先看这个)                │
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

菜单里选 `6`（或跑 `openwrt-install --diag`）会打印一份诊断，一眼看清哪一步不满足：

- 识别到的整盘、各自容量型号
- 启动盘解析结果（`/rom` 的源设备 → 整盘）与**每块盘为什么被排除/入选**
- 所有分区归属哪块盘、是不是 USB
- 克隆安装的源盘是哪个、它每个分区的 `start/size/type/uuid`（`sfdisk -d` 原始输出）
  以及**逐分区要复制多少 MiB、合计多少**（这一步就是上面那个"整盘长度"bug 的可见化）
- `whiptail`/`sfdisk`/`resize2fs`/`e2fsck`/`gunzip` 等工具在不在
- 磁盘挂载情况与空闲空间

最常见的失败原因：

1. **目标盘不够大**：装进去的内容 = **系统分区本身**（ext4 版约 2.1 GB：
   16 MiB 的 `/boot` + 2 GiB 的 rootfs），不是整块 U 盘。所以 4 GB 以上的盘就够，
   内置 eMMC/NVMe 通常都满足。写入前脚本会预检容量，不足时明确告诉你
   "需要 X MiB，而 /dev/sdX 只有 Y MiB"，不会让你对着 `dd: No space left on device` 猜。
   > 早期版本这里是错的：它按"分区表里最后一个分区的末尾"算长度，而**分区表里的
   > 分区可能被扩容到整盘**（比如 U 盘 128 GB，rootfs 分区被 `sfdisk -N` 扩到盘尾），
   > 于是对着 7.2 GiB 的内置盘报"需要 122105 MiB，目标盘太小" —— 完全装不上。
   > 现在改成：分区表用 `sfdisk -d` 读，复制长度用**文件系统自己的大小**
   > （ext4 超级块里的块数 / squashfs 的 `bytes_used`），分区表被扩容也不受影响。
2. **只有一块盘、而它正是当前启动盘**：脚本会**拒绝**写它（避免把正在运行的
   系统就地清空）。要么从别的介质启动后再装，要么用 `sysupgrade` 升级。
3. **认不出启动介质**：克隆安装需要知道"当前是从哪块盘启动的"。诊断里
   `clone install source` 那一行如果是"认不出…"，就把当时的 `--diag` 输出发出来。

选 `1` 安装，脚本会：
1. 自动识别**可写入的硬盘**：排除当前启动盘、有分区在挂载的盘、以及所有 USB 设备
   （判据直接读 sysfs，不依赖固件里根本没有的 `lsblk`）
2. **把当前运行的这套系统的分区装过去**（不找镜像、不联网）：逐分区复制 + 在目标盘上
   重建分区表（`start`/`type`/`uuid` 照抄源盘，所以 PARTUUID 不变、grub 不用改），
   ext4 版的 rootfs 分区顺带扩到盘尾，并在装完后 `e2fsck -f -y` + `resize2fs` 扩文件系统
3. 显示目标盘（型号 + 容量）并**倒计时 5 秒**（此时 Ctrl+C 可取消）—— **会清空目标盘所有数据**
4. 复制 + 写分区表 + 扩容
5. 只读检测空间并说明结果

### 安装方式：克隆当前系统（不用镜像文件、不用网络）

**这是默认也是唯一的安装方式。** 用 dd 写出来的启动介质里只有系统本身，没有
`.img.gz` 文件（ESP 只有 16 MiB 装不下 35 MB 的镜像；rootfs 是只读 squashfs 也放不下），
而刷机时机器通常根本没有网络 —— 所以安装器**不搜索镜像文件、也不提供下载**，
直接把当前运行的这套系统整盘复制到目标盘。

- 菜单里选 `1` 就是克隆安装；命令行 `openwrt-install`（或 `--no-menu`）同理
- 完全不需要镜像文件、不需要网络
- **不是整盘 dd**：把源盘上"rootfs 之前的分区（`/boot` 等启动链）+ rootfs 本身"
  按原偏移复制到目标盘，rootfs 之后的分区（数据盘、旧 overlay）不复制
  —— 所以 **128 GB 的 U 盘也能装进 7.2 GB 的内置盘**，实际写入量约 2.1 GB
- 目标盘上重建 GPT：`start`/`type`/`attrs` 与分区号（1 / 2 / 128）**照抄源盘**，
  但 `uuid` **重新生成**（每个分区一套新的）⇒ 两块盘的 PARTUUID 不再相同
- 目标盘里所有引用旧 UUID 的地方会一起改掉：ESP 上的 `/boot/grub/grub.cfg`
  （`root=PARTUUID=...`，含 failsafe 那行）以及 `/etc/config/fstab` 之类按 UUID 挂载的配置
  —— 所以**两块盘各自引导到自己的系统**，互不干扰（`--same-uuid` 可退回"逐字节等价克隆"）
- **整盘安装**：装到内置盘时不会只占 2 GiB ——
  - **ext4 版**：rootfs 分区扩到盘尾，装完 `e2fsck -f -y` + `resize2fs`，并**自证**
    （日志会打印"根分区 X MiB / 根文件系统 Y MiB / ✅ 整盘安装"；若文件系统没扩上会明确告警并给出
    `resize2fs` 命令）
  - **squashfs 版**：根是只读的扩不了，于是把剩余空间建成一个 `rootfs_data` 分区
    （OpenWrt 首次启动把它格式化/挂载成可写层 `/overlay`），整块盘同样不浪费
  - 例如 7.2 GB 的内置盘 → 约 7.3 GB 可用于根文件系统
- **装完建议拔掉 U 盘再启动**：现在目标盘有自己的 UUID、`grub.cfg` 也指向它自己，
  两块盘同时插着不会互相抢根分区；但机器的 uEFI 可能仍优先从内置盘启动
  （想用优盘启动时开机按 **F12** 选它）
- 特殊场景想要"写指定的镜像文件"仍然可以：`openwrt-install --fw /root/xxx.img.gz`
  （或把路径作为最后一个参数）—— 只是平时用不到

> 这正是 iStoreOS 的做法：它的 `quickstart` → `Install X86` 直接把自己运行的那块盘
> `dd` 到内置盘（见其源码 `istoreos/quickstart` 的 `backend/cmd/backend/prompt.go`），
> 所以它也不需要联网。

### 目标盘是怎么选的（多块盘必看）

```
--disk 显式指定  >  唯一候选盘(仍要你确认一次)  >  弹菜单让你选
只排除两项: 1) 当前正在启动的那块盘(写它等于把自己写死)  2) 所有 USB 设备
选项一律是"整盘"粒度(sda / sdb …), 不显示分区 —— 因为是整盘覆盖
确认框里会写明: 盘符 + 容量型号, 避免"装错盘"
```

- **唯一候选**：也会先弹一个确认框（写明盘符、容量、型号），点了"就用这块盘"才继续
  —— 不会出现"没问我，直接就开克隆了"。非交互环境（脚本调用）才自动采用并写明日志
- **多块候选**：弹**菜单**（方向键 + 回车，`Esc` 取消）让你选，**不会替你猜**
- **非交互环境**（脚本里跑 `--no-menu`，没有终端）：多块候选时**直接报错退出**，
  必须用 `--disk /dev/sdX` 指定 —— 宁可失败，不押注哪块盘
- **只有"当前启动的那块盘"会被拒绝**（写它等于把正在运行的系统当场写没）
- 目标盘上如果有分区正在被挂载（老系统残留、或被自动挂载），安装器会**先尽力卸载，
  然后照写不误**（整盘覆盖本来就会覆盖它们），只提示一句"当前运行的系统可能变得不稳定"
- 指定 USB 设备是允许的（比如你要装到 USB 硬盘盒），但会打印警告
- **装不上几乎只剩一种原因**：你选的那块盘=**当前启动的那块盘**（会被拒绝，因为写它等于
  自杀）。换一块盘，或从别的介质启动
- 想确认盘的情况：`openwrt-install --diag`（诊断里会列出每块盘、容量型号、挂载情况）
- 每一块盘的挂载情况都会打印出来（形如 `/dev/sda3@/mnt/sda3`），诊断里也有

> 判断"是不是 USB"读的是 sysfs 路径里有没有 `/usbN` 这一段，不是 `removable`：
> USB 硬盘盒的 `removable` 常为 0、读卡器又常为 1，都不能当判据。

### 命令行用法（非交互）

```sh
openwrt                            # 打开菜单(带方向键选择)
openwrt-install --no-menu          # 跳过菜单, 直接一键安装
openwrt-install --change-ip        # 只改 LAN 口 IP
openwrt-install --en               # 英文(纯 ASCII)菜单与全部输出, 中文乱码时用
openwrt-install --diag             # 诊断: 磁盘/启动盘/候选判定/克隆源/工具
openwrt-install -h                 # 查看全部用法
# 下面两条是"可选"的: 平时安装走克隆, 不需要镜像文件
openwrt-install --no-menu /path/to/openwrt-*.img.gz   # 改成写指定的镜像文件
openwrt-install --no-menu --fw /root/openwrt-*.img.gz # 同上, 用 --fw 指定
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

**克隆安装（ext4 版）**：装完脚本已经自动把 rootfs 分区扩到盘尾并 `resize2fs`，
所以 7.2 GB 的内置盘就是 **约 7.3 GB 可用的根文件系统**，无需任何手工操作。日志末尾会显示：

```
[INFO] rootfs 分区 7456 MiB —— 已占满整盘 ✅
[INFO] 克隆安装已自动扩到盘尾, 不需要再手动扩容。
```

**写镜像（`--fw`）或 squashfs 版**：rootfs 保持镜像里的 2048 MiB，剩余空间未分配，
日志会明确写出"剩余空间保持未分配"。想手动扩容时脚本会打印具体命令（见下一节）。

## 网口模式（单网卡 / 双网卡）

镜像默认网络配置是 **eth1 = LAN、eth0 = WAN**（双网卡机型的常见布局）。
但**单网卡机器**（只有一个网口，或该口不叫 eth1）会出现"只有 WAN、没有 LAN 口"，
表现为插上网线访问不了 `10.0.0.1` 管理页面。

菜单里选 `5`（**设置网口模式**），脚本会自动列出检测到的物理网口，然后按需切换：

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

菜单里选 `2`（或执行 `openwrt-install --change-ip`），输入新 IP 即可：

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

## 内置的额外组件

### Argon 主题（iStoreOS 就是基于它的）

- 官方源里**没有** `luci-theme-argon`（iStoreOS 用的是自己 fork 的版本），所以构建时把
  它源码里的文件直接打进固件：`htdocs/*` → `/www/`、`ucode/*` → `/usr/share/ucode/`、
  `root/*` → `/`（其中 `etc/uci-defaults/30_luci-theme-argon` 会在**首次启动**把 Argon
  设为默认主题：`luci.main.mediaurlbase=/luci-static/argon`）
- 版本：`luci-theme-argon` 2.4.7（20260824，commit `182294b0`）—— 钉在 workflow 的
  `ARGON_SHA` 里，升级只需改这一个变量
- 想切回官方默认主题：LuCI → 系统 → 系统 → 语言和界面 → 设计主题；或 SSH：
  ```sh
  uci set luci.main.mediaurlbase=/luci-static/bootstrap && uci commit luci
  ```

### DDNS-GO（自带 LuCI 页面，界面中文）

- 官方源里没有 `ddns-go`，构建时直接用上游 release 的 **linux_x86_64 静态二进制**
  （v6.17.7，约 11 MB）放进 `/usr/bin/ddns-go`（构建时会校验它是静态链接且能 `-v`）
- 服务由 procd 托管：`/etc/init.d/ddns-go`，配置 `/etc/config/ddns-go`
  ```sh
  uci show ddns-go
  uci set ddns-go.main.port=9876        # 网页配置界面端口
  uci set ddns-go.main.frequency=300    # 检查公网 IP 的频率(秒)
  uci set ddns-go.main.enabled=1        # 开机自启
  /etc/init.d/ddns-go restart
  ```
- **LuCI 页面**：菜单 **服务 → DDNS-GO**（Lua 实现，中文界面）—— 显示运行状态 / PID /
  开机自启 / 检查频率，并带"启动、停止、重启、打开配置页面"按钮
- **配置本身**在 DDNS-GO 自带的中文网页界面：`http://路由器IP:9876`
  （第一次进去要先设置用户名密码，然后添加你的域名与 DNS 服务商）
- 配置文件：`/etc/ddns-go/config.yaml`；日志：`logread | grep ddns-go`
- 为它和主题额外装的包：`luci-compat` + `luci-lua-runtime`（Lua 版 LuCI 页面需要）、
  `jsonfilter` + `wget-ssl`（Argon 主题的壁纸脚本需要）

> 这两个组件都不是"从源码编译"的：主题是纯静态文件，DDNS-GO 是上游发布的静态二进制，
> 所以 ImageBuilder 就够用，不需要 SDK 编译环境。

### 装完后主板还是从内置盘启动（"优盘启动不了"）

这有两层原因，别混：

1. **分区 UUID 相同**（已修）：老版本克隆时连分区表一起照抄，内核按
   `root=PARTUUID=` 找根分区时两块盘都匹配，于是"用优盘启动却进了内置盘的系统"。
   现在装到内置盘时会**给目标盘生成一套新 UUID**，并同步改掉 ESP 上的
   `/boot/grub/grub.cfg`（`root=PARTUUID=...`）和 `fstab` 里的引用 —— 两块盘各自独立。
2. **主板的 UEFI 启动项顺序**（系统里改不了，只能用 `efibootmgr`）：内置盘装好系统后，
   主板会给它建一个启动项，Dell 这类机器之后就**一直从内置盘启动** —— 在 BIOS 里把
   USB 调到"第一"往往也不管用，因为 UEFI 看的是 NVRAM 里的 `BootOrder`，不是设备顺序。

对这一层，镜像里现在内置了 `efibootmgr`，可以一条命令把当前这块优盘排到第一位：

```sh
openwrt-install --boot-order-list   # 先看看现在有哪些启动项、顺序如何
openwrt-install --boot-order        # 把当前启动的这块盘(优盘)排到第一位
```

（它靠"当前启动盘的 ESP PARTUUID"在启动项里认出优盘那一条；认不出就自动创建一条
`OpenWrt (USB)`。有些固件不允许从系统改，那就按下面的办法手动来。）

**不用这套工具的手动办法**（任何机器都成立）：

- 开机按 **F12**（Dell 的一次性启动菜单）→ 选 `UEFI: <你的优盘>`
- 或者 **F2** 进 BIOS → Boot Sequence → 选中内置盘那一项按 **Delete** 删掉它
- 或者干脆把内置盘的引导记录清掉（反正要重装）：
  ```sh
  dd if=/dev/zero of=/dev/mmcblk1 bs=1M count=16 conv=fsync   # 清掉 GPT+ESP
  sync; reboot            # 内置盘没有可引导的东西了, 固件只能走优盘
  ```

### Dell Wyse 3040 的无线网卡（已集成驱动）

Wyse 3040 的无线模块是 **Marvell 88W8897**（模块型号 **AzureWave AW-CM389MA**），
是 **SDIO** 卡不是 PCIe 卡，所以固件里需要的不只是 WiFi 驱动，还要 MMC/SDIO 主机支持：

| 包 | 作用 |
|---|---|
| `kmod-mwifiex-sdio` | Marvell mwifiex 驱动（SDIO/88W8897） |
| `mwifiex-sdio-firmware` | 8887/8997 的固件（OpenWrt 这个包里**没有** 8897 的） |
| （构建时补的）`mrvl/sd8897_uapsta.bin` | 8897 真正要的固件：OpenWrt 的 `mwifiex-sdio-firmware` 只装 `sd8887_uapsta.bin` + `sdsd8997_combo_v4.bin`（见上游 `linux-firmware/marvell.mk`），所以构建时从 linux-firmware 取这一份补进 `/lib/firmware/mrvl/`（钉提交 + 校验 sha256） |
| `kmod-mmc` | MMC/SDIO 核心（mwifiex-sdio 依赖） |
| `kmod-sdhci` | Atom（Cherry Trail）的 SD/SDIO 主机控制器 |
| `iwinfo` / `iw` | 无线诊断（信号、加密、接口能力） |

依据：[OpenWrt 论坛专帖（Wyse 3040 + 88W8897）](https://forum.openwrt.org/t/dell-wyse-3040-with-marvell-88w8897-wifi-card/177119)、
DietPi 论坛里同为 Wyse 3040 + AW-CM389MA 的实例。认证所需的 `wpad`/`hostapd` 基础本就在默认包里。

**装好后怎么确认**：

> 注意：`kmod-mwifiex-sdio` 这个包**不会**往 `/etc/modules.d/` 写自动加载条目
> （镜像里能看到 `mmc`、`sdhci`、`mt7921e`，唯独没有它），所以本仓库额外放了
> `files/etc/modules.d/mwifiex-sdio` 让驱动**开机自动加载**；临时手动加载：
> `modprobe mwifiex_sdio && sleep 3 && iw dev`

```sh
ls /sys/bus/devices/ 2>/dev/null >/dev/null; ls /sys/bus/sdio/devices/   # 有设备说明 SDIO 卡被识别
ls /lib/firmware/mrvl/                    # 应有 sd8897_uapsta.bin(8897 专用)
dmesg | grep -i -E "mwifiex|sdio"         # 驱动加载与固件下载日志(应能看到 firmware download 成功)
iw dev                                    # 应出现 mlan0(不是 wlan0)
iwinfo                                    # 接口与加密方式
```
LuCI 里是 **网络 → 无线**（`luci-mod-network` 已随 luci 装好）。

> 若你的机器插的不是这块卡（比如自己加的 PCIe M.2 网卡），把 `lspci -nn | grep -i net`
> 和 `lsusb` 的输出发我，改一行包名即可。
