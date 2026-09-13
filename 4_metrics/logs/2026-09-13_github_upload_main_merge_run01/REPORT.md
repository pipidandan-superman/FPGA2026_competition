# 个人分支关键资产发布与 main 合并审计

日期：2026-09-13  
目标分支：`codex/full/pipidandan-superman` → `main`

## 合并前基线

- `git fetch --prune origin` 后，个人分支相对 `origin/main` 为 `3 ahead / 0 behind`。
- 待合并既有提交：`612d7b3`、`63343aa`、`800a0d6`；它们覆盖模型 AXI/UART/LED 检查点、板端验证的 PL 重载器 v1.4 和发布回执。
- 原始主工作区存在未提交文件，因此不在其中暂存或切换分支；所有提交动作在独立个人分支工作树执行。

## 本次补充交付

1. `1_docs/doc/PC_PS_PL系统图集_20260913/`：6 页可编辑 Visio 图集、PDF、PNG、SVG、说明、浏览页和交付校验清单；同时更新文档索引。
2. `2_fpga/`：保留三个子工程的 RTL、BD/XCI、约束、构建脚本、发布 BIT/HWH/XSA、PYNQ 程序、仿真和 Vitis 源；排除 `*.cache`、`*.gen`、`*.runs`、`*.sim`、`.Xil`、`ipshared`、`__pycache__` 等可再生中间文件。
3. `8_tools/`：Action Viewer v1.0、BLE Console v1.0/v1.1 完整发布包和工具索引更新；分支中已有 PL Reloader v1.4 仍作为同一 PR 的既有交付保留。
4. `3_host/model_env/`、`1_docs/doc/` 的缺失关键脚本和参考源、当天 `7_logs/`，以及图集/MinerU/Git 发布审计证据。

清单：`selected_critical_assets.csv` 共 6,531 个文件、911,304,043 字节。MinerU 服务仍持有 `mineru_api_stdout.txt` 和 `mineru_api_stderr.txt` 的写入句柄，因此不复制这两份实时控制台副本；`mineru_result_marker.txt`、结果 JSON、Markdown、内容 JSON、输入清单和质量日志均在交付范围内。

## 验收口径

- 每个从主工作区复制到个人工作树的文件均应完成 SHA-256 相同核对。
- 通过项目路径审计、Git 暂存清单审计和提交前 `git diff --check`。
- 推送后，合并请求必须以 `main` 为目标并包含上述 3 条既有提交和本次补充提交；只经 PR 合并，不直接推送 `main`。
- 图集本身的静态交付结论保持 `PC_PS_PL_DIAGRAMS_DOCUMENTATION_PASS`，不把该文档验证写成新的板级验收。

## 结果

待执行完成后填写个人分支提交 SHA、PR 编号、合并提交 SHA、远端 `main` 回读和结果标记。
