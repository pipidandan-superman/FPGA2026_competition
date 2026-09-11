# 2026-09-11 当日计划

目标：解释历史 SD 最小系统、三种 PL 加载方式和板级不兼容。
优先核查工具源码与已归档启动记录，再说明运行时 PL 和 PS 初始化边界。
非目标：修改冻结 2_fpga、生成包、写卡或上板。
交付：中文答复与只读核查记录。

## PYNQ 摄像头迁移（用户授权执行）
用户已用当前 XSA 更新 Vitis/BSP 并确认 JTAG 下 HDMI 与 UDP 视频显示正确；现已恢复 SD 启动。授权在 `2_fpga/0_diaplay_test/pynq` 开发、部署和验证 PYNQ 控制层。
目标：SD/Linux 下复原摄像头到 HDMI 与 UDP/PC 显示。依次验证网络、Overlay、连续内存/VDMA、PC 接收及 HDMI 实物显示。保留 RTL/BD/Vitis 基线。
原始证据：`4_metrics/logs/2026-09-11_pynq_camera_run01/`。

完成状态：HDMI/UDP 双路已验收，用户确认实物画面。开机服务、CMA/网络配置和部署/恢复说明已交付，SD 软件重启自动恢复通过；现保留运行。

## 阶段成果上传与后续门禁

当前优先任务是将 PYNQ 源码、部署脚本、精选验证证据、根 README/HANDOFF 和本日四件套上传至 `codex/full/pipidandan-superman`。原工作区污染，必须使用独立 clean worktree 和逐文件暂存。

远端提交确认前不修改 SD Builder，也不创建 PYNQ 零基础教程。推送通过后的两个交付目标为：

1. 在现有 SD Builder v0.2 中增加完整 IMG 的 PYNQ 应用注入能力。
2. 在 `1_docs` 创建面向零基础的 EES-331 PYNQ 开发流程。

非目标：直接推送 main、上传完整 IMG、上传 Overlay 二进制或整包运行依赖、改写原有 RTL/BD/Vitis 基线。
