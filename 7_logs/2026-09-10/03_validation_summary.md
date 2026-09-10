# 2026-09-10 Validation Summary

## 最新：关键证据归档与上传验收

最终结果：`ARCHIVE_CONTENT_VALIDATION_PASS`、`STAGED_BLOB_HASH_PASS`、两版 `FROZEN_GUI_SELF_TEST_PASS`、路径审计 PASS；个人分支内容提交 `ae1384aea6f3390fb17ef78562eabf83f4677039` 与远端一致，`PERSONAL_BRANCH_PUSH_PASS`。草稿 PR #3 已建立且以 main 为目标。18 项资产和 300 项暂存哈希核对通过；冻结目录/原索引无新增改动。完整 diff --check 报原始证据/发行资产 CRLF 与空白，保留其哈希；本次编辑文档检查通过。原始推送、PR 回执见本 run 的 `push_console.txt`、`upload_result.json`、`pr_result.json`。

- 证据入口：[归档索引](../../4_metrics/logs/2026-09-10_session_archive_upload_run01/REPORT.md)。清单 selected_manifest.json 记录每个精选文件大小/SHA-256/来源；归档校验、Git 检查与上传回执保存在同一 run。
- 已读取原始结果：SD/Linux Shell 启动 PASS；v0.2 22 项规则测试、真实 FSBL/BSP 与 IMG 读回 PASS；v0.1 保留检查 PASS；AIPC 文档两页 QA PASS_WITH_PENDING_FIELDS。本次归档不重新声称新增板测 PASS。
- 保留板卡手册、赛题和模板此前 MinerU 解析证据。模板 DOCX 直接解析失败→转换 PDF 后 PASS 的链路及短文本人工核对提示一并归档；没有静默改用其他语义解析器。
- 9 月 8 日裸机 UDP/BGR 板测仍有效；Linux 网络、Jupyter、新 Overlay 与完整任务闭环另行验收。
- 本轮验收标准：精选内容哈希一致，远程原有事实保留，暂存中 2_fpga/IMG/ZIP/缓存为零，源工作区冻结差异哈希不变，项目路径审计通过；远端个人分支 HEAD 与交付提交一致。检查结果以本 run 的 archive_validation.json / upload_result.json 为准。

## 最新：AMD AIPC 借用报告文档验证

- 成果 [AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx](<E:/competition/1_docs/doc/AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx>)，2页，状态 `REPORT_DOCUMENT_QA_PASS_WITH_PENDING_FIELDS`；[编制与验证报告](E:/competition/4_metrics/logs/2026-09-10_aipc_loan_report_run01/REPORT.md)。
- 原模板SHA256 `EBBC3F74BB0E42663E54245EFB0624AE4E692CF37F2110A5DE9AC75A6DCFEFA6` 未变；输出SHA256 `DC535EA60D83B79E10FFC81ED51C4AB4524B5B25B0363CBCF3170B7BD8823F7A`。
- 原DOCX MinerU `MINERU_PARSE_FAIL`（缺Markdown/JSON）已披露并保留；转换PDF后run [2026-09-10_aipc_template_pdf_run01](E:/competition/4_metrics/logs/2026-09-10_aipc_template_pdf_run01/mineru_results.json) 为 `MINERU_PARSE_PASS`，2图片、Markdown/JSON完整。PDF SHA256 `3C8598A76C21692B8223D97C16CB7E0C5F094E979AA0D880A77B35D129842BD9`；质量review/short_text已人工复核。完整MD/JSON路径与回退解释见编制报告。
- 模板与新报告各2页，section/page尺寸/边距不变；仅document.xml与两个图片部件修改，其余包部件保留。参考与最终PNG、fidelity diff、style/section检查及 `package_audit.json` 均在报告run。
- 文档明确区分已板测摄像头显示/SD-Linux启动、软件启动包验证和后续AI/网络/执行闭环。未将旧方案性能目标或其他机器的历史AI结果写成当前实测。
- 姓名/学校/邮箱/电话/教师待补充，模板4062编号待确认，37032G机型暂拟申请；未提交借用申请或发送文件。未改冻结工程。

## 最新：EES-331 SD Builder v0.2 发布验证通过

