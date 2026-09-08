# 可复用 Skill 与工具

## 归档要求

每个 Skill 或工具条目应说明：适用范围、输入/输出、使用步骤、失效条件、已验证设备/软件版本、
失败处理和可复用证据。与本项目绑定的参数、路径和示例命令应明确标注，避免把未验证流程描述为可用。

## 当前状态

2026-09-06 新增仿真 Skill 参考副本，并已完成 `E:\competition` 项目适配：

- `modelsim-local-sim/`：ModelSim 后台/命令行仿真流程；
- `modelsim-gui-sim/`：已打开 GUI Transcript 的回退仿真流程；
- `vita-vivado-batch-sim/`：EES-331/Vivado 2025.2 XSim 批处理流程；目录名保留
  历史 `vita` 前缀，但输出路径和结果标记已改为本工程规范。
- `mineru-doc-reader/`：PDF、扫描文档图片及 Office 参考文件的强制 MinerU 解析流程；输入按 SHA-256 建档，完整原始产物写入 `4_metrics/logs`，最终报告可交付到 `1_docs`。

统一强制路径：

- 工作区根：`E:\competition`；
- 工程日志：`E:\competition\7_logs\YYYY-MM-DD`；
- 原始证据：`E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN`；
- 冻结 FPGA 基线：`E:\competition\2_fpga`（默认只读）。

禁止把新日志写入 `2_log`、`log`、`logs`、`D:\VitA` 或旧桌面工程路径；禁止把
仿真库、波形、报告或构建临时文件放在仓库根目录或 `2_fpga` 内。

日志 Skill 的本地副本位于 `6_skill/daily-engineering-log/SKILL.md`，可在此修改项目专用提示词。
后续新增脚本时，应在 `4_metrics/scripts/` 放置验证脚本，并在 `4_metrics/logs/` 和
`4_metrics/evidence/` 保存完整运行证据。

文档内容解析的活动入口是 `.codex/skills/mineru-doc-reader/SKILL.md`。对 PDF、扫描页、DOCX、PPTX、XLSX 等文件进行内容读取、总结、问答、表格提取或技术解释前必须调用该技能；仅列目录、计算哈希、重命名等元数据操作不触发。活动副本和本目录参考副本应保持哈希一致。

可复用 Skill 的候选、适配边界和审核记录见 [`SKILL_REVIEW_PENDING.md`](SKILL_REVIEW_PENDING.md)。
已批准并落地：`engineering-organization`、`rtl-coding-standards`；`log-management` 已合并进
`daily-engineering-log`，不再建立第二套日志入口。项目强制策略的生效层是
`.codex/skills/project-workspace-policy/SKILL.md`；本目录是人工维护的参考副本，
两者冲突时以 `.codex/skills` 为准。
