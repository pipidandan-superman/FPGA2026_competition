# PYNQ 零基础开发与 EES-331 摄像头工程实战

本文面向第一次接触 Zynq、Linux 和 PYNQ 的开发者，目标是在 EES-331（XC7Z020-CLG484-1）上理解并复现当前工程：

- OV5640 采集视频；
- HDMI 输出实时画面；
- 通过千兆网口把视频发送到 PC 上位机；
- SD 卡上电后自动加载 PL 并启动业务。

当前板测工程固定使用：

- 工程根：`E:/competition/2_fpga/0_diaplay_test`
- PYNQ 控制层：`E:/competition/2_fpga/0_diaplay_test/pynq`
- Builder 源码：`E:/competition/3_host/pynq/sd_boot_builder_v02`
- Builder EXE：`E:/competition/8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.2.exe`
- 已验证成功整合镜像：`E:/competition/9_pynq/sd/02_integrated_camera_hdmi_udp/ees331_pynq_sd_20260911_222654.img`
- 镜像 SHA256：`8d22bcde0268678050bcc1429bee5ecadb0020e5ce3f5ba4df7045066deafcca`
- PC 上位机：`E:/competition/3_host/udp_video/dist/EES331_UDP_Viewer.exe`
- XSA SHA256：`d69fb256b66106da87514fc3821fe177bbe538c128e74485f43a4a265f092ebc`

## 1. 先理解 Zynq 的 PS 与 PL

Zynq-7020 在一颗芯片中包含两部分：

- **PS（Processing System）**：ARM Cortex-A9、DDR 控制器、SD、UART、以太网等。Linux 和 Python 运行在 PS。
- **PL（Programmable Logic）**：FPGA 可编程逻辑。当前工程中的摄像头采集、像素流处理、VDMA 数据通路和 HDMI 时序位于 PL。

当前设计的职责可以画成：

```text
OV5640
  │ 像素/同步信号
  ▼
PL 摄像头采集与视频流 ──► AXI VDMA ──► DDR（三帧缓冲）
          │                              │
          └──────── HDMI 视频链 ─────────┘
                                         │
                                         ▼
                                PS/Linux/Python
                                         │ UDP
                                         ▼
                                  PC 上位机显示
```

OV5640 的 SCCB 初始化和 ADV7511 的配置已由当前 PL 设计完成。Python 的主要任务是加载匹配的 Overlay、配置 VDMA、分配连续内存、读取帧并发送 UDP；不要重复搬入一套互相冲突的摄像头或 HDMI 初始化。

## 2. 常见文件分别是什么

| 文件 | 作用 | 是否直接执行 |
|---|---|---|
| `.bit` | PL 位流，决定 FPGA 内部逻辑 | 由 FSBL、Linux FPGA Manager 或 PYNQ Overlay 加载 |
| `.hwh` | Vivado 硬件描述，PYNQ 用它识别 IP、地址和中断 | 与 bit 同名配对，不能代替 bit |
| `.xsa` | Vivado 导出的硬件平台归档，可含 PS 配置、HWH 和 bit | 给 Vitis、设备树和 Builder 使用 |
| Overlay | PYNQ 对一组 bit/HWH 的运行时抽象 | Python 中用 `Overlay(...)` 加载 |
| 设备树 DTB | 告诉 Linux 有哪些 PS/PL 设备、地址、时钟和驱动关系 | 由 bootloader 传给内核 |
| `BOOT.BIN` | Zynq 启动容器，通常含 FSBL、U-Boot，FSBL 模式还可含 bit | BootROM 从 SD FAT 分区读取 |
| `image.ub` | FIT 镜像，通常含 Linux 内核、设备树等 | U-Boot 加载 |
| `boot.scr` | U-Boot 启动脚本 | U-Boot 执行 |
| `uEnv.txt` | 追加启动参数；本工程用于 CMA | U-Boot/启动脚本读取 |
| IMG | 整张 SD 卡的扇区镜像，含分区表、FAT 启动分区和 ext4 根分区 | 用 Win32DiskImager 写入 SD 卡 |
| rootfs | Linux 根文件系统，包含 `/home`、`/etc`、Python、systemd 等 | Linux 挂载后使用 |