- [完整报告](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/REPORT.md)；[新版程序](E:/competition/8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.exe)；[工具ZIP](E:/competition/8_tools/sd_start_tool_v0.2/EES331_SD_Builder_v0.2.zip)。
- 22项测试 PASS，原始输出 [tests_release_console.txt](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/tests_release_console.txt)。覆盖自动 PS DT、输入/外设门禁、辅助 HWH、原版Z2镜像拒绝、GUI。合成PS变更仅证明生成规则，不证明外设板测。
- 完整IMG/FSBL+BSP重建 PASS：[result.json](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_175423_0bb6c6/result.json)。IMG全量读回PASS、启动分区外字节不变，SHA256 `ae016a04126cb61a9893cf01e565135c5c49b5479ea75570d83b48917cd38eab`。模式Linux后自动加载，参考最小XSA，未板测。
- 最终EXE自检 [frozen_self_test_final.json](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/frozen_self_test_final.json) PASS。EXE手动构建 `2026-09-10_sd_builder_v02_175742_16fccb` PASS；最终EXE FSBL模式 [result.json](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_180104_171c99/result.json) PASS，BOOT四分区/真实PL载荷匹配。
- 实际GUI默认及高级页截图在run01 `gui_default.png`、`gui_advanced.png`，高级设置滚动后底部日志/状态可访问。
- [release_result.json](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/release_result.json) 为 `V02_RELEASE_PACKAGE_PASS`；[旧版核对](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/v01_preservation_result.json) 为 `V01_PRESERVATION_PASS`（19项）。原8_tools旧版文件保留；源码/发布校验清单完整。
- MinerU历史复用已披露并核验：输入SHA256 `27C26F39F3E35132A89FAE2155FA23575E850B0A22E3D9DC64FD73186B3F5949`，`MINERU_PARSE_PASS`、质量pass、无fallback；[复用记录及Markdown/内容JSON路径](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/mineru_reuse.json)。用于板级UART/USB/QSPI规则。
- [路径审计](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/skill_path_audit_console.txt) pass=true。新输出硬件状态 `NOT_TESTED`；未写SD、未改冻结工程，新增PHY复位等规则需要新一轮冷启动验收。下方v0.1为保留历史。

## 最新：EES-331 SD Builder 0.1 软件交付验证

- 强制输入含bitstream的XSA，拒绝缺bit/错误器件/错误UART/截断位流；从同一包提取HWH与PS初始化。10项输入/GUI测试通过（tests_console.txt）。
- 源码路径 `3_host/pynq/sd_boot_builder/`；EXE [EES331SDBootBuilder.exe](../../4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/distribution/EES331SDBootBuilder.exe)。[报告](../../4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/REPORT.md) 与 [使用说明](../../3_host/pynq/sd_boot_builder/README.md)。
- 真实FSBL/BSP重新生成+Linux自动加载+完整IMG：`2026-09-10_sd_builder_165718_5e2d15`，BOOT/FIT/ZIP PASS、IMG全读回PASS、根分区不变；测试IMG SHA256 8673ef8329d2a6ad7dec4a70f5138fdd1d53e5b04a98cb45c8b68d3ee4e119c5。
- FSBL模式 `2026-09-10_sd_builder_170008_760643`：4分区启动链及PL载荷对比PASS。手动模式 `2026-09-10_sd_builder_165549_b92f74`，真实启动ZIP构建PASS。
- EXE自检 `frozen_self_test.json` 为FROZEN_GUI_SELF_TEST_PASS；EXE实际构建见 `frozen_build_config.json.result.json` 和 `2026-09-10_sd_builder_170040_95e111`。工具构建/依赖/测试原始输出都在toolkit_run01。
- 生成目录先.pending-output，所选检查成功后才发布output。新XSA新位流板测状态NOT_TESTED；复杂PS外设配置要求匹配DTB，内核驱动/任意外部连线适配不包含在当前自动化承诺。未写SD，冻结工程不改。

## 最新：SD/Linux Shell 启动 PASS，整卡 IMG 打包 PASS

