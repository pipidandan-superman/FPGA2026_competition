# EES-331 PL 在线重加载 v1.4 上板复现指南

本指南对应 2026-09-13 已完成两轮 A→C 上板成功的 `EES331_PL_Reloader_v1.4`。第二轮发生在用户确认开发板断电、重新上电之后。它说明怎样复现“原摄像头视频 → 动作版 PL → PC 模型 → AXI-Lite → LED/UART → 恢复原视频”的完整链路。

> 验收边界：当前证据是 **2/2 次成功切换**，其中第二次为用户确认断电重启后的成功；v1.4 尚未记录 Linux boot ID，因此不能把它写成自动证明的冷启动，也不能外推为长期 10/10 稳定性。

## 1. 固定交付物

- 重加载程序：`8_tools/EES331_PL_Reloader_v1.4/`，必须保留 EXE 与 `_internal` 整个目录。
- 动作识别入口：`8_tools/EES331_Action_Viewer_v1.0/Start_Action_Verification.ps1`。该入口复用仓库中的 `EES331_Gesture_Viewer_v1.0` 运行目录，并显式加入 `--action-control`。
- 动作载荷：`9_pynq/overlays/action_v1_20260913/`。
- 重加载器 EXE SHA-256：`aa46d21540109ce9387822802b18d96d493643663f735d8eea0bd641cd063d90`。
- 动作 BIT SHA-256：`bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d`。
- 动作 HWH SHA-256：`64ff7724c56c97b52fac699168f762e30ea42b4d25910a30caf00f58c8b55ed0`。
- 模型 `best.pt` SHA-256：`68db7cacbdd6d9c9a583e1c50a9f5934a3a6b78675b215ec86717827be8bfc79`。

从 GitHub 克隆时必须安装 Git LFS，并在仓库根目录执行 `git lfs pull`。如果 EXE、BIT、HWH、PT 或 ZIP 只有很小的文本内容，说明拿到的是 LFS 指针，不可上板。

## 2. 接线与网络前提

1. 使用已经验证可启动 PYNQ 3.0.1、可输出 OV5640 HDMI/UDP 动态视频的 SD 卡；不要替换 BOOT.BIN、镜像或原 `ees331-camera` 服务。
2. EES-331 设为 SD 启动，连接 OV5640、HDMI、网线后上电。
3. PC 有线网卡固定为 `192.168.240.2/24`，开发板为 `192.168.240.10`。
4. 允许 PC 到板端 TCP 22；板端视频发往 PC UDP 5000，动作命令使用 UDP 5001。
5. 关闭普通 UDP Viewer、旧动作上位机和任何占用 UDP 5000 的进程。自动串口核验时也要关闭其他占用 COM4 的程序。
6. COM4 如用于旁路观察，参数为 9600/8N1，只接收；动作不是 PC 直接写串口，而是 PC→UDP5001→PS→AXI-Lite→PL UART/LED。

## 3. 从上电到动作版

1. 上电后等待 60～90 秒，先确认 HDMI 和/或普通 UDP 画面持续动态、颜色与流畅度正常。静态图、花屏或卡顿都不能勾选基线确认。
2. 打开 `8_tools/EES331_PL_Reloader_v1.4/EES331_PL_Reloader.exe`。默认地址 `192.168.240.10`、用户 `xilinx`，密码框自动填充 `xilinx`；若板卡密码已修改，覆盖输入即可。
3. 点击“检查状态”。预期看到 `ees331-camera` 的真实 PID、`ActiveState=active`、`SubState=running`。查询命令自身不算摄像头进程。
4. 勾选“我已确认当前原 HDMI/UDP 画面动态、流畅”。
5. 只点击一次“一键加载动作版 PL”，等待完整流程结束；运行期间不要再次点击、不要断电、不要同时启动其他视频接收器。
6. 依次检查日志关键标记：

   ```text
   PAYLOAD_VERIFIED
   ORIGINAL_STOP_SAFE
   PL_LOADED
   SENSOR_SETTLE_BEGIN / SENSOR_SETTLE_PROGRESS / SENSOR_SETTLE_COMPLETE
   VDMA_RESET_OK
   BUFFER_ALLOCATED
   FIRST_FRAME_WAIT
   VDMA_STREAM_STARTED
   VIDEO_READY_BEFORE_ACTION
   ACTION_SERVICE_READY
   ACTION_OVERLAY_READY
   ```

   v1.4 在 PL 下载后固定等待 10 秒，再给首帧最多 30 秒，并每秒报告 VDMA 状态。10 秒只是给 OV5640 有状态前端恢复的容错时间，不是 SCCB、PCLK 或 VSYNC 已健康的独立证明。
