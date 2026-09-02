# 执行计划

1. 将现有工程资料保持在编号归档目录：`1_docs`、`2_fpga`、`3_host`、`4_metrics`、`5_report`；
2. 将后续日志根目录固定为顶层 `7_logs`，不再写入 `1_log` 或 `2_log`；
3. 将日志 Skill 复制到 `6_skill/daily-engineering-log/SKILL.md` 并允许在本地修改提示词；
4. 保留空 FPGA 测试骨架并归入 `2_fpga/src`、`2_fpga/build`、`2_fpga/report`；
5. 用文件清单和哈希检查归档完整性。

候选 Skill 的复制、路径改写和依赖迁移必须等用户明确批准编号后执行；本轮已收到批准并完成 A1/A2/A3 的限定范围操作。

用户已批准 A1、A2、A3。本次实际执行为：复制 A1/A2 到 `6_skill/`，把 A3 的日志边界和证据规则合并到 `daily-engineering-log`；没有处理 A4/B1/C1/C2。

风险：AMD PDF 解析工具对中文文件名返回 500；已使用短名重试仍失败，条款依据改用本地 PDF 的 pypdf 文本提取，
并以第 17–19 页的 3.2.5 条款和目录图为边界。该解析失败不影响原 PDF 归档。