- 用户补充粘贴日志已归档新 run 的 `uart_user_pasted.txt`，FIT内核/DTB SHA1与封装版本匹配，确认 UART1、1GiB和Shell；详细检查 `uart_pasted_review.json`。Jupyter只有Starting、随机MAC和zocl IRQ等问题仍需单独验证。项目技能路径审计 pass=true；证据哈希在 `evidence_sha256.json`。
- 用户 UART [uart_pynq_log.txt](../../4_metrics/logs/2026-09-10_pynq_v301_baseline_boot_run02/uart_pynq_log.txt) 已出现 FSBL SD启动、SUCCESSFUL_HANDOFF、U-Boot、EES-331 Linux、`xilinx@pynq:~$`。结果 `SD_BOOT_TO_LINUX_SHELL_PASS`。源日志 SHA256 `6122200aecca6987ec22b638893e1d34b72ffb07543dc85f15cfc38fd92be98b`，副本归档新 run。
- 完整 IMG [ees331_pynq_v3.0.1_ps_sd_20260910.img](../../4_metrics/logs/2026-09-10_ees331_img_package_run01/ees331_pynq_v3.0.1_ps_sd_20260910.img)，7,858,807,808 B，SHA256 `203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a`。
- 结果 `FULL_IMG_PACKAGE_READBACK_PASS`：输出全量读回、六个启动文件与部署清单一致、FAT副本和文件链通过、启动分区之外全部字节保持原 IMG、根分区不变。镜像是安装基线，不是上板首次运行后的卡快照。
- 原始证据：[package_result.json](../../4_metrics/logs/2026-09-10_ees331_img_package_run01/package_result.json)、[package_console.txt](../../4_metrics/logs/2026-09-10_ees331_img_package_run01/package_console.txt)、[fat_validation.json](../../4_metrics/logs/2026-09-10_ees331_img_package_run01/fat_validation.json)、[block_verification.json](../../4_metrics/logs/2026-09-10_ees331_img_package_run01/block_verification.json)。完整说明/PL更新矩阵：[REPORT.md](../../4_metrics/logs/2026-09-10_ees331_img_package_run01/REPORT.md)。
- 证据边界：新 IMG 尚未重新烧录上板；原文件版本已有 UART 启动证据。日志仍有 U-Boot PHY读取/默认环境警告、Linux随机MAC、FSBL部分调试数值异常，保留为后续问题；网络/Jupyter/Overlay未验收。本轮未改变启动行为以免将新改动混入通过的版本。

下方 NOT_TESTED 是当时写卡阶段的历史状态，已由本节的 UART 证据更新。

## 修正版已部署 G 盘（最新，2026-09-10 16:09:58 +08:00）

- 用户授权“根据查验的问题完整修正”，本轮实际完成文件修正和写卡。静态结果 `SD_BOOT_CANDIDATE_STATIC_PASS`（240 项）；部署结果 `SD_DEPLOY_READBACK_PASS`；板级状态 `NOT_TESTED`。
- 修复：有效 `[bootloader]` 启动头、带 DEBUG 的 FSBL、补全 U-Boot+控制 DTB，BOOT/FIT 同步 UART1/33.333333MHz/1GiB/PHY0，匹配最小 XSA 的设备状态，取消 boot.py 自动加载 Z2 base.bit。原版 U-Boot 程序载荷复用，经实际二进制验证读取外部 DTB；内核未变。
- 校验：BOOT 头和全部分区 checksum、OCM 范围、FSBL ELF 与载荷、U-Boot 原始字节/入口地址、FIT SHA1/默认配置/内核参数、DTB phandle/时钟/alias/symbol 均通过；DTC 二进制 roundtrip 零警告。源级 numeric-phandle 警告有记录和说明。
- G 盘：磁盘 1、容量 15634268160；替换 BOOT.BIN/image.ub/boot.py、新增 system.dtb，保留 boot.scr/REVISION。六个文件读回一致，FlushFileBuffers 成功；`chkdsk G:` 只读写后检查无问题。备份五个原文件在 run 的 sd_backup，根分区未写，冻结工程未改。
- 新 BOOT SHA256：`3ea3eae30dba8646ddb597abf098594a99ed6c0250576bed12a9eca91c3902a0`；新 FIT：`6c101d5352e8da48e9ee5493135621c0e62f148023fcf4826ebabbe4e0f194d0`。全部文件清单以部署结果为准。
- 报告：[REPORT.md](../../4_metrics/logs/2026-09-10_sd_boot_fix_run01/REPORT.md)。原始证据：[candidate_validation.json](../../4_metrics/logs/2026-09-10_sd_boot_fix_run01/candidate_validation.json)、[deploy_result.json](../../4_metrics/logs/2026-09-10_sd_boot_fix_run01/deploy_result.json)、[部署控制台](../../4_metrics/logs/2026-09-10_sd_boot_fix_run01/deploy_20260910_160957_console.txt)、[写后 FAT 检查](../../4_metrics/logs/2026-09-10_sd_boot_fix_run01/chkdsk_after_deploy.txt)、[U-Boot 外部 DTB 指令证明](../../4_metrics/logs/2026-09-10_sd_boot_fix_run01/uboot_external_dtb_proof.json)。构建/BIF/DTS/校验和部署脚本同目录。
- 技能路径审计 pass=true。验收边界：离线文件修正已完成，冷启动 FSBL→U-Boot→Linux、网络/Jupyter 和 EES-331 Overlay 尚无本轮板测 PASS；最小 XSA 未开 USB/I2C/QSPI，因此 DT 同步禁用这些设备。

