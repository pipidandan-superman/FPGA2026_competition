# 2026-09-10 Execution Plan

## 最新：归档和上传执行顺序

执行结果：精选归档、文档合并、校验、提交、个人分支推送和草稿 PR 创建全部完成。内容提交 `ae1384a`；PR `https://github.com/pipidandan-superman/FPGA2026_competition/pull/3`。仅追加回执，不重复构建/板测。

1. 已核对原工作区 main 上的未提交改动，保留现场；个人分支使用独立 worktree，快进至远程 main@c60291a。
2. 明确精选清单，逐项记录大小、SHA-256、来源与用途；从远程 README/HANDOFF 合并本日新增记录，保持旧版应用与板测事实。
3. 仅复制清单文件，核对已有路径差异；用精确文件列表暂存。保持证据/资产字节，排除多 GB IMG、重复 ZIP、缓存和冻结 2_fpga。
4. 校验两版资产/发行物、暂存范围、敏感信息、原工作区冻结差异及项目技能路径。检查结果写入 `4_metrics/logs/2026-09-10_session_archive_upload_run01/`。
5. 提交后只推送 `codex/full/pipidandan-superman` 并核对远端 HEAD；尝试创建 main 草稿 PR，保留回执。main 合入另需成员审核，不能强推。
6. 如网络或 PR 认证失败，保留提交和原始错误，明确已推送与未完成事项；不为上传重建、写卡或重置现场。

## AMD AIPC 借用报告（已执行）

1. 定位实际 `1_docs/doc/` 模板，核对工程README、设计方案、当前日志和软件验证；模板样例不作为本项目已实现事实。
2. 原DOCX的MinerU直接解析缺输出，保存FAIL记录；披露后转PDF，再用MinerU pipeline解析，PASS且short_text质量review，经两页人工核对。
3. 按模板复制包，仅改正文与两张示例图；保持其他部件字节一致。以当前工程改写AI PC用途、FPGA分工、YOLOv8n拟部署、UDP数据流、反馈/异常处理与验收计划。
4. 编号/机型及人员信息已异步询问；未获答复字段显式待确认或待补充。完成2页渲染、参考差异检查、包保留审计及日志更新。

## v0.2 新版生成（本轮已执行）

1. 保存 v0.1 源/资产/EXE/ZIP 哈希，复制到独立 `3_host/pynq/sd_boot_builder_v02/` 修改，冻结 `2_fpga/` 只读。
2. 核对复用的 EES-331 手册 MinerU 完整结果和输入哈希；用 XSA 控制器参数+固定板级模板生成 DT，而非将新版 SDT 原样替代 Linux DT。
3. 切换 EES-331 基础 IMG 身份/全量 SHA 校验；高级设置只负责路径和完整 DTB 覆盖；新增具体缺项提示，保留启动引脚约束。
4. 真实显示 XSA 的辅助 HWH 导致旧式单HWH误拒绝，修正为唯一PS7系统HWH；其SD0禁用仍明确拒绝，不改原XSA。
5. 22项回归、原生DTC、真实FSBL/BSP重建+整卡、EXE手动/FSBL模式验证；界面实际检查发现高级页截断后增加滚动并重新冻结/自检。
6. 生成独立 `8_tools/sd_start_tool_v0.2/` 和发布ZIP，验证旧版未变、压缩包与交付副本一致。新硬件包需板测；回退使用保留旧版/已启动基线，不以文件PASS代替板级验收。

## XSA SD Builder 应用开发（已执行）

1. 用户补充“强制XSA含比特流”，固化到预检规则；本地解析XSA内bit/HWH/ps7_init/器件信息并比较PS参数。源代码在 `3_host/pynq/sd_boot_builder`，原始证据run为 `4_metrics/logs/2026-09-10_sd_builder_toolkit_run01`。
2. 复用此前已校验的基线资产，建立manifest；用隔离XSCT工作区明确proc/os重新生成平台与BSP，解决旧default-domain-empty路径，FSBL以DEBUG重编。
3. 实现GUI、BOOT/FIT/ZIP、FAT/IMG校验，所有构建写独立4_metrics/logs日期run，验证完成才发布output目录。任何模式均不直接写卡。
4. 10项输入/GUI测试、真实手动/FSBL/Linux三种模式构建、强制FSBL重建及完整IMG读回通过；PyInstaller生成EXE，EXE自身GUI/依赖自检和真实XSA构建通过。
5. 交付EXE、源码、README、报告和版本哈希。生成新硬件启动包后仍须板测；复杂PS外设变化要求匹配DTB，缺驱动时不承诺只靠XSA完成Linux移植。