XSA 更新硬件描述，不会自动把原裸机 `main.c` 变成 Linux/Python 应用。PYNQ 运行时通常依赖 bit/HWH 和 Linux 侧控制代码；PS 启动参数变化还可能要求同步 FSBL、设备树或内核驱动。

## 3. JTAG 裸机与 SD/Linux/PYNQ 的区别

### JTAG + Vitis 裸机

- Vitis 通过 JTAG 下载 bit、初始化 PS、下载 ELF；
- `main.c` 直接操作寄存器和固定物理地址；
- 断电后 JTAG 下载内容消失；
- 适合验证硬件平台和裸机控制顺序。

### SD + Linux + PYNQ

- BootROM 从 SD 加载 FSBL/U-Boot/Linux；
- Python 运行在 Linux 用户空间；
- PYNQ 的 Overlay 负责运行时加载 bit，并根据 HWH 暴露 IP；
- 缓冲区由 Linux/XRT/CMA 管理，不能照搬裸机固定 DDR 地址；
- systemd 可在开机后自动启动业务。

因此，JTAG 下成功说明硬件和裸机控制链可工作；它不能自动证明 SD/Linux 下的内存、驱动、Overlay、网络和开机服务均正确。当前项目已经分别完成 PYNQ 双路画面和 Linux 软件重启自动恢复测试。

## 4. 当前未重刷 SD 卡时，上电怎么做

当前已经部署业务的 SD 卡无需再次使用 Vitis 或 JTAG。

1. 关闭板卡电源。
2. SW8 保持 SD 启动位置。
3. 插好 OV5640、HDMI、网线和串口线。
4. PC 有线网卡设置静态 IPv4：
   - 地址：`192.168.240.2`
   - 掩码：`255.255.255.0`
   - 网关留空。
5. 打开 `E:/competition/3_host/udp_video/dist/EES331_UDP_Viewer.exe`，确认只运行一个接收器。
6. 给板卡上电，等待约 60～90 秒。
7. 验收：
   - HDMI 出现摄像头画面；
   - PC 上位机出现摄像头画面；
   - 镜头前移动物体，两边画面都持续变化。

`ees331-camera.service` 会自动加载 Overlay、配置三帧 VDMA、驱动 HDMI，并向 `192.168.240.2:5000` 发送约 5 fps 的 UDP 视频。

已验证的是 Linux 软件重启后的自动恢复。物理断电再上电应按上述流程单独执行一次并保存证据。

## 5. 重刷基础 IMG 后，如何手工恢复业务

基础 IMG 只有适配 EES-331 的 Linux/PYNQ 环境，不含后来部署的摄像头业务。重刷后需要重新安装。

### 5.1 准备文件

从 `E:/competition/2_fpga/0_diaplay_test/pynq` 取：

- `camera.py`
- `run_camera.sh`
- `install.sh`
- `inspect_board.py`
- `ees331-camera.service`
- `ees331_camera.network`
- 与当前 XSA 严格匹配的 `overlay.bit`、`overlay.hwh`
- `uEnv.txt`

### 5.2 先恢复 CMA

VDMA 三帧缓冲需要足够的连续物理内存。本工程使用：

```text
cma=128M@0x10000000
```

把配套 `uEnv.txt` 放到 SD 卡 FAT 启动分区，然后重启。登录后检查：

```bash
cat /proc/cmdline
grep -i cma /proc/meminfo
dmesg | grep -i cma
```

### 5.3 上传并安装

先让板卡和 PC 位于同一网段，再从 PowerShell 上传：

```powershell
scp -r E:/competition/2_fpga/0_diaplay_test/pynq xilinx@192.168.240.10:/home/xilinx/ees331_camera
```

板端执行：

```bash
cd /home/xilinx/ees331_camera
chmod +x install.sh run_camera.sh
sudo ./install.sh
sudo systemctl daemon-reload
sudo systemctl enable ees331-camera.service
sudo reboot
```

重启后检查：

```bash
systemctl status ees331-camera.service --no-pager
journalctl -u ees331-camera.service -b -n 100 --no-pager
ip addr
```

如果上传目录形成了多一层 `pynq`，应先整理到固定路径 `/home/xilinx/ees331_camera`，否则 service 的 `ExecStart` 找不到脚本。

## 6. 用 Builder v0.2.2 生成已整合 IMG

这种方式把应用直接写入 IMG，首次启动即可自动运行。

### 6.1 安装依赖