以下为修复前历史审计；旧整卡哈希对应修复前介质，不能当作当前卡哈希。

## 全面检查完成（历史）

- 结果：`FULL_SD_AUDIT_COMPLETE_WITH_BOOT_AND_PORTING_DEFECTS`；板级启动未测试。用户确认 SD 拨码和上电成功仍为排查前提。
- 全卡读完 15,634,268,160 B，0 错误，870.21 秒；全卡 SHA-256 `5ecfc64c109302c0a2e9cdda1cb4a318f09197c19f0468d90a033e2fd730dfce`。MBR 与原版相同；根分区全部 7,721,444,352 B 与原版逐字节一致。
- ZIP 哈希/解压流 CRC 通过，本地 IMG SHA-256 与 ZIP 解压内容同为 `f17405d25298a2c5ea23ccf95f868b42b18f819ff9d7fe5d079ac9ef53415861`；G 根目录除 BOOT.BIN 外的原版文件均相同。
- chkdsk G: 只读检查无问题。BPB 实际 FAT16、MBR 类型字段 0x0C；这一差异原版已存在，旧日志直接称 FAT32 不准确，不能据此判新故障。卡上两份 FAT 一致。
- BOOT.BIN 仍是缺 bootloader 标记、FSBL 偏移/长度为零的普通 ELF 镜像，且无 U-Boot；Bootgen 原生只读解析再次确认。FSBL 调试宏未开启的问题仍有效。
- 新增确定适配问题：image.ub 内 DTB 的 serial0→UART0@e0000000，UART1 disabled；ps-clk-frequency=50MHz，memory=512MiB；EES-331 为 J3/UART1、33.333333MHz、1GiB。FIT 内核/DTB hash 本身通过，属于配置不适配而非烧录损坏。
- 原版 BOOT.BIN 内 DTB 与 FIT 内 DTB 相同；boot.scr 优先启动 FIT，因此只添加根目录 system.dtb 不能保证生效。当前最小 XSA 的 SD0 MIO40..45、CD=MIO0 与手册相符，不能继续当作已知故障。
- Linux 目录遍历 21,862 个目录、177,234 普通文件目录项、20,733 符号链接，无解析异常；systemd/Python/PYNQ/Jupyter/resizefs 存在。boot.py 会自动加载 Z2 base.bit，属于后续 Linux/Overlay 适配待办。未运行 e2fsck 或写入型介质/容量验证。
- 报告：[REPORT.md](../../4_metrics/logs/2026-09-10_sd_card_full_audit_run01/REPORT.md)。原始证据：[scan_result.json](../../4_metrics/logs/2026-09-10_sd_card_full_audit_run01/scan_result.json)、[scan_console.txt](../../4_metrics/logs/2026-09-10_sd_card_full_audit_run01/scan_console.txt)、[card_bootgen_read.txt](../../4_metrics/logs/2026-09-10_sd_card_full_audit_run01/card_bootgen_read.txt)、[embedded_device_tree.json](../../4_metrics/logs/2026-09-10_sd_card_full_audit_run01/embedded_device_tree.json)、[rootfs_extended.json](../../4_metrics/logs/2026-09-10_sd_card_full_audit_run01/rootfs_extended.json)。其余脚本/CRC/哈希/超级块证据同目录。
- MinerU 有效复用：[mineru_reuse.json](../../4_metrics/logs/2026-09-10_sd_card_full_audit_run01/mineru_reuse.json)；旧 run `2026-09-08_eth_zynq_psw_check_mineru_run01` 为 MINERU_PARSE_PASS，手册本次实算 SHA-256 `27C26F39F3E35132A89FAE2155FA23575E850B0A22E3D9DC64FD73186B3F5949` 匹配，Markdown/413 项 content JSON 完整，quality=pass/fallback=false，已检查 SD 配置图。
- 判据：本轮只读检查完成；修复后需分开证明 FSBL、U-Boot、Linux 串口、根分区、网络/Jupyter 和适配 Overlay。未写卡、修改冻结工程或重新上板。

