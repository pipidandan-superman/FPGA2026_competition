# 2026-09-10 Daily Plan

## 最新：关键证据归档与个人分支上传

- 用户授权归档证据、更新日志/HANDOFF/README 并上传个人分支；按项目 Git、工作区和日志技能执行。
- 收录 SD 故障定位/修复/原始 UART、完整 IMG 读回、SD Builder 两版源代码与 EXE、AIPC 模板/成品/解析与两页 QA。大 IMG、重复 ZIP、工具链缓存保留本地。
- 使用已合入远程 main 的最新文档为基线，保留 9 月 8 日 UDP 板测和 BGR 修复记录。原工作区其他改动不纳入归档，冻结 2_fpga 不改。
- 交付入口：[归档索引](../../4_metrics/logs/2026-09-10_session_archive_upload_run01/REPORT.md)。当前目标分支 `codex/full/pipidandan-superman`；完成状态以该目录 upload_result.json 的远端核对为准。

## 最新：AMD AIPC 借用报告已编写

- 用户要求参照 `1_docs/doc/AMD AIPC 借用报告 - 模板.docx`，输出同目录。已完成“锐眼·智行”两页DOCX，模板原件保留。
- 报告按当前EES-331/OV5640/VDMA/HDMI、Linux启动及拟定AI PC视觉分拣路线编写，区分实测基础和待联调任务。
- 尚缺队长/学校/联系方式/教师信息；编号与机型待确认，已提示并使用显式待填字段。正文、两张框图和排版检查完成。

## 最新：SD Builder v0.2 已完成，v0.1 保留

- 用户授权“保留这一版，并且生成新版本”，本轮已完成新版源码/EXE/ZIP。入口为 `E:/competition/8_tools/sd_start_tool_v0.2/`；旧版源/EXE/ZIP 19 项哈希未变，原 `8_tools/sd_start_tool/` 也保留。
- 修正：基础 IMG 固定为适配后的 EES-331；XSA+板级模板自动生成 PS DT；高级 DTB 覆盖；辅助 HWH 识别；三种 PL 模式说明、USB 角色及可滚动高级页面。
- 22 项测试、真实 FSBL/BSP 重建与完整 IMG、EXE 自检/构建/FSBL载荷校验和发布包验证通过。新输出未上板，本轮未写卡或修改冻结工程。
- 交付报告：`4_metrics/logs/2026-09-10_sd_builder_v02_run01/REPORT.md`。后续目标为实际新 XSA 的冷启动和外设/PL 验收。下方 v0.1 是历史记录。

## 最新：XSA SD Builder 工具包原型已完成

- 用户要求本地应用输入硬件文件生成SD启动包，并明确强制提供含bitstream的XSA。已实现Windows GUI＋EXE＋后端，当前支持EES-331/2025.2/PYNQ3.0.1。
- 主目标已完成：XSA检查/PS差异、FSBL重建、三种PL加载方式、BOOT/FIT/ZIP及完整IMG输出，附文件校验和日志。影响PS外设的变化需要匹配DTB，未知驱动与外部器件配置不猜测生成。
- 软件验证已通过，原型新输出未上板。本轮不写卡、不改冻结工程；保留此前已启动基线。
- 交付和后续入口：`3_host/pynq/sd_boot_builder/README.md`、`4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/REPORT.md`及distribution/EXE。下一步使用实际新XSA分阶段板测，并按需要扩展板级DT生成规则。

## 最新：SD/Linux Shell 启动通过，完整 IMG 已生成

- 用户提供 uart_pynq_log.txt，确认 FSBL→U-Boot→Linux Shell 已启动；本轮将结果更新为 SD_BOOT_TO_LINUX_SHELL_PASS，网络/Jupyter/应用 Overlay 仍未验收。
- 用户询问整卡打包与后续 PL 更新，已基于原版 IMG 合入已部署文件，生成 `4_metrics/logs/2026-09-10_ees331_img_package_run01/ees331_pynq_v3.0.1_ps_sd_20260910.img`。
- 打包全文件读回通过，启动分区外全部字节保持原版；不含首次运行后配置。本轮不烧卡、不改冻结 FPGA 工程。
- 已交付镜像/SHA256/打包脚本/PL 文件更新矩阵，详见该 run 的 REPORT.md。当前下一目标是新 IMG 烧录复验与网络/Overlay分阶段验收。

以下为本日此前状态。

## 最新目标与结果：完成 SD 启动文件修正（16:10 更新）

