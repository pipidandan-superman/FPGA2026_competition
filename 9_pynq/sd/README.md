# EES-331 PYNQ SD 镜像归档

本目录是本项目唯一面向写卡和恢复操作的 IMG 归档入口。完整镜像体积较大，不提交 GitHub；GitHub 仅保存本说明和 `manifests/images.json`。

## 目录用途

- `01_base_ees331/ees331_pynq_v3.0.1_ps_sd_20260910.img`：已完成 EES-331 PS、SD、UART 和 Linux 启动适配的最小系统基线，用于回退及 Builder 新构建，不包含摄像头开机业务。通用 PYNQ-Z2 镜像不再作为本板基线。
- `02_integrated_camera_hdmi_udp/ees331_pynq_sd_20260911_222654.img`：2026-09-11 实际写卡并验证成功的 EES-331 集成镜像。上电后自动加载 PL，输出 OV5640 HDMI 画面，并向 PC 发送 UDP 视频。
- `03_boot_partition/boot_partition_20260911_222654.img`：与成功集成镜像对应的启动分区恢复/检查镜像。日常整卡部署不要使用它代替完整 IMG。
- `manifests/images.json`：镜像大小、SHA-256、来源和验证状态。

## 写卡和启动

1. 使用 `E:/competition/8_tools/win32diskimager-1.0.0-install.exe` 安装 Win32DiskImager，并以管理员身份运行。
2. 选择 `02_integrated_camera_hdmi_udp/ees331_pynq_sd_20260911_222654.img`，按 SD 卡容量再次确认目标盘符后写入。
3. 安全弹出 SD 卡，插入 EES-331，SW8 设为 SD 启动。
4. 连接 OV5640、HDMI、串口和网线；PC 有线网卡设为 `192.168.240.2/24`。
5. 运行 `E:/competition/3_host/udp_video/dist/EES331_UDP_Viewer.exe`，监听 UDP 5000，然后给板卡上电并等待约 60～90 秒。

板端业务地址为 `192.168.240.10/24`。`ov5640_cfg_done` LED 点亮只表示摄像头配置完成；PC 收到视频还要求网线建立链路、PC 地址正确且 UDP 5000 未被其他程序占用。

## 复现验收

复现时同时保存并检查：镜像 SHA-256、完整 UART 启动日志、`ees331-camera.service` 状态、HDMI 动态画面和 PC UDP 动态画面。镜头前移动物体后两路画面都持续变化，才计为完整功能通过。