## G 盘现场读取确认（2026-09-10 15:30，最新）

- 结果：`SD_CARD_G_BOOT_DEFECT_CONFIRMED`。G: 为磁盘 1 的 PYNQ 启动分区，卡容量 15,634,268,160 B；存在另一个无盘符分区。
- 实际 `G:/BOOT.BIN` 为 91,856 B，SHA-256 `EB88AA570030FA9D98F5B962C954DED787F0CCB85330326D029730654E466667`，与 run03 BOOT_MIN.BIN 逐字节相等。启动头 0x30/0x34/0x40 均为 0，现场确认打包缺陷仍在卡上。
- boot.py、boot.scr、image.ub、REVISION 均存在且可完整读取，全部哈希已记录；未验证 Linux 分区、全卡介质或完整系统兼容性。未写卡或进行板测。
- 证据：[REPORT.md](../../4_metrics/logs/2026-09-10_sd_card_g_audit_run01/REPORT.md)、[console.txt](../../4_metrics/logs/2026-09-10_sd_card_g_audit_run01/console.txt)、[file_hashes.json](../../4_metrics/logs/2026-09-10_sd_card_g_audit_run01/file_hashes.json)。
- 命令：`powershell -ExecutionPolicy Bypass -File E:/competition/4_metrics/logs/2026-09-10_sd_card_g_audit_run01/check_sd.ps1`。静态检查完成，修复后冷启动仍待验证。

## 最新结论：SD 静默静态审计（优先于下方历史判断）

- 用户当前已确认 SW8 为 SD 启动、上电成功；不再把重复确认拨码/供电作为下一步前置。
- 结果：`STATIC_BOOT_IMAGE_DEFECT_CONFIRMED`，尚未验证板级恢复。
- run03 `fsbl_only.bif` 缺失 `[bootloader]`；实际 `BOOT_MIN.BIN` 在 0x30/0x34/0x40 的 FSBL 源偏移/长度/总长度均为 0。该 BIN 哈希与此前记录的卡上 BOOT.BIN 一致（本轮未重新读卡）。这已构成最小镜像的启动打包缺陷。
- FSBL Makefile/构建命令没有 `FSBL_DEBUG` 或 `FSBL_DEBUG_INFO`；实际 ELF 中横幅和关键错误字符串均不存在。旧“上电应有 FSBL 横幅”的判据无效，即使修复启动头仍需启用打印并重编。
- run03 仅含 FSBL，没有 U-Boot，因此不能用于完整 PYNQ 启动；也不能将本次最小镜像错误反推为原版 PYNQ-Z2 镜像静默的同一原因。
- 旧“定案 DDR 训练失败”缺少执行位置证据；旧 BOOT_MODE=0 仅适用于修正拨码前，JTAG 全 1 不能单独证明没上电。
- 审计报告：[DIAGNOSIS.md](../../4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/DIAGNOSIS.md)。原始证据：[audit_console.txt](../../4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/audit_console.txt)、[fsbl_readelf.txt](../../4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/fsbl_readelf.txt)、[fsbl_strings.txt](../../4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/fsbl_strings.txt)。
- 命令：`powershell -ExecutionPolicy Bypass -File E:/competition/4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/audit.ps1`。只读项目源码/产物，未接板、写卡、重编或解析 PDF/Office。
- 后续验收：启动头非零有效、DEBUG 编译与横幅字符串存在、SD 冷启动实际 UART/阶段证据齐全；目前仅前述缺陷定位完成。