## 完整 IMG 打包与 PL 更新说明（已执行）

1. 核验用户 UART 中 FSBL SD模式/交接、U-Boot、FIT SHA1、EES-331 Linux 和 xilinx@pynq:~$；保存原始副本与哈希到 `4_metrics/logs/2026-09-10_ees331_img_package_run01/`。
2. 原 IMG 只读，抽出 FAT 分区至隔离副本；pyfatfs 写入四个修正文件，保留两文件。前两次副本因库截断路径/大小写查找问题失败，证据保留；修正为匹配原大写短名、删除后重新创建，由独立解析器确认六文件完全相等才继续。
3. `package_image.py` 生成完整 IMG，流式校验原版哈希、输出全文件读回哈希、启动分区外每个分块均相同，两个 FAT 副本/文件链/内容均通过。
4. 从官方 PYNQ v3.0 文档及本地 v3.0.1 overlay.py 核实 bit+hwh、dtbo 和运行时时钟行为；REPORT.md 提供按 PL/PS/驱动变化分类的文件更新表。
5. 交付全 IMG 和 SHA256；本轮无烧卡。新容器复烧待验，已验证的是包含在其中的启动文件版本及当前 UART 到 Shell。失败副本不可交付，原 IMG/修复备份/冻结工程保持不变。

## 同日追加：用户授权的完整文件修正（已执行）

1. `4_metrics/logs/2026-09-10_sd_boot_fix_run01/prepare.ps1`：校验 G 卡身份/故障 BOOT 哈希，备份原五个文件，隔离复制 FSBL/BSP。未改冻结工程。
2. `build_fsbl.ps1`：使用 Vitis 2025.2 ARM GCC，对所有 C/汇编以 FSBL_DEBUG_INFO 重编。保留 XSA 生成 ps7_init；ELF 与 BOOT 中打印字符串核验通过。
3. 复用原版 U-Boot 载荷；通过实际 ARM 反汇编确认外部控制 DTB 地址 0x00100000。封装为入口/LOAD=0x04000000 的 EXEC ELF，没有冒称源码重编。
4. `ees331.dts`：UART1、33.333333MHz、1GiB、SD0/PHY0、最小 XSA 设备启用状态与旧 PL 节点适配。DTC 编译后将同一 DTB 放入 BOOT 和 FIT；保留内核，更新 FIT 哈希，保留 boot.scr。
5. `validate_candidate.py`：240 项离线检查通过。`boot.py` 换为仅打印信息的钩子；FSBL-only 诊断镜像仅保存于 candidate。
6. `powershell -NoProfile -ExecutionPolicy Bypass -File E:/competition/4_metrics/logs/2026-09-10_sd_boot_fix_run01/deploy_sd.ps1 -Mode Deploy`：原文件未变化、卡身份和卷刷新预检通过；暂存/刷盘后依次提交 image.ub、boot.py、system.dtb、BOOT.BIN；读回全部哈希一致，清理临时副本后再次刷新卷。
7. `chkdsk G:` 写后只读检查无问题。原始控制台、哈希、报告在上述 run，结果 SD_DEPLOY_READBACK_PASS；随后同步本日四件套与 HANDOFF。
8. 回退：同脚本 `-Mode Rollback` 仅恢复修复前故障现场，需已部署文件仍匹配清单；PC 备份一直保留。本轮未回退。断电中断/脚本失败时保持卡在 PC，先检查保留的临时副本和备份，不继续板测。

以下为本日历史执行记录。

## 同日追加：SD 全面只读检查（已完成）

