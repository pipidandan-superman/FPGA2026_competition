# 可复用 Skill 与工具

## 归档要求

每个 Skill 或工具条目应说明：适用范围、输入/输出、使用步骤、失效条件、已验证设备/软件版本、
失败处理和可复用证据。与本项目绑定的参数、路径和示例命令应明确标注，避免把未验证流程描述为可用。

## 当前状态

2026-09-06 新增仿真 Skill 参考副本（按用户明确要求复制，未改动源 Skill）：

- `modelsim-local-sim/`：ModelSim 后台/命令行仿真流程；
- `modelsim-gui-sim/`：已打开 GUI Transcript 的回退仿真流程；
- `vita-vivado-batch-sim/`：Vivado/XSim 后台批处理参考流程。

注意：`vita-vivado-batch-sim` 保留 ViTA 的路径和器件假设，当前仅作参考副本；
若要在本工程直接执行，必须先按 EES-331/Vivado 2025.2 做路径、器件和项目适配。

日志 Skill 的本地副本位于 `6_skill/daily-engineering-log/SKILL.md`，可在此修改项目专用提示词。
后续新增脚本时，应在 `4_metrics/scripts/` 放置验证脚本，并在 `4_metrics/logs/` 和
`4_metrics/evidence/` 保存完整运行证据。

ViTA 可复用 Skill 的候选、适配边界和审核记录见 [`SKILL_REVIEW_PENDING.md`](SKILL_REVIEW_PENDING.md)。
已批准并落地：`engineering-organization`、`rtl-coding-standards`；`log-management` 已合并进
`daily-engineering-log`，不再建立第二套日志入口。