1. 安装 Vitis 2025.2，确认目录 `F:/vivado2025/2025.2/Vitis`。
2. 运行 Cygwin 官方安装器，安装包选择 `e2fsprogs`。
3. 确认：

```powershell
Test-Path C:/cygwin64/usr/sbin/debugfs.exe
Test-Path C:/cygwin64/usr/sbin/e2fsck.exe
```

MSYS2 当前镜像没有满足本工具要求的 `e2fsprogs` 包，本机已验证的路径是 Cygwin。

### 6.2 Vivado 导出 XSA

1. 在 Vivado 完成综合、实现和 Generate Bitstream。
2. 选择 Export Hardware。
3. 勾选 Include bitstream。
4. 导出 XSA。
5. 对当前业务 XSA 计算哈希：

```powershell
Get-FileHash -Algorithm SHA256 E:/competition/2_fpga/0_diaplay_test/display_test_wrapper.xsa
```

整合内置摄像头应用时必须匹配固定 XSA 哈希。新 XSA 需要重新迁移和验证，不能绕过哈希门禁。

### 6.3 Builder 操作

1. 打开 `EES331SDBootBuilder_v0.2.2.exe`。
2. 选择含 bitstream 的 XSA。
3. 点击“检查 XSA / 配置差异”。
4. PL 加载方式选择“手动加载”。
5. 勾选“同时输出完整 .img”。
6. 勾选“整合 EES-331 摄像头 PYNQ 应用”。
7. 高级设置确认：
   - Vitis：`F:/vivado2025/2025.2/Vitis`
   - debugfs：`C:/cygwin64/usr/sbin/debugfs.exe`
   - 基础 IMG 为登记的 EES-331 基线；
   - DTB 覆盖留空，除非已有完整、审核过的 DTB。
8. 点击“生成启动包”。
9. 只有日志出现 `SD_PACKAGE_STATIC_PASS`、`PYNQ_ROOTFS_INJECTION_PASS`、完整读回 PASS 才算离线构建通过。

“手动加载”描述的是 PL 的启动阶段策略。整合镜像中，systemd 会在 Linux 启动后自动调用 PYNQ Overlay，所以日常上电仍无需人工运行 Python。

## 7. 用 Win32DiskImager 写入 SD 卡

安装器：

`E:/competition/8_tools/win32diskimager-1.0.0-install.exe`

当前复现请直接选择已归档并完成板测的完整镜像：

`E:/competition/9_pynq/sd/02_integrated_camera_hdmi_udp/ees331_pynq_sd_20260911_222654.img`

不要用 `03_boot_partition` 中的分区镜像代替完整 IMG。原始基础镜像位于 `9_pynq/sd/01_base_pynq`，仅用于回退和手工重新部署。

详细步骤：

1. 备份 SD 卡需要保留的文件。
2. 安装并以管理员身份启动 Win32DiskImager。
3. 插入 SD 卡，打开 Windows 磁盘管理，记录 SD 卡容量和盘符。
4. 在 Image File 选择上述已验证的完整 `ees331_pynq_sd_20260911_222654.img`。
5. 在 Device 选择 SD 卡对应盘符。再次按容量核对，禁止选择系统盘或数据盘。
6. 点击 **Write**，确认覆盖。
7. 等待写入完成。不要在过程中拔卡、休眠或关机。
8. 完成后使用 Windows“安全删除硬件”弹出 SD 卡。
9. 将 SD 卡插回 EES-331，SW8 设为 SD 启动，再执行冷启动验收。

Win32DiskImager 负责逐扇区写入 IMG，不负责 XSA 分析、BOOT.BIN 生成或 ext4 应用注入。这些已由 Builder 完成。

## 8. SSH、Jupyter 与 Python 开发

### SSH

```powershell
ssh xilinx@192.168.240.10
```

常用命令：

```bash
hostname
uname -a
ip addr
df -h
free -h
systemctl status ees331-camera --no-pager
```

### Jupyter

若镜像启用了 Jupyter，可在浏览器访问板卡地址对应的 9090 端口。Jupyter 适合逐步检查 Overlay、寄存器和缓冲区；长期业务应使用脚本和 systemd，避免 Notebook 单元格执行顺序造成状态不一致。

手动调试前先停服务：

```bash
sudo systemctl stop ees331-camera
```

