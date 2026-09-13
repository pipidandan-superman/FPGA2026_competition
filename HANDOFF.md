# EES-331 项目交接

## 2026-09-12 BLE Console v1.1 与手动复现

推荐未配对GATT接入已集成上位机：三次无缓存读取/保持门控、自动通知、断连停止发送。
31项离线/Tk测试、新版后端60.5秒三轮双向及真实EXE按钮双向字节核对通过；
用户另行确认双向通信成功。TX只是发送记录，HEX旁的文本替代字符不是数据损坏，
端到端结果以另一端实际收到的HEX为准。

[操作与验证状态](1_docs/doc/ees331_ble_validation_status_2026-09-12.md) ·
[上位机源码及说明](3_host/ble_console/README.md) ·
[方案v1.2](1_docs/doc/ees331_ble_axi_bram_development_plan_2026-09-12.md) ·
[本次发布范围](4_metrics/logs/2026-09-12_ble_v11_publish_run01/REPORT.md)。
本地新EXE在8_tools/EES331_BLE_Console_v1.1，旧包保留；本次上传源码、说明、精选证据，
不上传运行依赖树或凭据。冻结FPGA不改；长期/重连/机械臂/AXI-BRAM仍待分阶段执行。

## 2026-09-12 最新蓝牙里程碑

PC与板载MLT-BT05已通过短时双向通信：未配对GATT保持61.703秒，11轮、每方向166字节全部一致，结束主动断开。COM4有线AT正常；不等于长期压力、Windows PIN配对稳定、机械臂互通或正式AXI/BRAM控制通过。复现时直接通过BLE上位机连接并订阅FFE1，COM4=9600/8N1用于另一端收发核对，不需ILA。

入口：[验证状态与复现](1_docs/doc/ees331_ble_validation_status_2026-09-12.md) · [完整开发方案v1.1](1_docs/doc/ees331_ble_axi_bram_development_plan_2026-09-12.md)。下方历史阶段状态以本段及最新验证报告为准；当前电平桥不能替代正式字节级UART/FIFO。


## 2026-09-12 当前最高优先级：板载蓝牙验证

执行入口：[完整开发方案](1_docs/doc/ees331_ble_axi_bram_development_plan_2026-09-12.md)。用户确认自定义AXI-Lite只做控制/状态、BRAM使用独立控制器、蓝牙使用PL板载模块。首先G0核实基线和供电极性，建立独立PL UART诊断副本，B0查询MLT-BT05，B1以Windows主机作BLE Central验证双向收发。PC通路PASS不代表MLT主机模式或BT24直连PASS。之后按C0/C1实现CSR、4KiB TDP BRAM、LED，再接机械臂。方案中给出地址偏移、所有权/CRC/seq/结果确认、心跳和回退；物理基地址待审计。此轮仅编写和发布方案，2_fpga冻结基线保持只读。

## 2026-09-10 关键证据归档与个人分支交付

