# EES-331 SD/PYNQ 摄像头显示与 UDP

本目录将已有 `display_test` 的 PS 控制逻辑迁移到 PYNQ 3.0.1/Linux。
OV5640 SCCB 初始化、摄像头采集、ADV7511 初始化及 HDMI 输出仍使用已通过 JTAG 板测的 PL。
Python 控制 VDMA、分配帧缓存，并使用 Linux UDP socket 发送兼容原 PC 上位机的数据。

## 已部署的使用方式

保持 SW8 为 **SD 启动**，连接摄像头、HDMI 显示器和网线后上电。已安装的 `ees331-camera.service` 会在网络启动后加载位流并运行业务，无需启动 Vitis、JTAG 下载或 Jupyter。

- 开发板：`192.168.240.10/24`（原 `192.168.2.99/24` 保留）。
- PC 有线网卡：`192.168.240.2/24`。
- UDP 目标端口：5000；画面 640×480，每像素三字节 BGR，默认网络发送 5 fps。
- HDMI 通过 PL/VDMA 持续播放摄像头流，网络发送 5 fps 不会将 HDMI 限制到 5 fps。
- PC 使用原有 `E:\competition\3_host\udp_video\dist\EES331_UDP_Viewer.exe`；同一时间仅运行一个监听 UDP 5000 的上位机。
- 本轮已打开的 PC 窗口标题为 `EES-331 PYNQ/Linux - live camera UDP`，它复用原上位机代码并附加证据记录。

板上常用命令（串口或 SSH）：

```bash
systemctl status ees331-camera --no-pager
journalctl -u ees331-camera -b -n 20 --no-pager
sudo systemctl stop ees331-camera
sudo systemctl start ees331-camera
```

手动测试必须先停止开机服务，避免两个程序控制同一 VDMA：

```bash
sudo systemctl stop ees331-camera
cd /home/xilinx/ees331_camera
sudo bash run_camera.sh --seconds 60 --fps 5 --peer 192.168.240.2
sudo systemctl start ees331-camera
```

`--no-udp` 仅测试采集和 HDMI，`--seconds 0` 持续运行；Ctrl-C/SIGTERM 会先停止 VDMA 并确认 halted，再释放帧缓存。不要用 `kill -9` 终止运行中的 DMA 程序。异常时程序停止在首个失败阶段，不自动反复重试。

## 从本目录重新部署

Windows PowerShell 生成与当前 XSA 配对的位流/HWH：

```powershell
python E:\competition\2_fpga\0_diaplay_test\pynq\prepare_overlay.py
```

该脚本固定验证已经验收的 XSA SHA256：
`d69fb256b66106da87514fc3821fe177bbe538c128e74485f43a4a265f092ebc`。
新 XSA 必须重新核对地址窗口、IP 参数和板测，不可只删除哈希检查。

将下列文件复制到板卡 `/home/xilinx/ees331_camera/`：

```text
camera.py
run_camera.sh
install.sh
overlay.bit
overlay.hwh
uEnv.txt
ees331_camera.network
ees331-camera.service
inspect_board.py（诊断工具，可选）
```

在板上执行：

```bash
sudo systemctl stop ees331-camera  # 首次安装没有该服务时可忽略提示
cd /home/xilinx/ees331_camera
sudo bash install.sh
sudo reboot
```

全新基础 SD 镜像默认地址为 `192.168.2.99`，可能无法从 PC 的 192.168.240 子网直接连接。可在串口先执行临时配置，再 SSH 复制文件：

```bash
sudo ip addr add 192.168.240.10/24 dev eth0
```

安装器将服务配置到 Linux 根文件系统，给网络增加固定地址，并在 SD 启动分区写入 `uEnv.txt`。替换前的配置保存在 `/home/xilinx/ees331_camera/backup/`。
本轮未重新生成原 SD IMG/ZIP；若重新刷整卡镜像，须重新部署本目录。

## 关键适配