调试完成再恢复：

```bash
sudo systemctl start ees331-camera
```

## 9. Overlay、MMIO 和寄存器

### Overlay

```python
from pynq import Overlay

ol = Overlay("/home/xilinx/ees331_camera/overlay.bit", download=True)
print(ol.ip_dict)
```

bit 与 HWH 必须同名且来自同一次 Vivado 导出。只替换 bit 而保留旧 HWH，可能导致地址错误或 IP 缺失。

### MMIO

```python
from pynq import MMIO

vdma = MMIO(0x43000000, 0x10000)
status = vdma.read(0x04)
vdma.write(0x00, 0x00000004)
```

地址和偏移必须来自当前设计、HWH 和 IP 文档。不要把示例地址直接用于其他 XSA。寄存器操作顺序应保持与已验证的 `camera.py` 一致。

## 10. pynq.allocate、CMA 与物理地址

`pynq.allocate` 从连续内存分配器取得 DMA 可访问缓冲区：

```python
from pynq import allocate
import numpy as np

frame = allocate(shape=(480, 640, 4), dtype=np.uint8)
print(hex(frame.physical_address))
```

关键点：

- Python 的虚拟地址不能直接写入 DMA；
- VDMA 寄存器需要 `physical_address`；
- CMA 必须够大，并落在 PL 的 AXI 地址可达窗口；
- 三帧缓冲要计算总大小并留出余量；
- 不要沿用裸机写死的 `0x10000000` 缓冲地址。

## 11. Cache flush 与 invalidate

CPU 和 DMA 共享 DDR 时要处理缓存一致性：

- CPU 写好数据给 DMA 读之前，执行 `flush()`；
- DMA 写好数据给 CPU 读之前，执行 `invalidate()`。

```python
tx_buffer.flush()
rx_buffer.invalidate()
```

遗漏缓存维护可能出现旧画面、局部撕裂或数据时好时坏。当前 `camera.py` 已按采集方向处理，不应随意删除。

## 12. VDMA 三帧环形缓冲

本工程使用三个帧地址。典型顺序为：

1. 分配三块连续缓冲；
2. 配置 MM2S 输出通道，使 HDMI 先有有效首帧；
3. 清理一次启动期旧状态；
4. 配置 S2MM 摄像头写通道；
5. 观察实际读写帧索引发生切换；
6. 运行期一旦出现 VDMA 错误就停止，不循环清错掩盖故障。

三帧环形缓冲降低采集和显示速率瞬时差异造成的覆盖风险。帧大小、stride、水平尺寸、垂直尺寸和像素格式必须一致。

## 13. UDP 视频与 PC 上位机

板卡固定地址 `192.168.240.10/24`，PC 固定地址 `192.168.240.2/24`，目标端口 5000。

单帧大于普通 UDP 负载，因此 OV56 协议把一帧分成多个数据包，并携带帧号、分片号和校验信息。PC 上位机负责：

- 按帧号重组；
- 检查包头和 CRC；
- 统计缺片、丢帧和坏包；
- 完整后渲染画面。

调试顺序：

```powershell
ping 192.168.240.10
```

然后确认 Windows 防火墙允许上位机接收 UDP 5000。不要同时打开多个接收器，否则端口绑定和统计会混乱。

## 14. systemd 开机服务

常用命令：

```bash
sudo systemctl daemon-reload
sudo systemctl enable ees331-camera
sudo systemctl start ees331-camera
sudo systemctl stop ees331-camera
sudo systemctl restart ees331-camera
systemctl status ees331-camera --no-pager
journalctl -u ees331-camera -b -n 100 --no-pager
```

服务失败时先读本次启动日志，不要立即反复重启。常见原因包括 Overlay/HWH 不匹配、CMA 不足、网络目标不通、VDMA 状态错误或脚本权限/路径错误。

## 15. 安全停止 DMA

不要用 `kill -9` 终止正在运行的采集脚本。正确顺序是：

1. 通知主循环退出；
2. 停止 S2MM/MM2S；
3. 轮询状态，确认通道 halted；
4. 再释放 `pynq.allocate` 缓冲区；
5. 最后退出进程。

强杀可能让 DMA 继续访问已经归还给 Linux 的物理页，导致下一次启动异常或系统不稳定。

## 16. 新 XSA 的迁移门禁

