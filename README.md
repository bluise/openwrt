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
- **内置 `openwrt-install`** 交互式安装助手（装到内置硬盘 / 改 LAN IP / 改密码 / 网口模式 / 查看磁盘与网口）

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
openwrt-install
```

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
│  0) 退出                                  │
└───────────────────────────────────────────┘
```

选 `1` 安装，脚本会：
1. 自动识别内置 SATA/NVMe 硬盘（**排除启动 U 盘**）
2. 自动查找 U 盘上的固件镜像
3. 显示目标盘并**倒计时 5 秒**（此时 Ctrl+C 可取消）—— **会清空目标盘所有数据**
4. 写入镜像
5. 只读检测空间并说明结果

### 命令行用法（非交互）

```sh
openwrt-install --no-menu          # 跳过菜单, 直接一键安装
openwrt-install --change-ip        # 只改 LAN 口 IP
openwrt-install -h                 # 查看全部用法
openwrt-install --no-menu /path/to/openwrt-*.img.gz   # 指定固件
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
