# 2026-09-09 Daily Plan

## 当前判断

- 用户询问“PYNQ 是什么、赛题是否要求这样做”。这属于对 `1_docs/pdf/AMD赛题.pdf` 的内容级解读，必须走 MinerU。
- 旧产物 `1_docs/pdf/amd_sait题_mineru/parsed/` 为空目录，Markdown 与 content JSON 缺失，不满足复用条件，需重新解析。

## 主目标

1. 用本地 MinerU（pipeline 后端）重新解析 `E:\competition\1_docs\pdf\AMD赛题.pdf`。
2. 从赛题原文中核对所有 PYNQ 相关条款，回答“赛题是否强制 PYNQ”。

## 任务优先级

1. 新建证据目录 `4_metrics/logs/2026-09-09_amd_sait_pynq_mineru_run01` 并运行 MinerU。
2. 校验 `MINERU_PARSE_PASS`、Markdown、content JSON、中文质量检查。
3. 摘录 PYNQ 相关条款并给出结论。
4. 建立本日四个日志文件并挂接证据链接。

## 任务 2（同日追加）：EES-331 PYNQ 从零部署计划

- 用户追加询问：能否在当前板卡从零部署 PYNQ，并要求制定完整部署计划存入 doc。
- 判定：可行；产出计划文档 `1_docs/doc/EES-331_PYNQ从零部署计划_2026-09-09.md`。

## 非目标

- 不修改 `2_fpga/`（冻结基线）；不启动任何构建/烧卡动作（计划文档阶段）。
- 不改动现有 Vitis/RTL 主线方案。

## 预期交付

- MinerU 证据目录（marker、manifest、results、console/API 日志、Markdown、content JSON、页面图）。
- 对用户问题的结论：PYNQ 定义 + 赛题各条款中 PYNQ 的强制/推荐/加分属性。
- EES-331 PYNQ 部署计划文档（含可行性对比、路线、分阶段 PASS 判据、风险表）。
- `7_logs/2026-09-09/` 四个日志文件。