任何新 XSA 都按以下顺序处理：

1. 记录 XSA、bit、HWH SHA256。
2. 比较器件、DDR、UART、SD0、GEM0、MIO、FCLK、GP/HP AXI 和地址空间。
3. 若 PS 配置改变，重新生成匹配的 FSBL/BSP，并同步设备树。
4. 核对 HWH 中的 IP 名称、基地址、VDMA 参数和 PL DDR 可达范围。
5. 在隔离环境运行 Builder 静态构建与读回检查。
6. 先做 JTAG/裸机硬件基线验证，再做 SD/Linux Overlay、CMA、HDMI 和 UDP 验证。
7. 修改 PYNQ 地址或顺序时，一次只改变一个变量并保留失败日志。
8. 通过物理冷启动后再更新 systemd 自动运行版本。

XSA 可以在线用于重新加载 PL，但 PS 的 MIO、DDR 初始化等不能靠运行时换一个 bit 完整切换。涉及 PS 启动配置的变化必须重建并重启对应启动链。

## 17. 故障排查表

| 现象 | 优先检查 |
|---|---|
| cfg_done LED 不亮 | service 日志、Overlay 是否下载、bit/HWH 是否配对 |
| HDMI 无信号 | PL 时钟/复位、ADV7511 初始化、MM2S 状态、首帧 |
| HDMI 有画面但 PC 没画面 | IP 网段、UDP 5000、防火墙、S2MM 状态 |
| PC 有静止旧帧 | cache invalidate、帧索引切换、S2MM 是否继续写 |
| allocate 失败 | CMA 参数、连续内存剩余量、已有进程是否占用 |
| VDMA 报错 | 地址对齐、stride/hsize/vsize、物理地址窗口、启动顺序 |
| service 启动太早失败 | 网络依赖、CMA/Overlay 就绪、服务 After/Wants 配置 |
| Builder FSBL BSP 失败 | Vitis 路径、XSCT 日志、Tcl/DLL 环境污染、XSA 是否完整 |
| 写卡后 Windows 只看到小分区 | 正常；Windows 通常只识别 FAT 启动分区，ext4 由 Linux 使用 |

## 18. 验收标准与证据边界

### 离线构建 PASS

- XSA/bit/HWH 哈希符合预期；
- FSBL、BOOT.BIN、FIT、DTB 构建和结构检查通过；
- IMG 分区和文件读回通过；
- ext4 写入前后 e2fsck 通过；
- 应用逐文件 SHA256、systemd 链接和 CMA 参数通过；
- 整个 IMG 分块读回与 SHA256 通过。

这只能记为 `SD_PACKAGE_STATIC_PASS` 和 `PYNQ_ROOTFS_INJECTION_PASS`。

### 板级冷启动 PASS

1. 用 Win32DiskImager 写入新 IMG；
2. 板卡完全断电；
3. SW8 为 SD 启动；
4. 重新上电并保存完整 UART；
5. 无人工命令，60～90 秒内 service active；
6. HDMI 和 PC 均出现随动作变化的摄像头画面；
7. UDP 统计无坏头、CRC 错误，丢帧在声明范围内；
8. VDMA 运行期无错误；
9. 正常停止时 DMA halted 后释放缓冲。

当前已部署 SD 卡的软件重启自动恢复通过；Builder v0.2.1 生成的新整合 IMG 已通过离线验证，但尚未执行这套物理断电冷启动验收。

## 19. 推荐的日常开发循环

1. 保留一个已知可启动、已知可显示的 SD 卡作为恢复介质。
2. Vivado 改动后导出含位流 XSA并记录哈希。
3. 先检查 XSA 差异，不直接覆盖已验证文件。
4. 用 JTAG 验证新的硬件数据通路。
5. 在 Linux 中停掉自动服务，手动加载新 Overlay 做有界测试。
6. 更新 Python 地址和控制顺序，运行协议与语法测试。
7. 恢复 systemd，做软件重启测试。
8. 用 Builder 生成新 IMG，做静态读回。
9. 写入备用 SD 卡，做物理冷启动、HDMI 和 UDP 联合验收。
10. 保存 UART、service、VDMA、PC 统计、哈希和现场结果，再更新版本说明。

这样可以把硬件平台问题、Linux 启动问题、PYNQ 控制问题和 PC 网络问题分开定位。
