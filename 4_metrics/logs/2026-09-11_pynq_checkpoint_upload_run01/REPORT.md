# PYNQ 摄像头阶段成果上传审计

- 日期：2026-09-11
- 目标分支：`codex/full/pipidandan-superman`
- 原工作区：`E:\competition`
- 独立工作树：`E:\competition_worktrees\FPGA2026_competition\pipidandan-superman`

## 上传门禁

本轮先归档并上传已经完成的 SD/PYNQ 摄像头成果。只有远端分支确认包含本次提交后，才允许继续修改 SD Builder 或编写 PYNQ 零基础教程。

## 已验证事实

- `PYNQ_CAMERA_HDMI_UDP_PASS`。
- `SD_REBOOT_AUTOSTART_PASS`。
- 120 秒联合运行发送 600 帧、384000 个 UDP 包，VDMA 运行错误为 0。
- 最终软件重启后，PC 在 124.125 秒内接收并渲染 604 帧，CRC、丢帧和坏头均为 0。
- 用户现场确认 HDMI 与 PC 均显示随动作变化的实时摄像头画面。
- 原 XSA、`main.c`、`BOOT.BIN`、`IMAGE.UB` 和 `BOOT.SCR` 未被本次 PYNQ 迁移修改。

## 边界

- “上电等待即可运行”适用于当前已经安装 `ees331-camera.service` 且未重刷的 SD 卡。
- 已完成 Linux 软件重启自动恢复；物理断电冷启动尚未单独验收。
- 当前完整 IMG 尚未包含业务 rootfs 注入。重刷基础 IMG 后仍需重新安装 PYNQ 应用。
- 本次上传不包含 `overlay.bit`、`overlay.hwh`、`current.hwh` 或完整运行目录；Overlay 可由受哈希约束的 `prepare_overlay.py` 从 XSA 生成。

## 证据

- 功能证据：`4_metrics/logs/2026-09-11_pynq_camera_run01/`
- Git 审计：本目录的 `git_status.txt`、`git_branches.txt`、`ahead_behind_count.txt`、`tracked_worktree_changes.txt`、`staged_changes.txt`、`untracked_paths.txt` 和 `git_graph.txt`

最终提交、远端提交和验证结果将在推送后补充。
