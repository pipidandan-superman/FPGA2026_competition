# 2026-09-10 Next Start Guide（v9，SD Builder v0.2 已交付）

## 最新：归档后从这里继续（v10）

归档已推送：`codex/full/pipidandan-superman`，内容提交 `ae1384a`；[草稿 PR #3](https://github.com/pipidandan-superman/FPGA2026_competition/pull/3) 等待另一成员审核，未合并 main。先检查同 run 的上传回执，再按下列硬件/报告待办继续；本次后续提交仅补充回执与交接。

1. 先读 [归档索引](../../4_metrics/logs/2026-09-10_session_archive_upload_run01/REPORT.md)、README 顶部与 HANDOFF；从个人分支 `codex/full/pipidandan-superman` 查看交付，远端核对结果见同 run 的 upload_result.json。
2. v0.2 使用 `8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.exe`。Git 不含基础 IMG，先按索引找到/复制本机 EES-331 基础镜像并核对 SHA-256，另备 Vitis 2025.2。本 run 参考 XSA 可用于输入检查，实际硬件变更需对应的新 XSA。
3. 下一硬件目标是新 XSA/新输出的冷启动 UART，再验收 Linux 外设、网络/Jupyter、PL/DMA 和业务；旧裸机 UDP 成果不能替代这些测试。
4. AIPC 报告填写人员、学校、联系方式，确认团队编号和机型后才可提交。当前 DOCX 成品和模板分别保留。
5. 不改冻结 2_fpga、不混用不同日期 BIT/ELF，不覆盖已通过 SD 基线，不直接推送 main。本机旧路径显示 XSA 的 SD0 拒绝结论只针对该文件，不据此判断远程最新硬件。
6. 原 E:/competition 仍可能有其他未提交工作；继续 Git 操作应先读本次审计并使用个人分支 worktree，不清理、重置或批量暂存原现场。

## 同日补充：AIPC 报告交付入口

- 新报告在 `E:/competition/1_docs/doc/AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx`，正文/图示及两页模板校验完成，原模板保留。
- 提交前补齐队长、学校、邮箱、电话、指导教师，确认编号4062是否真实及拟借机型。当前字段是明确待填，不把模板示例当作事实。
- 后续若补充信息，在原新报告中局部更新并重新渲染检查；不要覆盖模板。证据 `4_metrics/logs/2026-09-10_aipc_loan_report_run01/REPORT.md`。
- 以下SD Builder/板卡入口继续有效，报告编写没有修改任何软硬件设计。

## 当前第一入口

先读 [v0.2 使用说明](E:/competition/3_host/pynq/sd_boot_builder_v02/README.md)，打开 [v0.2 EXE](E:/competition/8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.exe)。旧 `8_tools/sd_start_tool/` 和旧源码仍为v0.1，请按版本区分。

1. 提供 Vivado 2025.2 含bitstream的XSA，先检查配置。DTB默认留空；已登记板载PS配置自动生成，具体未知外接连接再补充高级DTB。
2. 完整IMG只使用适配后的EES-331基础镜像 `4_metrics/logs/2026-09-10_ees331_img_package_run01/ees331_pynq_v3.0.1_ps_sd_20260910.img`，不能选原版Z2或新生成的IMG。当前主机已自动定位。
3. 选择PL模式及USB角色（仅USB0启用生效）。界面高级设置可滚动。新输出位于独立 `4_metrics/logs/YYYY-MM-DD_sd_builder_v02_<id>/output/`。
4. 当前22项测试、FSBL/BSP重建、整卡读回、EXE构建与位流载荷检查均通过，但v0.2生成包未板测。下一步取得实际新XSA的冷启动UART，再验收启用外设及PL/DMA/业务应用。
5. 显示工程现存 `2_fpga/0_diaplay_test/vitis/display_test_wrapper.xsa` 未启用SD0，因此不能直接输入生成SD启动包；本轮没有替用户改变冻结设计。
6. 不覆盖此前板级通过证据、不改冻结2_fpga、不把任意PL驱动或网络/Jupyter默认视为通过。保留v0.1/旧启动镜像作对照。完整证据见 [REPORT.md](E:/competition/4_metrics/logs/2026-09-10_sd_builder_v02_run01/REPORT.md)。

以下v8及更早内容为历史。

## 工具包入口（最新）

先读 `E:/competition/3_host/pynq/sd_boot_builder/README.md`。程序在 `E:/competition/4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/distribution/EES331SDBootBuilder.exe`。

1. 必须选择Vivado 2025.2导出的含bitstream的XSA；检查PS差异，按需补充匹配DTB。选择手动/PYNQ Linux后自动加载/FSBL加载模式，再导出ZIP或完整IMG。
2. 原版IMG和Vitis默认路径已配置。每次输出到新的 `4_metrics/logs/YYYY-MM-DD_sd_builder_<id>`。工具不写卡；生成包的result.json仅表示静态和文件校验通过。
3. 当前原型已通过10项输入/GUI测试、真实BOOT/FIT/ZIP/IMG生成、FSBL/BSP重建、PL载荷验证和EXE真实构建。新输出尚未上板；下次使用真实新XSA进行冷启动和PL/DMA/应用验收。
4. 不用测试版自动加载IMG覆盖此前已启动基线的证据。未知PS外设/驱动适配不能绕过DTB缺项门禁；需要更多单XSA自动化时逐项扩展板级profile并板测。
5. 冻结2_fpga保持只读；不把本次工具开发当作任意PS配置都自动兼容EES-331的证明。

以下v7及更早记录作为历史保留。

## 当前入口

先读 `E:/competition/4_metrics/logs/2026-09-10_ees331_img_package_run01/REPORT.md`。用户 UART 已证明 SD→FSBL→U-Boot→Linux Shell 成功，不再把“缺少启动日志”作为当前阻塞。

1. 需要新卡部署时使用同 run 的 `ees331_pynq_v3.0.1_ps_sd_20260910.img`（SHA256 203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a）；文件和分区全量校验通过，新 IMG 重新烧卡冷启动仍待实测。
2. 当前成功卡可以继续验收网络/Jupyter。日志有 U-Boot PHY读取失败、Linux随机MAC等未闭环项，不把登录成功等同外设全通过；先记录 `ip addr`、`ip link`、完整 dmesg 与连通性，再按证据定位。
3. PL变化按报告矩阵处理。优先独立 bit+hwh 同版本 Overlay，Linux驱动需要时加 dtbo/模块；PS启动配置变化才重新生成 XSA/FSBL/BOOT并同步实际被使用的 DTB。不要每改 RTL 就重烧整卡。
4. 当前 BOOT 不含 PL bitstream，boot.py 不自动加载 Overlay；新硬件应用在独立目录开发验证。冻结 `2_fpga/` 不改，不加载 PYNQ-Z2 的默认 base.bit。
5. 保留本次成功启动文件和 IMG；先形成可重复的 Overlay 小测试再考虑自动启动与新版整卡发布。运行环境快照应在板子正常关机后从实际卡另行读取。

下面 v6 及更早内容为历史。

## 最新入口：冷启动验收

先读 `E:/competition/4_metrics/logs/2026-09-10_sd_boot_fix_run01/REPORT.md`。G 盘已完成 BOOT.BIN/image.ub/boot.py 修正并新增 system.dtb，读回哈希和写后 FAT 检查通过；原文件在同 run 的 sd_backup。本轮文件工作已完成，不要再按下文旧记录重做备份/烧录/修正。

1. 安全移除 G 盘插回板卡；先打开 COM6、115200-8-N-1、无流控并开始保存 UART 文本，再冷启动。沿用用户已确认的 SD 拨码/供电，不重复以此请求确认。
2. 观察 FSBL 横幅与 SD 模式记录 → U-Boot → Linux 日志/登录；每一阶段单独验收，出现 FSBL 不等于完整 PYNQ PASS。
3. 若仍全静默：保持本次文件，保存本轮现象后用 JTAG 读当次执行位置/BootROM 状态；FSBL 横幅在 PS 初始化后，不能仅凭无横幅定案 DDR。若 FSBL 已有输出，按第一个明确加载/交接错误分段定位。
4. Linux 起来后核对 `/proc/device-tree/model`、`cat /proc/cmdline`、`free -h`、`dmesg` 中 UART/MMC/GEM/PHY，再查 IP 与 Jupyter。Linux 可用 RAM 应考虑 CMA/内核保留，不能要求 free 精确显示 1GiB。
5. 不运行原版 PYNQ-Z2 base Overlay。boot.py 已取消其自动加载；当前为最小 PS 启动适配，USB/I2C/QSPI 随 XSA 禁用，自定义 Overlay/完整外设移植待分阶段验收。
6. 冻结 `2_fpga/` 不改。不要用 FSBL-only 诊断镜像替换默认完整 BOOT，除非新定位结果要求单变量试验。回退脚本 `deploy_sd.ps1 -Mode Rollback` 仅恢复修复前故障现场，不是恢复已验证可启动系统。

当前阻塞仅为缺少新卡板上冷启动原始日志；无本轮硬件 PASS。下面 v5/v4/v3 全部为历史。

## 全面检查后的当前入口

先读 `E:/competition/4_metrics/logs/2026-09-10_sd_card_full_audit_run01/REPORT.md`。整卡 15.63GB 读取无错误，根分区与原版逐字节相同，不必在文件未变时重复扫描或重新下载镜像。

1. 首先处理已证实的 BOOT 缺 bootloader 标记和 FSBL DEBUG 关闭，隔离构建并验证头字段/字符串后再做首级冷启动验收。
2. 完整 PYNQ 需要适配的 U-Boot 和 DTB；当前 FIT 的 UART0/50MHz/512MiB 配置未适配 EES-331。优先修改实际被 boot.scr 使用的 image.ub 内 DTB，不能只放根目录 system.dtb 就假定生效。
3. SD0 MIO40..45/CD MIO0/Bank1 1.8V 与手册相符；不因当前失败盲目更改。最小工程 DDR 参数与冻结基线重叠项一致，仍需实际 FSBL 初始化验证。
4. 首次进入 Linux 前规划处理 boot.py 自动加载原版 Z2 base.bit 的行为，再分阶段验收网络/Jupyter/EES-331 Overlay。卡上尚未执行任何本轮修复。
5. 限制：全卡只读无错不是写入保持/容量压力测试；根分区解析与原版一致不是 e2fsck；无本轮上板 PASS。

以下 v4/v3 条目为历史，优先执行以上入口。

## 最新入口（优先于后面的 v3 历史内容）

G 盘实读更新：`4_metrics/logs/2026-09-10_sd_card_g_audit_run01/REPORT.md` 已确认卡上 BOOT.BIN 与错误 BOOT_MIN.BIN 逐字节相同，长度/偏移字段仍为 0。卡未修改；下一步仍是修复启动镜像，不必重复验证是否为同一旧文件（除非用户后续替换）。

1. 先读 `E:/competition/4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/DIAGNOSIS.md`。用户已确认 SD 拨码和供电，不再重复要求确认。
2. run03 BIF 漏 `[bootloader]`，BOOT_MIN.BIN 的 FSBL 源偏移/长度为零；FSBL 同时未开启 DEBUG 且实际 ELF 无横幅字符串。当前先修复这两个已证实缺陷，不能继续用原 BOOT_MIN.BIN 静默作为板卡失败判据。
3. 修复建议：在新证据目录依次做 BIF 单变量修正与头字段校验，再单独启用 DEBUG 重编并验证字符串；本轮仅分析，尚未执行。不要改动冻结工程或覆盖旧证据。
4. 串口验收要在 POR 前打开 COM6 并留完整日志；出现横幅只证明执行到 FSBL 打印点，不等于 PYNQ。完整 PYNQ 还需要适配的 U-Boot 和后续系统。
5. 修复后若仍静默：先保留 SD 冷启动现场，再读本轮寄存器/设阶段断点区分 ROM、FSBL 入口、ps7_init、UART；JTAG 全 1 时先解决枚举，不能直接断言没上电。

以下 v3 状态及步骤作为历史留存，不再作为当前执行入口；其中“等待供电确认”和对原静默版 ELF 期待横幅的做法已被上文替代。

## 当前状态（客观）

- 用户已将 SW8 修正为手册 SD 行位型（1、2、5=ON 侧，3、4、6=K1Q 侧）并执行 POR。
- 最近一次 JTAG 扫描（run03/diag_jtag8）：`1 Xilinx TUL 1234-tulA (error DR shift through all ones)`，targets 数量 0；COM6 仍在系统枚举中。
- 最后一次成功寄存器读数（diag6，SW8 修正前）：`PC=0xffffff28`、`BOOT_MODE(0xF8000DE0)=0x00000000`、`OCM 0x0=0x00000000`。
- 待用户确认：电源开关当前位置、D18 当前亮灭。

## 下会话第一动作

1. 确认用户侧供电状态（D18、电源开关）。
2. 重跑 `4_metrics/logs/2026-09-10_pynq_fsbl_rebuild_run03/diag_jtag8.tcl`（xsct 路径 `F:\vivado2025\2025.2\Vitis\bin\xsct.bat`）。
3. 若 targets 枚举成功：读 `0xF8000DE0`。手册 SD 行=00110；若读数与 0x00000006 不一致，对照 SW8 特写照片重新核对拨杆。
4. BOOT_MODE 确认为 SD 位型后：COM6 打开（115200-8-N-1），再次 POR，观察串口输出（卡上当前为 BOOT_MIN.BIN，仅含自研 FSBL）。

## 禁止立即执行

- 不得改动 `2_fpga/` 既有工程（`3_pynq_test` 为用户自建，改动前同样需用户确认）。
- 覆盖卡上文件前必须先备份（原版 BOOT.BIN 已在 run03，勿覆盖丢失）。
- 串口/启动结论必须伴随寄存器读数或串口原始输出，不写无证据结论。

## 关键判据

- SD 模式生效：BOOT_MODE 读数与手册 SD 行 00110 一致（0x00000006）。
- FSBL 横幅：串口出现 `Xilinx First Stage Boot Loader`（随后报无法加载后续分区属预期，BOOT_MIN.BIN 仅含 FSBL）。
- 手册依据：`4_metrics/logs/2026-09-08_eth_zynq_psw_check_mineru_run01/EES-331 User Guide/auto/` 第 4 节（供电/D18）、第 6 节（SW8 表）、第 12 节（UART1 经 J3）。