1. **连续内存地址**：HWH 显示当前 VDMA 可访问 `0x00000000..0x1fffffff`，其中原裸机帧缓冲使用 HP1 的 `0x10000000..0x1fffffff` 窗口。原 Linux CMA 分配到了 `0x38100000`，不能直接用于当前位流。`uEnv.txt` 增加 `cma=128M@0x10000000`，由内核保留区域，应用仍用 `pynq.allocate`，不直接占用裸机固定 DDR 地址。
2. **PYNQ 环境**：`run_camera.sh` 设置 `XILINX_XRT=/usr`，使用 `/usr/local/share/pynq-venv/bin/python3`，避免 sudo/SSH 丢失环境后出现 `No Devices Found`。
3. **大小写配对**：SD FAT 中文件显示为 `OVERLAY.BIT/HWH`；应用目录统一使用 `overlay.bit/hwh`，避免 HWH 查找失败。SD 包的 manual 模式保持不变，由业务服务负责每次加载。
4. **VDMA**：保留现有 main.c 的寄存器顺序、三帧环形缓存和动态 Genlock 配置；当前 IP 未连 IRQ，使用 MMIO 轮询，不依赖中断驱动。先给 PL 初始化留出 1 秒，再启动 DMA；MM2S 运行后记录并清除一次启动瞬态标志，然后严格要求新的读写帧切换。运行期不重复清错。`0x11000` 中的帧完成标志不是错误，错误掩码为 `0x8FF0`，在裸机检查基础上补查 EOLLateErr。
5. **帧一致性**：复制已完成帧到独立 bytes；无缓存一致性硬件支持时先 invalidate。复制期间写指针变化或耗时达到 10 ms 则丢弃快照并重试，以免发送撕裂帧。拒绝次数是板内快照重试，不等于 UDP 丢帧。
6. **协议**：沿用 OV56、32 字节网络序帧头、每帧 640 包、每包 1440 字节像素和整帧 CRC32；原 PC 上位机可直接接收。

## 验证与证据

- 2026-09-11：SD/PYNQ 联合运行 120 秒，发送 600 帧/384000 包，约 5 fps，VDMA 错误为 0。
- 用户现场确认 HDMI 和 PC 均有正常画面且随镜头前动作变化。
- 最终版本 SD 软件重启后服务自动恢复；124.125 秒记录到 604 完整 PC 渲染帧，CRC/丢帧/坏头均 0，持续 VDMA 状态无错。开机约 1 分钟进入视频；尚未做物理断电测试。
- `test_protocol.py` 使用原 PC 解码器验证字节级兼容、BGR 次序、损坏帧拒绝和缺包帧拒绝。
- [本轮原始证据](../../../4_metrics/logs/2026-09-11_pynq_camera_run01/)；[项目验证摘要](../../../7_logs/2026-09-11/03_validation_summary.md)。
- 板端每次服务运行在 `/home/xilinx/ees331_camera/evidence/<boot-id>_<单调时间>/` 保存首/末 BGR 帧和退出结果；运行日志由 journal 保存。板卡 RTC 仍显示历史日期，报告以 PC 日期和单调时间为准。

`CAPTURE_VDMA_RUN_COMPLETE` 只代表板端有界运行完成；完整验收还需要 PC 接收统计和 HDMI 实物显示。不能把 `ip_dict` 内容或 `PL_LOADED` 单独当作视频功能 PASS。

## 恢复

```bash
sudo systemctl disable --now ees331-camera
```

以上停止业务且保留 Linux 和网络。若要恢复原 CMA 布局，将 `/boot/uEnv.txt` 改名为不被启动脚本加载的备份后重启；若此前有自己的 uEnv，恢复对应备份。网络配置恢复 `/home/xilinx/ees331_camera/backup/` 的原文件。
原 RTL/BD/Vitis 工程和 BOOT.BIN/image.ub/boot.scr 均未因 PYNQ 迁移改写。恢复 JTAG 基线时应先正常关闭 Linux，再按原流程切换启动模式。