- 已完成：内容提交 `ae1384aea6f3390fb17ef78562eabf83f4677039` 已推送且远端 HEAD 一致；[草稿 PR #3](https://github.com/pipidandan-superman/FPGA2026_competition/pull/3) 目标 main，尚未合并。归档文件哈希、18 项启动资产、300 项暂存对象、两版 EXE 自检与项目路径审计通过。后续回执提交只补充文档和 Git 结果。
- 归档入口：[REPORT.md](4_metrics/logs/2026-09-10_session_archive_upload_run01/REPORT.md)，逐文件来源、大小和 SHA-256 见同目录 `selected_manifest.json`；Git 审计、校验与推送回执也保存在该目录。
- 目标分支 `codex/full/pipidandan-superman`，以远程 `main@c60291a` 为基线在独立 worktree 整理；保留已有 UDP/颜色修复记录。本机原工作区的其他未提交改动不纳入本次上传。
- 已选择 SD 故障定位/修复/原始 UART、整卡读回、SD Builder v0.1/v0.2 源码与 EXE、AIPC 模板/报告/解析与排版证据。大 IMG、重复 ZIP、工具链缓存保留本地。参考 XSA 仅从冻结目录只读复制到归档目录。
- 边界：旧基线 SD/Linux Shell 已通过；v0.2 新生成包未板测；9 月 8 日裸机 UDP/PC 色彩修复已通过，Linux 网络/Jupyter/PL 应用另行验收。AIPC 人员与机型等字段待补齐。
- 下次先读 `7_logs/2026-09-10/04_next_start_guide.md` 顶部；从个人分支取回交付文件，按归档索引取得基础 IMG。合入 main 仍需 PR 和另一成员审核，不以分支推送代替硬件验收。

## 2026-09-10 AMD AIPC 借用报告已编写

- 按用户指定模板完成 `1_docs/doc/AMD AIPC 借用报告 - 锐眼智行具身智能分拣.docx`，2页，含当前EES-331架构、AI PC借用用途、计划和两张新框图。模板原件与非编辑DOCX包部件保留。
- 通过MinerU的DOCX→PDF回退解析（短文本review已人工核对）、参考渲染、两页最终视觉检查及包/节/样式审计。原始证据 `4_metrics/logs/2026-09-10_aipc_loan_report_run01/REPORT.md`。
- 人员/学校/联系信息待补充，团队编号与机型待确认，37032G暂拟申请。未发送或提交。当前SD Builder v0.2与冻结硬件状态均不变。

## 2026-09-10 SD Builder v0.2 已交付（当前最新）

- 用户要求保留旧版并生成新版；v0.1源/资产/EXE/ZIP的19项哈希无变化，原 `8_tools/sd_start_tool/` 保留。新版入口 `8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.exe`，同目录有完整ZIP。
- 新版源码 `3_host/pynq/sd_boot_builder_v02/`。删除原版PYNQ-Z2输入入口，固定已适配EES-331基础IMG；默认XSA+板级模板生成PS设备树，完整DTB覆盖置于高级设置。辅助HWH自动识别，USB角色可选，三种PL模式说明、页面滚动与缺项提示完成。
- 22项测试、真实FSBL/BSP重建+整卡读回、EXE自检/手动/FSBL模式构建、位流载荷验证、发布ZIP/旧版保留核对PASS。最终测试IMG在 `2026-09-10_sd_builder_v02_175423_0bb6c6/output/`。
- 新输出尚未上板；本轮未写SD或改冻结工程。本机旧路径的实际显示XSA未启用SD0而被正确拒绝；高级DTB不能绕过启动引脚约束，未知外部设备/PL内核驱动仍需适配。
- 报告 `4_metrics/logs/2026-09-10_sd_builder_v02_run01/REPORT.md`；下一会话从 `7_logs/2026-09-10/04_next_start_guide.md` v9继续。下方标注“最新”的段落均为当时历史状态。

## 2026-09-10 EES-331 SD Builder GUI 0.1 已交付（历史，已由 v0.2 替代）

- 用户要求应用输入硬件文件导出SD启动包，并明确XSA必须含bitstream。已实现强制XSA的Windows GUI/EXE，支持PS差异检查、必要时新FSBL/BSP、手动/Linux后自动加载/FSBL三种模式、BOOT/FIT/ZIP和完整IMG校验输出。
- 程序：`4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/distribution/EES331SDBootBuilder.exe`；源码与说明：`3_host/pynq/sd_boot_builder/`；验证报告：toolkit_run01/REPORT.md。
- 10项输入/GUI测试通过，真实完整IMG/FSBL重建/FSBL位流载荷校验通过，EXE自检与真实XSA构建通过。新硬件包未板测，本轮未写SD或改冻结工程。
- 第一版限当前EES-331+Vivado/Vitis2025.2+PYNQ3.0.1；影响PS外设的未知变化需要匹配DTB，不自动猜测外部器件和驱动。默认手动加载PL，界面可切换自动加载。
- 下一入口：7_logs/2026-09-10/04_next_start_guide.md v8。使用实际新XSA完成冷启动/PL/DMA/应用验收，再扩展板级profile。

## 2026-09-10 SD/Linux Shell 启动已证实，完整 IMG 可交付（启动基线）

- 用户 `2026-09-10_pynq_v301_baseline_boot_run02/uart_pynq_log.txt` 证实 FSBL→U-Boot→EES-331 Linux→`xilinx@pynq:~$`，阶段结果 SD_BOOT_TO_LINUX_SHELL_PASS。
- EES-331 最小系统基线已归档为 `9_pynq/sd/01_base_ees331/ees331_pynq_v3.0.1_ps_sd_20260910.img`，7,858,807,808 B，SHA256 `203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a`。
- FULL_IMG_PACKAGE_READBACK_PASS：六个启动文件与已部署版本一致，启动分区外所有字节保持原版。新的完整 IMG 尚未复烧上板；不含首次启动后的运行状态。
- 网络/Jupyter/应用 Overlay 待验收，UART 中 U-Boot PHY/default-env、Linux随机MAC和部分 FSBL调试格式问题未因打包而修复。当前已通过的是 SD/Linux Shell 启动。
- PL开发通常更新同版本 `.bit`+同名`.hwh`和应用，需要Linux内核驱动时再处理`.dtbo`/模块；PS启动配置变化需新XSA/FSBL/BOOT及实际使用DTB。当前BOOT不含PL位流；冻结工程不改。
- 完整报告与更新矩阵：`4_metrics/logs/2026-09-10_ees331_img_package_run01/REPORT.md`；下一入口为 `7_logs/2026-09-10/04_next_start_guide.md` v7。下方 NOT_TESTED 为当时历史状态。

## 2026-09-10 SD 修正版已部署（历史里程碑，16:09:58 +08:00）

- 用户“根据查验的问题完整修正”已执行：隔离重编带打印 FSBL，正确 bootloader 头+U-Boot+控制 DTB，FIT 内同步适配 UART1/33.333333MHz/1GiB/PHY0，取消 Z2 base.bit 自动加载。最小 XSA 未启用的 USB/I2C/QSPI 在 DT 中禁用。
- G 盘已替换 BOOT.BIN/image.ub/boot.py、新增 system.dtb，boot.scr/REVISION 保留；全部文件读回哈希一致、卷刷新成功、写后 FAT 只读检查无问题。PC 备份完整，冻结工程/根分区未写。
- `SD_BOOT_CANDIDATE_STATIC_PASS`（240 项）+ `SD_DEPLOY_READBACK_PASS`；`hardware_status=NOT_TESTED`。新 BOOT SHA256 `3ea3eae30dba8646ddb597abf098594a99ed6c0250576bed12a9eca91c3902a0`。
- U-Boot 复用官方镜像中的原始程序载荷，通过实际二进制确认其读取 0x00100000 外部 DTB，未冒称源码重编；内核保留，BOOT/FIT 中的设备树字节一致。
- 当前第一动作：安全移除卡并插回板卡，COM6 115200-8-N-1 无流控先开日志，再冷启动记录 FSBL→U-Boot→Linux。用户已经确认 SD 拨码与供电。网络/Jupyter/自定义 Overlay 待实际板测，不提前标记完整 PYNQ PASS。
- 证据和回退说明：`4_metrics/logs/2026-09-10_sd_boot_fix_run01/REPORT.md`、`candidate_validation.json`、`deploy_result.json`；当前交接 `7_logs/2026-09-10/04_next_start_guide.md` v6。

以下为此前修复前审计和历史板测记录，旧“未写卡/等待修复”不代表当前状态。

## 2026-09-10 G 盘全面检查完成（历史）

- 全卡 15,634,268,160 B 只读读取完成，0 错误；MBR/7.72GB Linux 分区与原版镜像相同，除 BOOT.BIN 外的根目录启动文件也相同；ZIP→IMG 完整性验证通过。没有发现烧录载荷损坏证据。
- 当前 BOOT.BIN 无有效 FSBL 加载头、无 DEBUG 打印且缺 U-Boot；image.ub 内 DTB 另有 UART0/50MHz/512MiB 的 Z2 假设，与 EES-331 UART1/33.333333MHz/1GiB 不符。只改 BIF 不足以启动完整 PYNQ。
- boot.scr 优先使用 FIT 内 DTB；原版 BOOT 内 DTB 与 FIT 内 DTB 相同。只放根目录 system.dtb 不能保证修复生效。
- SD0/CD MIO0 与手册一致；Linux/PYNQ/Jupyter 文件存在，boot.py 会自动加载原版 Z2 base.bit，需要后续适配。整卡无读取错误不是写入型介质验收，未运行 e2fsck 或板测。
- 未写卡、重编或修改冻结工程。下一入口：`4_metrics/logs/2026-09-10_sd_card_full_audit_run01/REPORT.md`、`7_logs/2026-09-10/04_next_start_guide.md` v5。

## 2026-09-10 SD 启动静默：镜像缺陷已定位，板级恢复待验

- 同日 15:30 直接检查 G 盘确认：实际 BOOT.BIN（91,856 B）与 run03 BOOT_MIN.BIN 逐字节一致，FSBL 源偏移/长度仍为零。未写卡。现场证据 `4_metrics/logs/2026-09-10_sd_card_g_audit_run01/REPORT.md`。

- 用户当前确认 SW8 为 SD 启动且上电成功。只读审计发现 run03 `fsbl_only.bif` 缺 `[bootloader]`，实际 BOOT_MIN.BIN 的 FSBL 源偏移、长度、总长度均为 0。
- 同一 FSBL 没有启用 DEBUG，ELF 中不存在预期横幅和错误字符串；旧“最小镜像上电应有横幅”的验收无效。
- 先依次修正 BIF、验证启动头，再启用 DEBUG 重编并确认实际字符串；之后做 SD 冷启动 UART/阶段验证。只有 FSBL 的镜像不能启动完整 PYNQ。
- 未执行源代码修改、重编、写卡、JTAG 或板级恢复。旧 BOOT_MODE=0 是修正拨码前的证据；不能沿用“定案 DDR 训练失败”或据 JTAG 全 1 断言没上电。
- 入口：`4_metrics/logs/2026-09-10_sd_boot_static_audit_run01/DIAGNOSIS.md`；日志：`7_logs/2026-09-10/03_validation_summary.md` 与 `04_next_start_guide.md`。

## 2026-09-08 FREEZE udp-color-fix-pass-20260908 (UDP camera-frame R/B swap root-caused, fixed PC-side)

- Symptom: UDP camera frames showed red/blue-swapped colors (yellow object -> pale blue, blue-violet -> orange, lavender -> pink); HDMI was always correct. Root cause: VDMA S2MM packs the 24-bit {R,G,B} AXIS word little-endian, so DDR/UDP type=0x01 payload bytes are [B,G,R] per pixel, while the host decoded them as [R,G,B]. OV5640 registers (`0x4300=0x61`, RGB565 sequence 1) are NOT at fault — do NOT change them to "fix" colors (that would swap HDMI).
- **Current receiver: `3_host/udp_video/dist/EES331_UDP_Viewer.exe` — 31,187,867 B, SHA-256 `a4b75ed3423aeb2ca292623b00310ac166be6c09171527ad8397435ca193dd1d` (built from `udp_video_gui.py` V1.2, type-aware decode: type=0x01 -> BGR, type=0x02 -> RGB). Discard older copies (V1.0 31,187,636 B / V1.1 31,188,255 B) — they render camera frames with red/blue swapped.** `udp_video_rx.py` V1.1 carries the same type-aware fix; camera payload is already cv2-native BGR, so model-side frame grabbing needs no channel flip.
- Board side unchanged: the C1.2 frozen pairing below stays valid (BIT `7CB11F7D...` + ELF `3E295D51...` + XSA `30644B31...`); no rebuild or re-programming is needed to get correct colors on the PC.
- Verified: localhost end-to-end injection `ALL_COLOR_SWAP_FIX_TESTS_PASS`; user visual pass on the live board stream (recorded video: natural skin tones, 6.25 fps, ~1% loss/CRC consistent with C1.2). Byte-order erratum in the design contract: `1_docs/OV5640_UDP视频传输数据格式与上位机设计_2026-09-08.md` §10.
- Evidence: `4_metrics/logs/2026-09-08_udp_color_swap_fix_run01/` (RUN_REPORT, verification scripts + raw console log, user screenshots + final board-stream video, per-file SHA-256). Tag: `udp-color-fix-pass-20260908`.

## 2026-09-08 FREEZE udp-camera-c12-pass-20260908 (C1.2 quality PASS, 4.77 fps zero-defect)

- Frozen board-proven pairing for the camera-to-PC UDP video stream. Reproduce: program BIT -> load paired ELF -> UDP stream resumes (monitor-independent; if you also want to SEE HDMI, switch the monitor to the board input first and press reset once).
- BIT `display_test_wrapper.bit` SHA-256 `7CB11F7DF165476EB86E3D8C43CC251FB1C454ECDB64B905F0931AD971EC192E7` (4,045,696 B, 12:09).
- ELF `app_component.elf` SHA-256 `6EB0097C17ABEAF2DFDD227F89B3141BCC45B8C7D9C83099B3A97B2FE4F29ED1` (861,424 B, 14:51 build).
- XSA `display_test_wrapper.xsa` SHA-256 `30644B3158D86D0D27C34ED60626179B17046CDA7B3AF51F35431B18652D22D0` (578,739 B, 12:09).
- Binaries live under `2_fpga/0_diaplay_test/vitis/hw_20260908_eth/` (refresh the ELF copy from this freeze).
- Measured quality: 1533+ complete frames @ 4.77 fps, 丢帧=0, CRC 错=0, 重复/坏头=0/0 (GUI screenshots archived). Do NOT mix this pairing with the 09-07 HDMI-only frozen pair.
- FINAL pairing update (post C2 first attempt, PROVEN): 66 ms interval / 600 µs burst pacing -> **6.3 fps measured, 丢帧=8, CRC 错=8 over 854+ frames (~0.9%)**, HDMI camera display normal. ELF refreshed: `app_component.elf` SHA-256 `3E295D51186135E4D9DFBBA4B6C3637F3E7AECE9135F2C124C29CE9FF1D963A9` (861,424 B). C2.1 zero-copy experiment (mass udp_sendto failures at 66 ms) reverted and archived; 15 FPS needs C2.2 diagnostics (err code + lwip220 tuning).
- Quality fixes in this freeze: dual-buffer snapshot (private stable copy, latest-wins), chunked 64 KB copy with interleaved stack service, gentle burst spreading (~25 ms per frame), Global-Timer lwIP scheduling, sticky S2MM error-bit clear.
- Next: C2 rate-up (interval 200->66 ms + pacing tightening) after an optional iperf benchmark; formal 10-minute soak test can be signed off at the next board session.

## 2026-09-08 Stage C1: live camera frames over UDP to PC (BOARD PASS)

- `UDP_CAMERA_C1_PASS`: `udp_video_tx_poll` now takes the latest completed DDR snapshot (`(PARKPTR CURRENT_READ + 2) % 3`, the pre-display slot — complete/stable/no contention) and streams it as type=0x01 frames at ~5 fps runtime / 1 fps monitor; GUI shows the live OV5640 image.
- Fixes en route: black-frame bug (send_one_frame always read the never-filled pattern buffer — now selects external snapshot vs pattern), D-cache invalidate before reading DMA-written DDR, sticky S2MM error bits cleared once after first frames (false CAMERA_STREAM_FAIL eliminated), forward declaration for park_current_read.
- Known items for C1.1: 丢帧/CRC 错 counters nonzero (burst PC-socket drops + suspected snapshot tearing) — plan: dual-pointer slot avoidance, burst pacing, evaluate lwIP UDP checksum; GUI fps field sampling quirk. (The "HDMI vs UDP color difference is expected behaviour" note written here was later disproven — the real cause was the R/B byte-order swap, fixed in FREEZE udp-color-fix-pass-20260908 at the top.)
- Evidence: `4_metrics/logs/2026-09-08_mainproj_eth_loopback_integrate_run01/` (C1 GUI screenshots x3, full serial, per-fix hashes).

## 2026-09-08 Stage B1: board-to-PC UDP video stream PASS (1 fps pattern)

- Result: `UDP_TX_B1_PASS`. `app_component` V3.1.2 streams 640x480 RGB888 synthetic frames (921,600 B = 640 packets x 1,440 B + 32 B header, whole-frame CRC32, SOF/EOF flags) from the board to the PC peer at 1 fps; serial shows `UDP_TX frame=N packets=640 errors=0` (58+ frames, zero TX errors) and the GUI receiver shows the moving color-bar pattern with `完整帧` increasing at ~1 fps, `丢帧=0`, `CRC 错=0`.
- New sources: `2_fpga/0_diaplay_test/vitis/app_component/src/udp_video_tx.c/h` (sender; `UDP_TX_USE_CAMERA=0` gates stage C1), `main.c` rework — lwIP timers now scheduled on the ARM Global Timer (`xiltimer.h`/`XTime_GetTime`, 250/500 ms) because the ScuTimer interrupt path proved dead in this SDT build; `udp_video_tx_yield()` keeps ARP/RX alive mid-burst without recursion.
- PC tools (`3_host/udp_video/`): `mock_sender.py` (protocol-conformant pattern sender), `udp_video_rx.py` (CLI receiver, localhost self-test PASS 178 frames/0 loss/0 CRC), `udp_video_gui.py` → packaged `dist/EES331_UDP_Viewer.exe` (V1.0 31,187,636 B / V1.1 31,188,255 B at this milestone; **superseded 2026-09-08 by the V1.2 BGR-fix build 31,187,867 B, SHA-256 `a4b75ed3...` — see FREEZE udp-color-fix-pass-20260908 at the top**).
- Design contract: `1_docs/OV5640_UDP视频传输数据格式与上位机设计_2026-09-08.md` (32 B header table, 640-packet framing, skip-on-loss policy, staged plan; supersedes the old plan's 192.168.1.x addressing with 192.168.240.x).
- Evidence: `4_metrics/logs/2026-09-08_mainproj_eth_loopback_integrate_run01/` (B1 screenshots, full serial log, per-file hashes), `..._udp_host_tools_v1_run01/`, `..._udp_gui_exe_build_run01/`, `..._udp_video_protocol_design_run01/`.
- Known open items: camera S2MM stream error (`SR=0x15810`, SOF-early class) blocks stage C1 — check camera cabling/power first; PS config change verified clock-clean (BD diff: only ENET0/MDIO/GPIO-EMIO entries, FCLK/PLL untouched). GUI fps field reads 0/1.9 on a 1 fps stream (sampling display quirk). `UDP_TX_INIT_OK` prints "ticks" but means ms.
- Next: stage C1 — replace the pattern source with a VDMA completed-slot snapshot (PARKPTR-selected), camera S2MM must pass first; then C2 rate scale 5/15 FPS.

## 2026-09-08 Main project PS Ethernet loopback integrated (V3.1, BOARD PASS)

- Scope: `2_fpga/0_diaplay_test` Zynq PS now has ENET0 enabled (MIO 16..27, MDIO 52..53, PHY reset MIO 47, 1000 Mbps) alongside the proven OV5640 -> VDMA -> DDR -> MM2S -> HDMI path. PS config is item-for-item equivalent to the board-proven `2_fpga/2_eth_onlytest_zynq7020` loopback project (21-item PCW compare, report in the evidence run).
- App `app_component` V3.1: original camera/HDMI/UART firmware preserved; added lwIP RAW bring-up (static `192.168.240.10/24`, gateway `192.168.240.2`, MAC `00:0A:35:00:01:02`) and UDP echo on port 5000; `eth_service_ms()` keeps the stack serviced inside the existing 1 s / 5 s monitor loops. SDT build calls `init_timer()` only and does NOT enable D-cache, preserving the proven V3.0 memory behavior.
- Board result 2026-09-08 12:23: `MAIN_ETH_LOOPBACK_PASS` — NetAssist `192.168.240.2:5000` sent `你好` x3, all echoed (`3/3`, RX 12 B = TX 12 B) while the camera image kept displaying over HDMI.
- New hardware/software pairing (do NOT mix with the 2026-09-07 frozen pair below):
  - BIT `display_test_wrapper.bit` SHA-256 `7CB11F7DF165476EB86E3D8C43CC251FB1C454ECDB64B905F0931AD971EC192E7` (4,045,696 B)
  - ELF `app_component.elf` SHA-256 `52209F6271626A2B390E93E9DDF53DCD7E150EC655F2F2513B8C28F14C2ABA56` (851,088 B)
  - XSA `display_test_wrapper.xsa` SHA-256 `30644B3158D86D0D27C34ED60626179B17046CDA7B3AF51F35431B18652D22D0` (578,739 B)
  - Binaries live under `2_fpga/0_diaplay_test/vitis/hw_20260908_eth/`.
- Evidence: `4_metrics/logs/2026-09-08_mainproj_eth_loopback_integrate_run01/` (integration report, before/after hashes, PASS screenshot SHA-256 `4AA8933B02B449F314D2E336908B41252FC9DE3DB91BF4E6B2742635AFF7CE0E`).
- Still owed: full UART serial capture (ETH heartbeat + HDMI heartbeat lines) for the raw serial record.
- Next: board-to-PC UDP frame sender (synthetic pattern + incrementing frame/packet IDs), then one VDMA frame snapshot; camera transport gates stay per `1_docs/OV5640_PS以太网传输实施计划_2026-09-08.md`.

## 2026-09-07 OV5640 + PS VDMA + HDMI frozen visual PASS

- Result: `BOARD_VISUAL_PASS`. Three archived board photos show live OV5640 data through S2MM -> DDR -> MM2S -> HDMI. This is **not** `FULL_UART_ACCEPTANCE_PASS`; the final run has no complete UART capture.
- Frozen source: tag `camera-hdmi-visual-pass-20260907`; report: `4_metrics/logs/2026-09-07_camera_display_success_freeze_run01/CAMERA_DISPLAY_SUCCESS_FREEZE_REPORT.md`.
- BIT SHA-256: `16DBACBFCA755D69B08AE1720AF10D6C642E97B12F34F410241CEC1F29130624`.
- XSA SHA-256: `7374BD4EE2D30C726FC0135E1960BA2BE19BD22C3B9D75B0AB0BBEE1CE64A6E1`.
- ELF SHA-256: `040B57D048D76A60AAED8262F4E7E05204E6A96E8EF01AD6598BE4EE93BDD990`.
- Final PL facts: S2MM line buffer `1024`; dynamic Genlock; restored `~vio_hsync` / `~vio_vsync`; route `11060/11060`, 0 errors; WNS `9.510 ns`, TNS 0, all constraints met.
- Required recovery sequence: program the frozen BIT, load the frozen ELF, manually reset the camera capture once, then inspect the live image. The camera image becomes normal after this reset. Do not mix this pair with a rebuilt BIT/ELF. See `2_fpga/0_diaplay_test/doc/camera_hdmi_correct_version_2026-09-08.md`.
- Next acceptance action: zero-change full-UART rerun with the same BIT/ELF; archive from startup through at least 60 seconds. Only then upgrade the label to `FULL_UART_ACCEPTANCE_PASS` if the UART is clean.
- Forbidden immediate actions: editing frozen source/artifacts, rebuilding the platform, changing VDMA controls/sync polarity/line-buffer depth/XDC/color format, or calling the photos a formal full acceptance PASS.

## 2026-09-05 晚间板级定位（优先于下方历史结论）

本次用户重新授权继续解决 HDMI。已撤销与原理图相反的物理字节交换，并用 JTAG/ILA 取得真实板级证据。

原 SDA 推挽驱动的实测为 `raw=1F1F0FFF011F, match=1A, done=0, error=1`，并非此前声称的 BD 回读成功。
开漏 SDA 诊断版本进一步捕获到地址72的NACK，发送连续高位时实际SDA随SCL改变。网表管脚与IOBUF连接已核对；下一步必须检查上拉VADJ及外部电气连接，不能把它直接定性为某个硬件短路，也不能靠放宽读回掩码继续推进。

完整结论、边界和实物检查点：`4_metrics/logs/2026-09-05_hdmi_root_cause_run02/DIAGNOSIS.md`。
当前板上是 run02 的临时诊断位流（初始化尚未通过），不是验收通过的发布版。原工程 bitstream 未覆盖，未写 Flash。
工程日志统一更新在 `2_log/2026-09-05/`；下方历史“配置已验证”或“字节已证实反接”等表述不适用于本次实测。

## 状态

- 日期：2026-09-04
- 2026-09-04 板级链路进度：正常 Vitis Run 的 UART PASS；DDR pattern/保持测试 PASS；VDMA MM2S 单帧和连续读协议 PASS。PS/DDR/VDMA 链路驱动的 HDMI 首轮板测无显示，后续发现一次测试加载了旧 bit，因此该轮不能作为有效结论。
- 2026-09-04 纯 PL HDMI 隔离测试：实际使用 `2_fpga/1_zynqtest_2025/project_1/project_1.xpr`，顶层已确认为 `hdmi_colorbar_vtc_top`。链路为 100 MHz → `clk_wiz_0` 25 MHz → 自研 1-PPC 480p VTC → 5 条竖彩条 → `hdmi_out_adv7511`。显示器已点亮，说明时序、HDMI 时钟、DE 和 I2C 配置链路基本可用；颜色仍不正确。
- 2026-09-04 颜色根因修正：原 ADV7511 初始化表把外部 YCbCr422 总线误配置为 RGB/YCbCr444，且 AVI Infoframe 错写为 YCbCr444/VIC4。已将 `0x16` 改为 `0xB9`（YCbCr422 Style 1），AVI PB1 `0x55` 改为 `0x29`，VIC `0x57` 改为 `0x01`，checksum `0x54` 同步改为 `0xAB`。修改位于 `2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv`。
- 2026-09-04 复测纪律：`1_zynqtest_2025/project_1` 中曾出现综合 DCP 时间早于源码修改、bit 略晚生成的情况。颜色修正后必须对 `synth_1` 和 `impl_1` 执行 Reset Runs，再综合/实现/生成 bit；只有确认新 bit 晚于全部源码后，板测才有效。
- 2026-09-04 纯 PL 彩条定义：640×480@60，5 条竖彩条，每条 128 像素；预期从左到右为白、黄、青、绿、品红，亮度递减。XDC 只保留 EES-331 引脚和 LVCMOS33 电平，不做时序约束。ADV7511 当前表中的 `0x55~0x5E` 是 AVI Infoframe，不是内部测试彩条。
- 2026-09-04 辅助工程脚本：新增 `2_fpga/0_diaplay_test/rtl/hdmi_new/build_hdmi_colorbar_vtc.tcl`，可创建独立 Vivado 工程并生成 25 MHz Clocking Wizard；但实际板测复测也可继续使用 `2_fpga/1_zynqtest_2025/project_1`。
- 2026-09-04 XSCT fallback：普通 Vitis Run 再现无串口输出时，使用 `4_metrics/logs/2026-09-04_vitis_uart_bypass_run33/run_uart_bypass.tcl` 手动初始化 PS、直写 UART1 FIFO、下载并运行 ELF。先看 `XSCT OK` 是否出现，以区分串口路径和应用运行问题。
- 2026-09-04 正常启动链修正：`app_component/_ide/launch.json` 原指向旧 `.bit` 和旧 `ps7_init.tcl`，已改为当前 XSA 的 `hw/sdt` 产物。进一步发现 FSBL 虽然重编但实际源 `zynq_fsbl/ps7_init.c` 仍是旧 DDR 配置；已同步为当前 XSA 生成版本并重建，`export/.../boot/fsbl.elf` 已同步。普通 Vitis Run/Debug 复测仍待用户执行。
- 2026-09-04 UART 自初始化：正常 Run 仍无输出后，`main.c` 已在入口第一行自初始化 UART1 时钟、MIO48/49、115200-8-N1 和 RX/TX，不再依赖 launch/PS7 是否成功完成 UART 配置。应用构建 PASS；下一步只用 Vitis 正常 Run/Debug 验收。
- 状态：HDMI TOP MODEL SIM PASS / CAM PCLK PLAN A IMPLEMENT PASS / BITSTREAM GENERATED / OOC ERRORS NONBLOCKING / BD CONNECTION CHECK PASS / RAW UART TX BOARD PASS
- GitHub：关键 RTL、集中后的测试台/仿真脚本、文档和最终证据已发布到 `main@d9dd5b4`
- 最新顶层归档：`main@12d31e1`，活跃顶层已改为 `hdmi_out_adv7511.v`
- 最新 XDC 归档：`main@c52e72b`，EES-331 HDMI/ADV7511 引脚约束已补齐
- 最新 BD 核对：run28，OV5640+HDMI 关键连线清单完成
- 分辨率：480p / 640x480@60
- 像素时钟：25.175 MHz
- 颜色空间：BT.709，RGB888 转 YCbCr422
- 目标路径：`E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new`

## 当前模块

| 模块 | 状态 | 说明 |
|---|---|---|
| `rgb2ycbcr422` | 实现完成，视频检查通过 | BT.709 定点转换与 Cb/Cr 奇偶打包 |
| `adv7511_init_table_pkg` | 实现完成，板级待验 | 480p 首版寄存器配置表 |
| `adv7511_controller` | 配置仿真 PASS | 上电延时、启动、完成/错误控制 |
| `adv7511_iic_data_xfer` | 配置仿真 PASS | 配置表读取、寄存器地址/数据传输握手 |
| `iic_protocal` | 直接复用用户源码，配置仿真 PASS | 底层 IIC 协议，ADV7511 地址 7'h39，分频 252 |
| `adv7511_cfg_top` | 配置仿真 PASS | 配置模块顶层，集成控制、传输和 IIC 协议 |
| `hdmi_out_adv7511` | Verilog 顶层整体 ModelSim PASS | `.v` 顶层集成、输出寄存与 ODDR 时钟转发，供 BD Module Reference 直接引用 |
| `iic_multi_byte` | 非活跃资产 | 保留用于后续连续寄存器突发扩展 |

当前可复现仿真入口：`E:\competition\2_fpga\0_diaplay_test\sim\run_modelsim.do`；测试台位于 `E:\competition\2_fpga\0_diaplay_test\sim`。Verilog 顶层最终复现证据见 `4_metrics/logs/2026-09-03_hdmi_top_verilog_run22`。

BD 集成限制已关闭：原 `.sv` 顶层被 Vivado 2020.2 Module Reference 拒绝，错误码 `filemgmt 56-195`；当前已改为等价 `hdmi_out_adv7511.v` 顶层，独立工程确认可创建 BD RTL cell。旧 `.sv` 顶层已删除。

## 顶层接口冻结

`PIX_CLK`、`RST_N`、`RGB888[23:0]`、`DE`、`H_SYNC`、`V_SYNC`、`HDMI_INT`；`HDMI_SDA`；`HDMI_DATA[15:0]`、`HDMI_CLK`、`HDMI_HSYNC`、`HDMI_VSYNC`、`HDMI_DE`、`HDMI_SCL`。BD wrapper 实际导出端口均带 `_0` 后缀。

## 下一步

XDC 已按 EES-331 手册补齐 HDMI/ADV7511 引脚，并通过端口、重复引脚和电平标准检查。下一步在 Vivado 中重新加载约束，执行 BD 校验、综合、实现和时序检查。Verilog 顶层仿真证据见 `4_metrics/logs/2026-09-03_hdmi_top_verilog_run22`；BD Module Reference 接受证据见 `4_metrics/logs/2026-09-03_hdmi_bd_verilog_ref_check_run23`；XDC 检查证据见 `4_metrics/logs/2026-09-03_hdmi_xdc_constraint_check_run24`。

最新实现失败原因已分析完成：`cam_pclk_0/AA22` 是普通 IO，但被用作相机采样时钟并插入 BUFG，触发 `Place 30-574 / Place 30-99`。尚未修改设计，等待用户在“降级 CLOCK_DEDICATED_ROUTE”与“重构相机 PCLK 采样架构”之间确认。分析证据见 `4_metrics/logs/2026-09-03_hdmi_impl_place_failure_analysis_run25`。

## 归档记录

- 已更新 `README.md` 的 HDMI 架构、验证状态和未验证边界。
- 已新增 `.gitignore`，排除 Vivado/ModelSim 缓存、库文件、波形和构建产物。
- 已选择性提交活跃 RTL、testbench、关键 Markdown、最终 ModelSim 命令与原始 transcript；未提交工程目录、旧架构和非活跃突发 IIC 资产。
- 已将三个测试台和 `run_modelsim.do` 集中到 `2_fpga/0_diaplay_test/sim`，迁移后整体 ModelSim 回归 PASS，提交为 `main@d9dd5b4`。
- 已将活跃顶层从 `hdmi_out_adv7511.sv` 改为等价 `hdmi_out_adv7511.v`，ModelSim 回归 PASS，Vivado 2020.2 BD Module Reference 检查 PASS，提交为 `main@12d31e1`。
- 已将 EES-331 手册中的 23 个 HDMI/ADV7511 引脚补入工程 XDC，并保存 `XDC_VALIDATION_PASS` 证据，提交为 `main@c52e72b`。
- 已分析综合后 `place_design` 失败原因，保留 Vivado 日志、DRC 报告和 AA22 引脚能力查询；尚无修复动作，提交为 `main@92a9bdc`。

## 固定流程

每次关键动作后必须同步更新 `E:\competition\7_logs\YYYY-MM-DD\` 四个日志文件和 `E:\competition\HANDOFF.md`；验证原始日志必须保存到 `4_metrics`。
## 2026-09-03 方案 A 实现结果

用户已确认采用方案 A，并根据 Clocking Wizard 实际频率将相机返回的 `cam_pclk_0` 约束为 41.600 ns（24.03846 MHz）；外层主时钟 `clk_in1_0` 不添加重复 `create_clock`，`cam_pclk_0_IBUF` 已设置 `CLOCK_DEDICATED_ROUTE FALSE`。静态证据见 `4_metrics/logs/2026-09-03_hdmi_cam_pclk_plan_a_apply_run26`。Vivado 2025.2 实现已通过，全局 WNS/TNS 为 `10.551/0.000 ns`，WHS/THS 为 `0.023/0.000 ns`，`cam_pclk` 域 WNS/WHS 为 `35.138/0.070 ns`，route error 为 0，`display_test_wrapper.bit` 已生成。OOC 子 run 中的 `Failed to create directory C` 为非阻塞错误，详细判定见 `4_metrics/logs/2026-09-03_hdmi_ooc_synthesis_error_analysis_run27`。下一动作是板级 HDMI 显示验证；是否清理 OOC error 由用户确认。
## 2026-09-03 BD 连线核对

已对照 2020 `cam_vdma_hdmi_true` 工程生成清单：`2_fpga/0_diaplay_test/doc/bd_ov5640_hdmi_connection_checklist.md`。OV5640 采集、Video In、VDMA S2MM/MM2S、HP0/HP1、Video Out、VTC、`pix_frame_display` 到新 HDMI 前端的关键连线一致。当前控制面使用 SmartConnect，参考工程使用 AXI Interconnect；Zynq 7010/7020、50/100 MHz 外部时钟、PS FCLK0 频率和 HDMI 输出架构差异均记录为工程基线差异。VDMA S2MM line buffer 当前为 512、参考为 1024；当前 `rom_data` 接常量 0，参考接 ROM。二者需理解但不阻断当前板测。证据见 `4_metrics/logs/2026-09-03_bd_connection_check_run28`。
UART self-test build PASS; board test pending.
UART header dependency removed and rebuild pass.
UART delay and print headers now declared locally and rebuild pass.
GUI build and run log check pass; serial retry with COM6 open before Run.
XSCT target check complete after direct UART attempt; board power cycle required before next Run.
## 2026-09-03 UART 无输出根因更新

用户确认 Zynq DDR 型号/配置未按 EES-331 板卡正确选择，并已完成修改。该根因可解释 FSBL/应用进入 DDR 后跑飞、debug session 提前断开、自动 COM6 终端关闭且 UART 无输出。当前仍是根因记录，不是 UART 板级 PASS；必须重新生成/导出 XSA，更新 Vitis platform/BSP/FSBL，重建应用，重新上电后在唯一 COM6 `115200-8-N1` 终端验证 header、heartbeat 和 RX echo。证据见 `4_metrics/logs/2026-09-03_vitis_uart_ddr_root_cause_run31/ddr_root_cause.md`。
## 2026-09-03 最小 UART Raw TX 测试

用户已完成 DDR 修正、XSA 更新、platform/BSP 更新和重新编译，但 UART 仍无输出。`app_component/src/main.c` 已简化为直接写 PS UART1 TX FIFO（`0xE0001030`），仅检查 TX FULL（`0xE000102C` bit3），并持续输出 `UART OK\r\n`；不再依赖 `xil_printf`、BSP API、heartbeat 或 RX echo。SOURCE UPDATE COMPLETE / BUILD PASS / BOARD TEST PENDING；ELF text/data/bss 为 `25600/1420/22952`。复测需唯一 COM6 `115200-8-N1` 终端；若无输出，排查 UART1 MIO、时钟/波特率、初始化、COM 端口映射和硬件路径。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/minimal_raw_tx.md`。
## 2026-09-03 XSCT 直接 UART 分流结果

Vitis Run 日志缺少完整下载/运行流程，调试器反汇编出现无效内容，不能证明应用执行。改用 XSCT 直接执行新 XSA 的 `ps7_init.tcl` 后，寄存器回读确认 `MIO48_CTRL=0x12E0`、`MIO49_CTRL=0x12E1`、`UART_BAUDGEN=0x7C`、`UART_BAUDDIV=6`；已直写 `XSCT OK\r\n`，并下载运行最小 `app_component.elf`。当前等待 COM6 确认是否出现 `XSCT OK` 和重复 `UART OK`。若两者都出现，UART 硬件路径正常，问题收敛为 Vitis Run 流程；若都没有，继续排查 COM6 与板卡 UART 的硬件映射。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/direct_xsct_uart_result.md`。
## 2026-09-03 UART TXFULL 位修正

用户确认 COM6 只出现 XSCT 直写的 `XSCT OK`，证明 COM6/UART1 硬件路径可用。XSCT 停机确认应用卡在 `main.c:9` 的错误等待循环：原掩码使用 `0x08`，但 Zynq UART 状态寄存器 `0x08` 是 `TXEMPTY`，BSP 定义的 `TXFULL` 是 `0x10`。已改为 `UART1_STATUS_TX_FULL=(1UL << 4)` 并重建 ELF（text/data/bss `25600/1420/22952`），随后通过 XSCT 下载运行。当前 UART BOARD TX 为 FIX APPLIED / COM6 REPEAT CONFIRMATION PENDING。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/txfull_bitfix_result.md`。
## 2026-09-03 UART Raw TX Board PASS

修正 Zynq UART1 `TXFULL` 位后，COM6 已连续输出 `UART OK`，`app_component.elf` 经 XSCT 加载到 `0x00100000` 并运行；调试反汇编也显示有效 `_start/main/uart_puts/uart_putc/exception` 代码。结合 DDR 修正，最小 UART 应用的板级执行链路已通过。当前结论为 `RAW UART TX BOARD PASS`；UART RX echo 和 HDMI 显示仍待验证。当前 `main.c` 仍是最小 TX 固件。证据见 `4_metrics/logs/2026-09-03_vitis_uart_minimal_raw_tx_run32/uart_board_tx_pass.md`。


## 2026-09-05 HDMI A5 板级签名与暂停边界（历史状态）

- 用户重新生成并下载后观察到 `LED0..LED7 = 8'b1010_0101`，与固定构建签名
  `8'hA5` 完全一致，证明 `hdmi_colorbar_vtc_top` 的纯 PL bitstream 已被正确加载。
- A5 版本只改变 LED 调试输出，没有改变 HDMI 视频数据，因此画面没有变化是该版本的
  预期结果，不能据此判断颜色修正或寄存器回读是否生效。
- 已加载 bitstream 时间为 `2026-09-05 13:11:49.160`；当前顶层与重写后的
  `iic_protocal.v` 均在约 `13:41` 才修改。因此该板测不包含、也不验证当前 I2C 重写。
- 该段记录的是当时的暂停状态；后续已恢复协议修改，并完成协议与 SW0 版本的联合 RTL 回归。

## 2026-09-05 SW0 RGB/YCbCr 模式切换实现

- 纯 PL 顶层 `hdmi_colorbar_vtc_top` 新增 `SW0` 输入，约束为 `AB6`；S2 仍保持为 PS
  专用复位键，不接入 PL。
- `SW0=0` 为 RGB888 经 FPGA 转换，`SW0=1` 为直接 BT.709 limited-range YCbCr422。
- 模式先两级同步，再在帧起点锁存；直出数据和控制信号保持与 RGB 转换路径相同的三拍
  延迟，避免半帧切换。
- LED7 显示当前直出模式，LED6:LED0 保留低七位回读调试信息；复位继续显示 A5。
- ModelSim 通过：`4_metrics/logs/2026-09-05_hdmi_mode_switch_run01/mode_result.txt`
  报告 `MODE_SWITCH_PASS`，并保留非空 WLF。尚未生成新的 bitstream。

## 2026-09-05 协议与 SW0 版本合并验证（历史，已被后文原始协议恢复替代）

- 当时用户恢复协议修改要求；当时活动版本继续使用重写后的
  `2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v`，未恢复旧版协议。
- `iic_protocal.v` 已按板级接口改为 FPGA 单向输出 SCL、SDA 保持双向开漏，支持单寄存器写、
  随机读/重复 START、ACK/NACK、单字节读后的主机 NACK、合法 STOP/错误 STOP，并导出
  `iic_error` 和 `iic_rd_data_valid`。
- `adv7511_iic_data_xfer.sv` 完成 34 次写入后读取 6 个关键寄存器，保存全部原始回读值，
  并在读回不匹配时给出位图而不提前终止。
- 独立 Vivado 建工程脚本 `build_hdmi_colorbar_vtc.tcl` 已补入
  `../iic/iic_protocal.v`，避免新工程遗漏底层协议源文件。
- 当前源码回归证据：
  `4_metrics/logs/2026-09-05_hdmi_protocol_sw0_run01`。
  底层协议 PASS；配置成功回读 `bitmap=111111/raw=101208bd0110`；故意失配
  `bitmap=111011/raw=101208bc0110`；NACK 快速错误 PASS。
- 协议和 SW0 均只完成 RTL/ModelSim 验证，尚未由本轮生成或下载 bitstream；板级结论仍待
  用户重新综合、实现、生成并下载当前源码。

## 2026-09-05 HDMI 黑屏修正

- 用户反馈协议版本下载后 HDMI 完全无显示。优先收敛到 ADV7511 初始化条件，而不是改变
  已通过仿真的 RGB/YCbCr 视频路径。
- 按 ADV7511 Hardware User's Guide 的上电要求，将配置启动延时从 120 ms 改为 200 ms。
- 重写协议使用开漏 SCL/SDA；为避免板上外部上拉缺失或未装导致总线浮空，在
  `hdmi_colorbar_vtc_top.xdc` 对 `HDMI_SCL/HDMI_SDA` 增加 FPGA 弱上拉。
- SW0 模式切换仿真在该修正后仍为 `MODE_SWITCH_PASS`。尚未生成 bitstream，下一步由用户
  重新综合、实现并下载验证：复位时 LED 应为 A5，释放复位后检查 LED 和 HDMI 是否恢复。

## 2026-09-05 原始 I2C 协议恢复（当前状态）

- 用户明确要求停止使用重写协议并恢复原协议；当前活动源已恢复
  `2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v` 的原始状态机和端口。
- `adv7511_iic_data_xfer.sv` 已移除重写版 `iic_error` 连接，改为沿用原协议的
  `iic_done` 加上外层超时判断；SCL 仍是 FPGA 输出，SDA 仍为双向开漏。
- 现有 SW0 RGB888/YCbCr422 帧边界切换、五色彩条、LED/约束修改均保留。
- 原始协议配置级回归通过：
  `4_metrics/logs/2026-09-05_adv7511_i2c_original_run01/cfg_success_result.txt`
  为 `bitmap=111111/raw=101208bd0110`；故意失配结果为
  `bitmap=111011/raw=101208bc0110`。
- 当前仍未生成或下载新的 bitstream；用户下一步可直接在 Vivado 中重新综合、实现、生成
  bitstream 并观察 HDMI 与 LED。

## 2026-09-05 板级竖条与物理字节交换（当前待上板）

- 用户反馈两个 SW0 输入模式都能显示但颜色错误，图像呈现白色偏绿、黑色偏红、红/蓝区域
  逐像素竖条，绿色区域基本正常。
- 该现象对应 ADV7511 将当前逻辑 `{Y,Cb/Cr}` 按 `{Cb/Cr,Y}` 解释；不是 RGB 转换公式
  的主要问题。
- 保留 `R0x16=0xBD` Style 3 和逻辑 `{Y,Cb/Cr}`，在
  `hdmi_colorbar_vtc_top.v` 与 `hdmi_out_adv7511.v` 的物理输出边界加入
  `{data[7:0],data[15:8]}` 字节交换。
- RTL 自检通过：16/16 像素无 YCbCr mismatch；证据见
  `4_metrics/logs/2026-09-05_hdmi_physical_byte_swap_run01`。
- 当前没有生成 bitstream；下一步重新综合下载后检查五色顺序及 `R0x16` 回读值。

## 2026-09-05 最新板级结果归档（暂停修改）

- 用户上传的最新板级照片已保存至
  `4_metrics/logs/2026-09-05_hdmi_board_result_run01/board_result_2026-09-05_run02.jpg`，
  详细说明见同目录 `board_result.md`。
- 现象：HDMI 能够稳定显示，但五色图像仍与预期不匹配，画面存在明显密集竖状条纹；本结果不能作为颜色或寄存器回读正确的验收结论。
- 本次只做证据归档和日志更新；没有修改 RTL、I²C、ADV7511 寄存器表、物理字节交换、XDC 或仿真文件，也没有生成/下载新的 bitstream。
- 图片 SHA-256：`E3D91414AB79266C725F0A276155BC2F8B87EC19A3AD8058ABB52B36F7A3A75E`。
- 当前工作边界：等待用户明确重新启动调试；在此之前不继续尝试颜色修正或协议修改。
(current tail continued)

## 2026-09-06 ADV7511 final board PASS

- Final 480p solution is frozen: logical `{Y,Cb/Cr}`, ADI BT.601 limited-range
  CSC table V1.3, `R0x15=01`, `R0x16=38`, `R0x48=08`, and an EES-331 port
  byte swap at `physical_data`.
- Board result: White / Black / Red / Blue / Green solid bars, no stripes.
  Raw photo:
  `4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/board_pass_white_black_red_blue_green.jpg`.
- ModelSim physical-swap regression PASS marker:
  `MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch`.
  Stable result file: `mode_result.txt` in the same run folder.
- Do not restore `physical_data = selected_data`; the unswapped build produced
  chroma stripes in the red/blue/green bars.

## 2026-09-06/07 开发机迁移 + 2_fpga 验证版合入 + AI 侧手势通路

- 开发机迁移：项目根目录现为 `E:\Work\Projects\AMD_proj\FPGA_competition_2026`（本仓库完整克隆），Vivado 2025.2 ML Standard 已装（仅 Zynq-7000 家族）。旧开始菜单快捷方式指向失效路径，桌面快捷方式已修复。
- 2_fpga 更新：以队友交付的验证版 zip 整体合入——`0_diaplay_test`（hdmi_new V1.8：`adv7511_init_table.sv` 含 CSC 与读回校验，新增 rtl/HDMI TMDS 直出、data_pre、fr_display、ov5640_data_cap；proj display_test 工程；sim 新增 4 个测试台）、`1_zynqtest_2025`（本地恢复，含 ILA，按约定不入库）。合入前旧版已备份至本地 0_assets（不入库）。
- ADV7511 颜色根因分析（文档级，未板测）：4:2:2 输入映射受 R0x48[4:3] 对齐与 R0x16[3:2] Style 双控制，且寄存器 Style 值与手册编号不对应（Linux 驱动注释佐证）；EES-331 仅接 D[15:0]，Style 2/3 使芯片读 D[23:16] 悬空脚。队友 CSC 直出 RGB 方案已板测通过，维持不动；分析留作 422 直通备援路线资料。证据：`7_logs/2026-09-07/`（HWUG Table 7、EES-331 手册页截图）。
- AI 侧（3_host）：手势模型 v1 训练完成（YOLOv8n + Roboflow hand-gesture v6，7 类，test mAP50 0.730；Stop/Thumbs up/Up/Down 优秀，Left/Right/Thumbs Down 为弱项）；PC 全链路（摄像头→JPEG→UDP→ONNX CPU→JSON 回传）实测通过，P50 62ms；UDP 协议 v1 定稿于 `1_docs/interface.md`（分片/心跳/异常处理）。
- 待办：①2025.2 环境基线 bit 复现（Reset Runs→板测彩条）②PS 显示验证 ③lwIP 发帧端（协议见 1_docs/interface.md）④AI 侧自采 Left/Right/Thumbs Down 数据重训 v2 ⑤舵机臂下单 ⑥中期报告 10-09。
- 详细记录：`7_logs/2026-09-07/` 四件套。

## 2026-09-11 SD/PYNQ 摄像头双路输出

- 指定目录 `2_fpga/0_diaplay_test/pynq` 已完成 PYNQ 3.0.1/Linux 控制层：加载配对 Overlay、用 `pynq.allocate` 管理三帧 VDMA 缓冲、HDMI 连续显示，并以 OV56 协议向 PC 发送 UDP 视频。
- 板卡固定业务地址为 `192.168.240.10/24`，PC 有线网卡为 `192.168.240.2/24`，UDP 端口 5000，默认发送 5 fps。PC 使用 `3_host/udp_video/dist/EES331_UDP_Viewer.exe`。
- 当前已部署且未重刷的 SD 卡保持 SW8 为 SD 启动，上电后由 `ees331-camera.service` 自动加载 PL 并启动业务；无需 Vitis、JTAG、Jupyter 或手工执行 Python。通常等待约 60 至 90 秒。
- 验证结果：`PYNQ_CAMERA_HDMI_UDP_PASS`、`SD_REBOOT_AUTOSTART_PASS`。120 秒运行发送 600 帧/384000 包且 VDMA 无运行错误；用户确认 HDMI 与 PC 均为随动作变化的实时画面。最终软件重启后 PC 接收 604 帧，CRC/丢帧/坏头均为 0。
- 验证边界：软件重启自动恢复已经通过，物理断电冷启动尚未单独验收。若重刷当前基础 IMG，业务文件、CMA 参数、网络配置和 systemd 服务会丢失，需要重新部署。
- 原 XSA、`main.c`、`BOOT.BIN`、`IMAGE.UB`、`BOOT.SCR` 未修改。完整证据见 `4_metrics/logs/2026-09-11_pynq_camera_run01/REPORT.md`。
- 后续顺序已冻结：先将当前成果上传至 `codex/full/pipidandan-superman`；确认远端提交后，再为 SD Builder v0.2 增加完整 IMG 的 PYNQ 应用注入，并在 `1_docs` 编写零基础开发教程。

## 2026-09-11 SD Builder v0.2.1 整合完成

- Gate 1 已上传并核对远端提交 `927548961e5cc3d13d5de67cc613071aa5df63a5`，随后才开始 Builder 和教程工作。
- `3_host/pynq/sd_boot_builder_v02` 已增加完整 IMG 的 PYNQ rootfs 注入，写入摄像头应用、配对 Overlay、`cma=128M@0x10000000`、固定网络和 `ees331-camera.service`。
- 整合模式固定要求当前已板测 XSA 哈希、完整 IMG 和 `manual` PL 模式。这里由 systemd 在 Linux 启动后自动调用 Overlay，日常上电无需人工运行 Python。
- Cygwin `debugfs/e2fsck` 1.44.5 的模块测试、逐文件读回和文件系统检查通过。MSYS2 e2fsprogs 获取失败作为历史失败保留，不是最终依赖路径。
- 冻结 EXE 首次完整构建在 `2026-09-11_sd_builder_v02_220613_158787` 因 PyInstaller Tcl/DLL 污染 XSCT 而失败；修复 `SetDllDirectoryW(None)` 和 Tcl 环境变量清理后重打包。
- 最终 `EES331SDBootBuilder_v0.2.1.exe` 大小 22,520,487 字节，SHA256 `c2966e6fa52bfb8786c0232221e4eb540b96b383406be1e38d581bf3a070f49a`，GUI 自检通过。
- 最终 EXE 完整构建目录：`4_metrics/logs/2026-09-11_sd_builder_v02_222654_1789ce`；结果 `SD_PACKAGE_STATIC_PASS`，应用注入、启动文件、完整读回均 PASS。
- 输出 IMG 大小 7,858,807,808 字节，SHA256 `8d22bcde0268678050bcc1429bee5ecadb0020e5ce3f5ba4df7045066deafcca`。完整 IMG 不上传 Git。
- 写卡使用 `8_tools/win32diskimager-1.0.0-install.exe`。该新 IMG 尚未写卡；下一步是备用 SD 卡物理断电冷启动、UART、HDMI 和 UDP/PC 联合验收。
- 零基础教程：`1_docs/PYNQ零基础开发与EES331摄像头工程实战.md`。
- 整合报告：`4_metrics/logs/2026-09-11_sd_builder_pynq_integration_run01/REPORT.md`。
- Git 功能提交 `87ce6f3` 已与最新 main 合并，第一轮远端核对提交为 `6f76d67dfa597cb56281a9242256f889d1e3205c`；上传回执见同一整合证据目录的 `upload_result.json`。

## 2026-09-11 SD Builder v0.2.2

增加自定义部署包输出目录（GUI、CLI --output-dir、JSON output_dir）。独立子目录避免覆盖，逐文件 SHA256 验证后发布；留空兼容旧版。5 项测试、冻结 EXE 自检和真实完整 IMG/自定义复制读回通过。发布入口 `8_tools/sd_start_tool_v0.2/EES331SDBootBuilder_v0.2.2.exe`；报告 `4_metrics/logs/2026-09-11_sd_builder_output_dir_run01/REPORT.md`。新 IMG 未写卡冷启动。保留 v0.2.1。

## 2026-09-11 集成 IMG 板测与归档入口

- 用户实际写卡并验证成功的镜像来自 `4_metrics/logs/2026-09-11_sd_builder_v02_222654_1789ce/output/ees331_pynq_sd.img`，不是后续仅完成离线构建的 224206 镜像。
- 本机正式归档副本为 `9_pynq/sd/02_integrated_camera_hdmi_udp/ees331_pynq_sd_20260911_222654.img`，大小 7,858,807,808 字节，SHA256 `8d22bcde0268678050bcc1429bee5ecadb0020e5ce3f5ba4df7045066deafcca`。
- 板测结果：SD 启动正常，OV5640 配置完成 LED 点亮，HDMI 和 PC UDP 上位机都显示随动作变化的实时画面。最初 PC 零帧是网线未连接，插好网线后恢复正常。
- EES-331 最小系统基线、当前集成镜像和配套启动分区分别归档于 `9_pynq/sd/01_base_ees331`、`02_integrated_camera_hdmi_udp`、`03_boot_partition`；通用 PYNQ-Z2 镜像已退出项目基线，清单见 `9_pynq/sd/manifests/images.json`。
- 后续写卡、复现和排障从 `9_pynq/sd/README.md` 开始；不要把 224206 镜像描述为已板测版本。
