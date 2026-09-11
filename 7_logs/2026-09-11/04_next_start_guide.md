# 2026-09-11 下次入口

先读 3_host/pynq/sd_boot_builder_v02/README.md 和本日验证摘要。
如用户后续要求新XSA部署，先区分纯PL变化与PS启动配置变化，再核对SD0/UART/DDR及设备树兼容；新包单独冷启动验收。
不立即修改冻结2_fpga、不覆盖成功SD基线、不把源码核查当板测。当前问答无阻塞，具体新设计尚未做兼容性验收。

## 当前入口：已授权 PYNQ 迁移
从 `2_fpga/0_diaplay_test/pynq` 和 `4_metrics/logs/2026-09-11_pynq_camera_run01` 继续。板已由 SD 启动，COM6 串口，SSH 192.168.240.10（临时地址，原 192.168.2.99 保留），PC 192.168.240.2。
迁移已完成并经 SD 软件重启验证自动启动；使用说明以 `2_fpga/0_diaplay_test/pynq/README.md` 为准，原始证据和两次启动失败的修复记录见运行目录 REPORT.md。
板卡永久增加 192.168.240.10，保留 192.168.2.99；`ees331-camera` 服务 enabled/active。先执行 `systemctl status ees331-camera` 和 `journalctl -u ees331-camera -b -n 20`。PC 上位机监听 UDP 5000，默认视频 5 fps；只运行一个接收器。
手动调试前 `sudo systemctl stop ees331-camera`，再 `sudo bash /home/xilinx/ees331_camera/run_camera.sh --seconds 60`。调试结束 `sudo systemctl start ees331-camera`。服务会停止 DMA 并确认 halted 后释放内存，勿 kill -9。
勿在 Linux 中运行裸机 ELF 或直接使用 0x10000000 帧缓冲；勿修改既有 RTL/BD/Vitis。新 XSA 需重新核对 DDR 地址窗口和部署哈希，不可绕过校验。本轮是软件重启测试，尚未做物理断电测试。重新刷原 IMG 后需重新安装本目录的业务文件、uEnv 和服务。

## 强制继续顺序

1. 先完成并确认 `codex/full/pipidandan-superman` 的 PYNQ 阶段成果推送。
2. 推送确认后，修改 `3_host/pynq/sd_boot_builder_v02`，为 full-image 增加 PYNQ rootfs 应用注入。
3. Builder 修改和离线验证完成后，在 `1_docs` 编写 PYNQ 零基础开发教程。
4. 新生成的整合 IMG 必须另行写卡并做物理断电冷启动、HDMI 和 UDP/PC 实测，才可记为整卡 PASS。

禁止直接在污染的 `E:\competition` 工作区切分支或批量暂存；禁止 `git add .`、`git add -A`、reset、clean 和 force push。
