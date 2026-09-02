# 可复用 Skill 与工具

## 归档要求

每个 Skill 或工具条目应说明：适用范围、输入/输出、使用步骤、失效条件、已验证设备/软件版本、
失败处理和可复用证据。与本项目绑定的参数、路径和示例命令应明确标注，避免把未验证流程描述为可用。

## 当前状态

目录骨架已建立，日志 Skill 的本地副本位于 `6_skill/daily-engineering-log/SKILL.md`，可在此修改项目专用提示词。
后续新增脚本时，应在 `4_metrics/scripts/` 放置验证脚本，并在 `4_metrics/logs/` 和
`4_metrics/evidence/` 保存完整运行证据。

ViTA 可复用 Skill 的候选、适配边界和审核记录见 [`SKILL_REVIEW_PENDING.md`](SKILL_REVIEW_PENDING.md)。
已批准并落地：`engineering-organization`、`rtl-coding-standards`；`log-management` 已合并进
`daily-engineering-log`，不再建立第二套日志入口。