## 已验证事实

1. **冻结基线工具链 = Vivado/Vitis 2025.2**（v1.1 修订依据）：
   - `2_fpga/0_diaplay_test/proj/display_test_zynq7020_school/display_test_zynq7020_school.xpr` 头部：`Product Version: Vivado v2025.2 (64-bit)`。
   - XSA `2_fpga/0_diaplay_test/vitis/display_test_plat/export/display_test_plat/hw/display_test_wrapper.xsa`（2026-09-08 导出）内部元数据两处 `Version="2025.2"`。
   - `1_docs/Zynq_PS7_Config_Report.md` 所称 "Vivado 2020.2 导出" 源自旧位置 `D:/VitA/6_proj/vitis/vita_wrapper.xsa`，已被现工程取代；该报告的 DDR 参数表落地时以当前 2025.2 工程 `ps7_init.tcl` 复核（已写入计划 v1.1）。
2. **计划文档修订完成**：`1_docs/doc/EES-331_PYNQ从零部署计划_2026-09-09.md` v1.0 → v1.1，9 处修正（详见 02_execution_plan 任务 1）。
3. **下载与校验 PASS**（证据：`E:\competition\4_metrics\logs\2026-09-10_pynq_stage0_download_run01\00_download_manifest.md`）：
   - `pynq_z2_v3.0.1.zip`：1,811,523,457 B，与服务器 Content-Length 精确一致；SHA-256 `ea6372e2d95e241dc7f891d30abc8af2eaf6650c0c16788c27dafba97f41cf8b`；`unzip -l` 内含单一 `pynq_z2_v3.0.1.img`（7,858,807,808 B ≈ 7.32 GiB）。
   - `PYNQ-v3.0.1.tar.gz`：31,085,104 B；SHA-256 `2349eea4d39abec2d581ee584a68d17ca00243436cec409c1b1a066b386acacd`；`tar -tzf` 顶层 `PYNQ-3.0.1/` 正常。
   - 位置：`E:\competition\3_host\pynq\download\`（用户指定）。

## PASS/FAIL 判据对照

- 阶段 0 计划 PASS 判据（下载部分）：
  - "镜像 SHA-256 记录入 run 目录" → **PASS**（manifest 已落）。
  - "镜像与工具就位清单写入当日日志" → 镜像部分 **PASS**（本文件）；工具部分 **未完成**（`dtc`/`mkimage`、balenaEtcher、Linux 环境确认待做）。
- 硬件物料确认（SD 卡/读卡器/网线/跳帽设置）未确认 → 阶段 0 整体尚未关闭。

## 阶段 2 基线启动与 JTAG 诊断客观时间线（run02/run03，2026-09-10）

### 测量与操作记录（按时间顺序）

1. 烧录：16G 卡（15,634,268,160 B）写入原版 PYNQ-Z2 v3.0.1 镜像，Windows 侧回读验证：分区 1 = 130MB FAT32（BOOT.BIN/REVISION/boot.py/boot.scr/image.ub），`REVISION` 内容 `Release 2022_10_22 93ddd21`；分区 2 = 7,721,444,352 B。
2. 原版镜像上板（SW8 经用户按口诀拨杆，串口 COM6 打开 115200-8-N-1）：串口无输出。
3. 用户报告 8G 卡（SanDisk，7,948,206,080 B）另烧原版镜像上板测试：串口无输出。
4. 用户自建工程 `E:\competition\2_fpga\3_pynq_test`（Vivado 2025.2，PS 勾选以太网/SD/UART，用户报告 DDR 选型正确）。经 XSA 内 hwh 提取核对：PCW_SD0_PERIPHERAL_ENABLE=1、PCW_UART1_PERIPHERAL_ENABLE=1（MIO 48..49，115200）、PCW_ENET0_PERIPHERAL_ENABLE=1（MIO 16..27，MDIO 52..53）、晶振 33.333333、DDR PARTNO=MT41K256M16 RE-15E/32Bit/533.333333MHz/训练开/外部 Vref；与冻结 XSA 的重叠参数 diff 仅 FCLK0 一项不同（新工程 FCLK0 未开，PCW_FPGA_FCLK0_ENABLE=0）。USB0=0。
5. XSCT 命令行构建（F:\vivado2025\2025.2）：platform create 自动生成 zynq_fsbl 域；`platform generate` 完成 gcc 编译链接（末尾报 "default domain is empty" 元数据错误），产物 `fsbl.elf`（367,528 B，ARM ELF32，SHA-256 `11e7963b163bd58cebf9e9322e77399454c1fcebf6a8b7d25a7ea65735da8e3c`）；bootgen 打包 `BOOT_MIN.BIN`（91,856 B，SHA-256 `eb88aa570030fa9d98f5b962c954ded787f0ccb85330326d029730654e466667`）。全部归档 run03。
6. 卡上 BOOT.BIN 替换：原件备份为 run03 `BOOT_pynq_z2_orig.BIN`（SHA-256 `3fcdd4303567d75ac1e7be96c4a93816acb6c150f6facbf1f123d729a5bd5def`），复制 BOOT_MIN.BIN → G:\BOOT.BIN，sync 后回读哈希一致。
7. 用户上电测试（16G 卡，两台串口上位机先后测试）：串口均无输出。
8. JTAG 诊断（xsct，板载调试器，同 USB 线）：
   - diag1：`targets` 输出为空；对裸 JTAG 上下文 mrd 0xF8000DE0 返回 "Blocked address … Reserved address range"。
   - diag2：targets/mrd 无输出返回。
   - diag3：延迟重试后枚举出目标列表：`1 APU / 2 ARM Cortex-A9 MPCore #0 (Running) / 3 ARM Cortex-A9 MPCore #1 (Running) / 4 xc7z020`。
   - diag6（targets 2 选中核心 0，stop）：`PC=0xffffff28`；`BOOT_MODE(0xF8000DE0)=0x00000000`；`OCM 0x0 = 0x00000000`。
   - 手册《EES-331 User Guide》第 6 节摘录：拨码"往上拨表示该位数值为 0，即 ON=0"；SW8 表：JTAG=00000、QSPI=00010、SD=00110（位序对应开关 1~6）、SPI_FLASH=00010、"6=ON"为 JTAG EX；第 4 节：供电两种方式经选择插针切换，上电成功后 D18 长亮。
   - SW8 照片（用户两次提供）：首次照片六位全在 ON 侧；用户修正为 1、2、5=ON 侧，3、4、6=K1Q 侧后再次拍照确认。
   - 用户执行 POR 后 diag7/diag8：`jtag targets` 返回 `1 Xilinx TUL 1234-tulA (error DR shift through all ones)`，targets 数量 0；COM6 仍在系统中存在。
   - 用户报告：D18 为绿色 LED 且常亮（此报告时点在 SW8 修正之前）。

### 当前状态（客观）

- 最近一次 JTAG 扫描（diag8）：链路 "DR shift through all ones"，无目标；COM6 存在。
- 待用户确认：当前电源开关位置与 D18 亮灭状态。
- 待执行：供电确认后重跑 diag_jtag8 脚本，读取 BOOT_MODE；对照手册 SD 行 00110（对应寄存器值 0x06）。
- 修正前假设说明：本日早间"FSBL 死于 ps7_init DDR 训练"为推断，当时基线静默均发生在 BOOT_MODE=0x00000000 读数状态（diag6）；该状态对应手册 JTAG 行（00000）。原版镜像与自研 FSBL 尚未在 SD 模式（0x06）下完成实测。

## 结果

- 任务 1（计划修订）：完成。
- 任务 2（下载校验）：完成。
- 阶段 0 状态：部分完成（下载项 PASS；工具/环境/物料确认项待用户配合）。