1. 以 G:→磁盘 1 的分区、容量为前置校验，`scan_card.py` 只读扫描 PhysicalDrive1 全部 15,634,268,160 B，逐段对比本地 IMG；耗时 870.21 秒、0 读取错误。
2. `chkdsk G:` 只读检查 FAT；`inspect_contents.py` 从原版 IMG 解析 FAT 文件并与 G 根目录对比、验证 boot.scr CRC/image.ub FIT hash、读取设备树和 XSA 参数。
3. `verify_archive.py` 验证 ZIP 哈希与完整解压流 CRC/SHA；确认本地 IMG 与 ZIP 内镜像相同。
4. 原版/当前 BOOT.BIN 均通过 Bootgen 2025.2 `-arch zynq -read <BIN>` 导出全部头表，确认普通 FSBL ELF 的 2 个分区不能混称两个启动程序。
5. `rootfs_extended.py` 使用隔离的 dissect.extfs 遍历与卡上逐字节相同的根分区目录；`supplement.py` 实读卡上 FAT/超级块，核验 MinerU 复用并提取启动脚本。无 WSL/e2fsck，明确只读解析和对比边界。
6. 证据统一位于 `E:/competition/4_metrics/logs/2026-09-10_sd_card_full_audit_run01/`，报告列出下一步修复和板测判据。本轮未修复、重编、写卡或运行原版 Overlay。

## 任务 1：计划文档修订（v1.0 → v1.1）

1. 核实工具链事实：`display_test_zynq7020_school.xpr` 头部 "Product Version: Vivado v2025.2"；XSA `2_fpga/0_diaplay_test/vitis/display_test_plat/export/display_test_plat/hw/display_test_wrapper.xsa`（2026-09-08 导出）内部元数据 `Version="2025.2"`。`Zynq_PS7_Config_Report.md` 所称 2020.2 系旧位置 `D:/VitA/` 过期工件。
2. 修订 `1_docs/doc/EES-331_PYNQ从零部署计划_2026-09-09.md` 共 9 处：版本头与修订记录、证据表增补工具链事实行、PYNQ 版本证据行（v3.1.1 已上架）、阶段 0 工具清单（改用现装 2025.2）、下载清单（补 v3.0.1 直链与 v3.1.1 备选）、阶段 1 FSBL 工具（2025.2）、DDR 依据行（以现工程 ps7_init.tcl 复核）、阶段 5 前置（2022.2 仅 sdbuild 需另装）、风险表 ps7_init 差异降级（极低/低）。

## 任务 2：阶段 0 下载与校验

1. 建目录：`3_host/pynq/download`（用户指定）与 `4_metrics/logs/2026-09-10_pynq_stage0_download_run01`。
2. `curl -sIL` HEAD 确认镜像真实地址与大小：`xilinx.com/bin/public/openDownload` 301 → `download.amd.com/opendownload/xlnx/pynq_z2_v3.0.1.zip`，Content-Length 1,811,523,457。
3. 后台并行下载：
   - `curl -L -C - --retry 5` 镜像 zip → `3_host/pynq/download/pynq_z2_v3.0.1.zip`；
   - `curl -L -C - --retry 3` 源码包 → `3_host/pynq/download/PYNQ-v3.0.1.tar.gz`（codeload.github.com，tag v3.0.1 tarball）。
4. 完整性：字节数比对 Content-Length、`unzip -l`、`tar -tzf`、`sha256sum`（结果见 run 目录 manifest）。
5. 写 run 目录 `00_download_manifest.md`，建本日四件套。

## 任务 2 工具/模块与风险（原记录留存）

- 工具：Git Bash curl（断点续传 `-C -`）、sha256sum、unzip、tar；后台任务避免长下载阻塞会话。
- 风险与回退：镜像下载中断 → curl `-C -` 续传；GitHub 不可达 → 源码包可延后获取（u-boot 首选从官方镜像 BOOT 分区提取），本次一次成功；磁盘占用 zip 1.69 GiB + 解压后 img 7.32 GiB（需约 10 GB）；8GB 卡容量贴线（实测 7,948,206,080 B ≥ 镜像 7,858,807,808 B，可烧）。

## 任务 3（同日追加）：阶段 2 基线与 FSBL 重制实际执行记录