- 用户授权“根据查验的问题完整修正”。本轮已完成隔离 FSBL 重编、BOOT 三阶段打包、U-Boot 控制 DTB/FIT 设备树适配、停用 Z2 Overlay 自动加载，并实际写入 G 盘。
- 结果：`SD_BOOT_CANDIDATE_STATIC_PASS`（240 项）和 `SD_DEPLOY_READBACK_PASS`；写后 FAT 检查无问题，板级启动 `NOT_TESTED`。
- 当前主目标转为使用本次文件冷启动，取得 FSBL → U-Boot → Linux 串口原始记录，再验收根分区/网络/Jupyter。
- 交付：`4_metrics/logs/2026-09-10_sd_boot_fix_run01/REPORT.md`、候选文件、原文件备份、构建/校验证据、带身份和哈希检查的部署/回退脚本。
- 本轮边界：冻结 `2_fpga/` 未改；未写 Linux 根分区；不把 USB/I2C/QSPI/自定义 Overlay 或 PYNQ 完整功能标记为已完成移植。

以下为本日历史计划与修复前判断；其中“未写卡/待授权修复”已由以上已执行记录替代。

## 修复前判断（历史）

- 最新“全面检查”已完成：整卡 15,634,268,160 B 只读扫描无错误，Linux 分区与原版逐字节相同；缺陷是 BOOT 打包/FSBL 打印/缺少 U-Boot，以及原版设备树 UART0、50MHz、512MiB 与 EES-331 不匹配。详见 `4_metrics/logs/2026-09-10_sd_card_full_audit_run01/REPORT.md`。下一目标为分阶段修复验证，本轮未写卡或改工程。

- PYNQ 部署计划已修订至 v1.1（`1_docs/doc/EES-331_PYNQ从零部署计划_2026-09-09.md`）：经工程文件核实（`.xpr` 头部 + XSA 内部元数据 `Version="2025.2"`），冻结基线工具链为 Vivado/Vitis 2025.2 而非 v1.0 所写 2020.2，路线 A 无需另装 2022.2。
- 用户已接好网络环境，明确指示下载必要文件至 `E:\competition\3_host\pynq\download` → 启动阶段 0 的"下载与校验"项。
- 赛题结论不变：PYNQ 非强制（鼓励项/加分项），本工作服务于鼓励项与 Skill 加分。

## 主目标

完成 PYNQ 部署阶段 0 的下载项：PYNQ-Z2 v3.0.1 官方镜像 + PYNQ v3.0.1 源码包，落 `3_host/pynq/download`，SHA-256 入证据 run 目录。

## 任务（优先级）

1. （已完成）计划文档 v1.0 → v1.1 修订：工具链事实修正、镜像直链补充、风险降级。
2. （已完成）下载 `pynq_z2_v3.0.1.zip`（1,811,523,457 B）与 `PYNQ-v3.0.1.tar.gz`（31,085,104 B）。
3. （已完成）完整性校验与 SHA-256 记录，写入 `4_metrics/logs/2026-09-10_pynq_stage0_download_run01/00_download_manifest.md`。
4. （已完成）本日四件套建立。
5. （已完成，同日追加）阶段 2 步骤 1：16G 卡烧录原版 PYNQ-Z2 v3.0.1 镜像、上板启动测试；8G 卡由用户另行烧录测试（结果见 03_validation_summary 追加节）。
6. （已完成，同日追加）用户自建最小系统工程 `2_fpga/3_pynq_test`（PS 勾选 ENET0/SD0/UART1），经命令行生成 fsbl.elf 与 BOOT_MIN.BIN（run03）并替换卡上 BOOT.BIN。
7. （历史暂停点）JTAG 诊断曾等待供电确认；当前用户已明确确认 SW8 为 SD 启动且上电成功，不再重复以此为阻塞。
8. （同日追加，已完成）SD 静默只读分析：发现 run03 BIF 缺失 `[bootloader]` 导致 BIN 的 FSBL 偏移/长度全零，同时 FSBL 未开启调试打印；证据 `4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/`。当前优先修复启动镜像与打印判据，板级恢复未验证。

## 非目标

同日追加：用户要求检查 G 盘，已完成只读现场核对。实际 BOOT.BIN 与 run03 错误镜像逐字节一致；证据 `4_metrics/logs/2026-09-10_sd_card_g_audit_run01/`。未执行修复或写卡。

- 不烧卡、不解压镜像（留待阶段 2 步骤 1，需先确认 SD 卡容量）。
- 不动 `2_fpga/` 冻结内容；不新建 `2_fpga/2_pynq_port/`（需用户届时明确授权）。
- 不下载 v3.1.1 备选镜像（按需另行获取）。
- 不启动阶段 1 硬件工程。

## 预期交付物

- `3_host/pynq/download/`：两个已校验文件。
- `4_metrics/logs/2026-09-10_pynq_stage0_download_run01/00_download_manifest.md`。
- 本日四件套。
