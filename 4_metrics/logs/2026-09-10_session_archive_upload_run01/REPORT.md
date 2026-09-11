# 2026-09-10 关键证据归档与个人分支交付

完成结果：内容提交 `ae1384aea6f3390fb17ef78562eabf83f4677039` 已推送至 `codex/full/pipidandan-superman` 并核对远端一致；[草稿 PR #3](https://github.com/pipidandan-superman/FPGA2026_competition/pull/3) 已创建，目标 main，尚未合并。`archive_validation.json`、`staged_blob_validation.json`、`release_copy_validation.json` 记录通过的归档/资产/EXE检查，`upload_result.json` 和 `pr_result.json` 保存远端回执。后续提交仅补齐回执和文档。本轮精选交付提交包含 334 个文件；检查时的 317/326 是加入审计回执之前的分阶段清单计数。原始空白检查完整输出留在本机，编辑文档检查为零错误；资产和证据中的 CRLF/原始空白按哈希保留。

`selected_manifest.json` 是提交前的内容快照；本索引、README/HANDOFF 和当日日志后续增加了已推送回执，因此这些可变文档不再沿用该快照哈希。版本程序、资产、模板/成品及历史原始证据哈希保持不变；回执更新另由 Git 提交追溯。

本轮按用户要求归档现有成果，更新 README、HANDOFF 和当日四份日志，并上传个人分支 `codex/full/pipidandan-superman`。上传回执以本目录后续生成的 `upload_result.json` 为准；分支交付不代表已合入 main 或新增硬件验收。

## 阅读入口与验收边界

| 项目 | 关键证据 | 当前结论 |
|---|---|---|
| SD 静默根因 | [静态审计](../2026-09-10_sd_boot_static_audit_run01/DIAGNOSIS.md)、[G 盘核对](../2026-09-10_sd_card_g_audit_run01/REPORT.md)、[全卡审计](../2026-09-10_sd_card_full_audit_run01/REPORT.md) | 错误 BOOT 加载头、无调试打印/完整启动链，以及 Z2 设备树与板卡不匹配；未发现整卡读坏证据 |
| SD 修复与启动 | [修复报告](../2026-09-10_sd_boot_fix_run01/REPORT.md)、[原始 UART](../2026-09-10_pynq_v301_baseline_boot_run02/uart_pynq_log.txt) | 修复文件部署读回一致；实板已到 `xilinx@pynq:~$`，只认定 SD_BOOT_TO_LINUX_SHELL_PASS |
| 完整安装镜像 | [打包与读回](../2026-09-10_ees331_img_package_run01/REPORT.md) | FULL_IMG_PACKAGE_READBACK_PASS；非运行卡快照，完整 IMG 未复烧验收 |
| SD Builder v0.1 | [源码](../../../3_host/pynq/sd_boot_builder/README.md)、[验证报告](../2026-09-10_sd_builder_toolkit_run01/REPORT.md) | 旧版本原样保留，作为历史交付与回退参考 |
| SD Builder v0.2 | [源码与使用说明](../../../3_host/pynq/sd_boot_builder_v02/README.md)、[验证报告](../2026-09-10_sd_builder_v02_run01/REPORT.md) | 22 项规则测试、真实 FSBL/BSP 重建、EXE 构建和整卡读回通过；新输出 hardware_status=NOT_TESTED |
| AIPC 借用报告 | [Word 报告](<../../../1_docs/doc/AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx>)、[质量报告](../2026-09-10_aipc_loan_report_run01/REPORT.md) | 两页报告与版式核对完成；人员、编号、机型等待补充，尚未对外提交 |

9 月 8 日远程已有的裸机 Ethernet/UDP 摄像头与 PC BGR 修复记录保留在 README/HANDOFF：4.77 fps、1533+ 帧零丢失/CRC 与后续 6.3 fps、约 0.9% 丢失/CRC 是不同测量，不合并成一组指标。它们不构成 Linux/PYNQ 网络、Jupyter 或新 Overlay 的验收证据。模型推理和机械臂完整闭环仍按各自原始记录和后续实验判定。

## 精选范围与二进制说明

`selected_manifest.json` 列明每个候选交付文件的原路径、字节数、SHA-256 和收录原因，`selected_paths.txt` 是精确清单。`binary_manifest.md` 列出本次二进制的逐文件来源、大小、哈希及用途，先完成记录再暂存。未整目录上传 Vivado/Vitis 构建树、工具链、缓存和波形。

- v0.1 EXE：`8_tools/sd_start_tool/EES331SDBootBuilder.exe`，22,760,519 B，SHA-256 `7f57bc727c66abeb6d3a06fe849803fcab5712effa24ed36ae3c790797765984`。为保留用户要求的旧版应用而收录，源自 toolkit_run01 的已验证发行物。
- v0.2 EXE：`8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.exe`，22,776,980 B，SHA-256 `b4a2b971432dd91f70fc27a54e5f78670f3ac5ffb8c6b38cfbbb6843034a0a6e`。为跨机直接运行 GUI 而收录，源自 v02_run01 的最终发行物；仍需外部 Vitis 2025.2。
- 两版 assets 是源码启动包生成的必需输入，来源与处理过程见 toolkit_run01/prepare_assets.py、各版本 assets/manifest.json 及修复报告。Linux 内核和 U-Boot 载荷来自 PYNQ 3.0.1 基线，FSBL/DTB 为本板适配产物；不冒称全部从源码重建。同内容由 Git 对象去重。
- 参考 XSA：本目录 `reference_pynq_test_wrapper.xsa`，313,220 B，SHA-256 `b3343e2161fdfc4aa744a211e65059346ae48e0f7ea5f1b41b945e4f9124576a`；只读复制自本机 `2_fpga/3_pynq_test/vitis/pynq_test_wrapper.xsa`，便于复现输入。冻结源文件没有写入，也没有把整个 FPGA 工程纳入本次提交。
- 原始 UART SHA-256：`6122200aecca6987ec22b638893e1d34b72ffb07543dc85f15cfc38fd92be98b`。参考文档解析输出、选定接线图、GUI 图与报告两页检查图用于追溯依据。
- `.gitattributes` 保持发行源码、哈希资产和选定证据原始字节，避免 Git 换行转换令 assets 校验失败。原始日志可能含工具输出空白，保留不改。

## 本地保留的大文件

Git 不包含以下 IMG，也不上传两个应用的重复 ZIP。基础 IMG 需从本机交付到新机器，放在 EXE 旁或在高级设置选择；仅克隆仓库不能直接获得它。

| 用途 | 本机绝对路径 | 大小 / SHA-256 |
|---|---|---|
| v0.2 唯一认可的 EES-331 基础 IMG | `E:/competition/4_metrics/logs/2026-09-10_ees331_img_package_run01/ees331_pynq_v3.0.1_ps_sd_20260910.img` | 7,858,807,808 B；`203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a` |
| v0.2 最终完整构建测试 IMG | `E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_175423_0bb6c6/output/ees331_pynq_sd.img` | 7,858,807,808 B；`ae016a04126cb61a9893cf01e565135c5c49b5479ea75570d83b48917cd38eab` |

上述大镜像哈希来自已归档的完整构建/读回结果；本轮归档不重复跑多 GB 构建或改写 SD 卡。v0.1/v0.2 应用 ZIP 保留于本机对应 `8_tools` 目录，版本校验见旧版保留与新版发布报告。较早原始报告中的本机绝对路径、完整构建树与未选截图是来源记录，不承诺全部存在于 Git 克隆。

## 文档解析证据

本轮只归档现有文件，不重新解释 Office/PDF 内容。保留此前报告编写中的 MinerU 链路：DOCX 直接解析失败记录在 aipc_loan_report_run01；转 PDF 后的 `MINERU_PARSE_PASS`、Markdown/content JSON 与质量提示在 [aipc_template_pdf_run01](../2026-09-10_aipc_template_pdf_run01/)。该次短文本 review 已结合两页渲染核对。原模板 DOCX SHA-256 `ebbc3f74bb0e42663e54245efb0624ae4e692cf37f2110a5de9ac75a6dcfefa6`，转换 PDF SHA-256 `3c8598a76c21692b8223d97c16cb7e0c5f094e979aa0d880a77b35d129842bd9`。报告成品 SHA-256 `dc535ea60d83b79e10ffc81ed51c4ab4524b5b25b0363cbcf3170b7bd8823f7a`。

同时归档板卡手册与赛题的既有 MinerU 元数据、Markdown/content JSON；板卡仅选择与适配相关的接线图，不把部分图像选择声称为全部解析包。

## Git 流程与回退

原工作区在 main 且含用户其他未提交改动；保持其分支、索引和设计现场，仅按本任务更新文档。个人分支在 `E:/competition_worktrees/FPGA2026_competition/pipidandan-superman` 操作，基于远程 main `c60291a`，逐文件比较并复制精选新增内容；不重置、不清理原工作区。README/HANDOFF 从远程最新文档合并本地 9 月 10 日记录，保留 9 月 8 日结果。

提交前核对资产、发行物和文档哈希，检查精确暂存范围、敏感信息及冻结目录差异，运行路径审计。上传仅推送个人分支，核对远端 HEAD；如可用则建立面向 main 的草稿 PR，合并需另一成员审核。本轮没有修改冻结 FPGA、写卡、JTAG 操作或新增板测。回退应用使用保留的 v0.1 与已适配基础镜像；Git 回退应使用新提交/revert，经成员审核，不强推改写历史。