1. 烧卡：balenaEtcher 流程由用户以 Win32DiskImager 完成（16G 卡，映像 `pynq_z2_v3.0.1.img`）；换卡前 8G 卡旧启动文件（BOOT.BIN/image.ub/system.dtb，2021-12-02）备份至 run01 `sdcard_found_image_backup/`。
2. 上板测试：SW8 拨杆调整（口诀 1、2、5=ON；3、4、6=K1Q，依据手册第 6 节表）、COM6 115200-8-N-1、POR 复测多次，串口无输出。
3. 用户自建 `2_fpga/3_pynq_test`（Vivado 2025.2），导出 `vitis/pynq_test_wrapper.xsa`；hwh 参数核对与冻结 XSA diff（重叠配置仅 FCLK0 不同）。
4. FSBL 命令行构建：
   - 工具定位：`F:\vivado2025\2025.2`（经注册表 InstallLocation 与 Vivado 进程路径确认）。
   - `xsct.bat build_fsbl.tcl`（setws/platform create/app create）→ app create 报平台域名不匹配；改 `gen_fsbl.tcl`（platform read + platform generate）→ gcc 编译链接完成，产出 `fsbl.elf`；末尾 "default domain is empty" 元数据错误不影响产物。
   - `bootgen.bat -image fsbl_only.bif -arch zynq -o BOOT_MIN.BIN -w on`。
5. 卡上替换：备份 `G:\BOOT.BIN` → run03；复制 `BOOT_MIN.BIN` → `G:\BOOT.BIN`；`sync` + 回读哈希一致；mountvol/Shell 弹出未生效，已告知用户数据已 sync 可直接拔卡。
6. 上电复测：两台串口上位机先后打开 COM6，无输出。
7. JTAG 诊断：diag1~diag8 脚本迭代（`connect`/`jtag targets`/`targets`/`stop`/`rrd pc`/`mrd -force`），关键读数与输出见 03_validation_summary 客观时间线；手册第 4、6 节原文摘录比对 SW8 与供电。

## 涉及工具/模块（追加）

- XSCT 经典流（2025.2，存在弃用警告）、bootgen、`Get-CimInstance Win32_PnPEntity`（COM 枚举）、`Get-Disk/Get-Partition`（磁盘识别）、注册表 Uninstall 键（工具路径定位）。

## 风险与回退（追加）

- FSBL 产物风险：`platform generate` 元数据报错未复现影响，产物经 `file`（ELF32 ARM）与大小校验；后续板级横幅为最终判据。
- JTAG 扫描时序：连接后需 ≥2s 延迟再枚举（diag3 证实）；拨码/POR 期间扫描会得到空链或全 1。
- 未决：BOOT_MODE 当前读数未取得（最后一次扫描链路全 1，待供电状态确认后重测）。

## 同日追加：SD 静默静态审计（已执行，未重新上板）

后续已执行 G 盘只读现场检查：`powershell -ExecutionPolicy Bypass -File E:/competition/4_metrics/logs/2026-09-10_sd_card_g_audit_run01/check_sd.ps1`。Get-Volume/Get-Partition/Get-Disk 枚举；读取全部根目录文件计算哈希；对 BOOT.BIN 做逐字节与启动头核对。未写 G 盘，完整输出见该 run 的 `console.txt`。

1. 接受用户当前 SW8=SD、上电成功的确认，读取 run03 原始 BIF、构建日志、FSBL 源码和归档 ELF/BIN。
2. 对实际 BIN 读取小端启动头，对 ELF 运行 GNU strings/readelf，并核对当前 ELF 与归档 ELF 的 SHA-256。
3. 对照 Xilinx 官方 Bootgen 源码，确认缺失 `[bootloader]` 对应 FSBL 加载头字段清零；核实 FSBL 宏关闭与实际横幅字符串缺失。
4. 完整复现脚本与输出：`E:/competition/4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/audit.ps1`、`audit_console.txt`；判定见同目录 `DIAGNOSIS.md`。
5. 后续建议依次验证 BIF 属性、调试宏、冷启动串口。若仍静默，保留现场后再做阶段断点；本轮未执行重编、写卡或 JTAG。不得把静态镜像缺陷确认写成板级恢复 PASS。