7. 只有出现 `ACTION_OVERLAY_READY` 且窗口显示“动作版 PL 加载完成”才算软件门通过。`FOUND`、SSH 成功、文件同步完成或 systemd `active` 都不等价于成功。

## 4. 启动模型并让 LED 输出

加载成功时勾选“加载成功后打开动作识别”，或之后点击 v1.4 窗口中的“打开动作识别”。

**不要直接双击动作识别 EXE 来期待 LED 输出。** 直接启动默认是显示/识别模式，日志中会看到 `protocol=null`，不会发送动作。v1.4 内部按钮通过 `Start_Action_Verification.ps1` 显式加入 `--action-control`。

动作窗口启动后先检查：

```text
ACTION_INITIAL_CLEAR
ACTION_LINK_READY
```

然后再做手势。有效动作要求同一类在 3 个不同新推理帧中连续出现且每帧置信度不低于 0.75；同一动作持续保持时不会周期重复下发，无有效动作 1 秒后发送 CLEAR。

| 模型动作 | 动作码 | LED | 自动下发 |
|---|---:|---:|---|
| Down | 1 | LED1 | 是 |
| Left | 2 | LED2 | 否，仅保留人工协议测试 |
| Right | 3 | LED3 | 否，仅保留人工协议测试 |
| Stop | 4 | LED4 | 是 |
| Thumbs Down | 5 | LED5 | 是 |
| Thumbs Up | 6 | LED6 | 是 |
| Up | 7 | LED7 | 是 |

看到 `ACTION_CONFIRMED` 表示 PS 报告 PL 已完成对应序号；LED 仍需人工观察，COM4 物理字节也必须由串口采集证据确认，不能由该事件替代。

## 5. 恢复原视频

1. 正常关闭动作识别窗口，使其发送一次 CLEAR。
2. 在 v1.4 中点击“恢复原视频”。
3. 等待恢复流程报告原 `ees331-camera` 为运行状态。
4. 人工确认 HDMI 和/或 UDP 再次出现持续动态、颜色正确、流畅的真实摄像头画面。

`systemctl active` 只能说明服务进程存在，不是物理视频恢复 PASS。只有人工确认动态视频后，才把本轮恢复记录为成功。

## 6. 故障处理与停止条件

- **卡在端口/SSH**：检查网线、PC 地址 `192.168.240.2/24`、板端电源和 `192.168.240.10:22`；不要通过反复点击绕过。
- **卡在首帧等待**：允许程序完成 10 秒预等待和 30 秒首帧窗口。若出现 `FIRST_FRAME_TIMEOUT`、`FAIL`、`DEGRADED` 或 READY 超时，停止重试，保留本次日志并执行自动/人工恢复。
- **加载成功但 LED 不动**：先确认动作窗口由 v1.4 内部按钮启动，并存在 `ACTION_LINK_READY`；若日志为 `protocol=null`，关闭后从 v1.4 重新打开。
- **画面不动或花屏**：立即停止动作验证，恢复原视频；不能以模型仍有旧框、服务仍 active 或 LED 偶尔变化作为视频健康证据。
- **AXI/网络硬挂死**：软件无法保证恢复。保留证据后断电恢复到原 SD 启动基线，不要连续下载位流。

每次运行的 PC 原始证据位于 `4_metrics/logs/<时间>_pl_reloader_gui_run01/` 和 `<时间>_gesture_viewer_run01/`。失败证据不得删除；它用于区分有效修复和偶然成功。

## 7. 当前已验证证据

- 第一轮 v1.4：`4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run01/REPORT.md`。
- 用户确认断电重启后的第二轮：`4_metrics/logs/2026-09-13_pl_reloader_v14_board_acceptance_run02/REPORT.md`。
- 直接打开模型窗口无 LED 的诊断与正确重开：`4_metrics/logs/2026-09-13_action_viewer_reopen_diagnosis_run01/REPORT.md`。
- v1.4 离线测试与发布包核验：`4_metrics/logs/2026-09-13_pl_reloader_v14_code_run02/`、`4_metrics/logs/2026-09-13_pl_reloader_v14_package_verify_run01/`。

以上证明当前固定硬件、SD、载荷与网络组合可以复现，不证明更换摄像头、SD 镜像、BIT/HWH、模型、网络拓扑后的兼容性，也不代表机械臂安全闭环已经完成。
