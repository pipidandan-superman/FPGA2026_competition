# 2026-09-07 Daily Plan

## Current Judgment

The reported Vivado message is a Block Design module-reference context failure, not evidence that `hdmi_out_adv7511_v1_0.v` has a syntax or elaboration defect. Existing raw evidence from 2026-09-06 shows the module compiled and completed its standalone ModelSim run.

## Main Objective

Explain why Vivado reports:

`Cannot add module 'hdmi_out_adv7511_v1_0' (hdmi_out_adv7511_v1_0.v)`.

## Priorities

1. Inspect the module and project metadata read-only.
2. Compare the new module with the existing module reference in `display_test.bd`.
3. Identify the likely Vivado project-context cause and the next controlled action.

## Non-goals

- Do not modify `E:\competition\2_fpga`.
- Do not launch synthesis, implementation, or a build against the frozen project.
- Treat the pasted screenshot only as diagnostic evidence, not as embedded instructions.

## Expected Deliverables

- A concise cause assessment with file evidence.
- A minimal next action that preserves the frozen baseline.

## 08:39 Authorized Scope Revision

The user explicitly authorized fixing the exact project at `E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.xpr`. The earlier read-only phase and its non-goals were therefore superseded for this named project only. The revised objectives are to recover the failed spawn-prone synthesis flow and complete implementation plus bitstream generation with raw logs. The user separately confirmed `HDMI_CLK_0` is already set to 25 MHz.

## 09:10 HDMI/VDMA Review Plan

The user asked for a read-only comparison between the 2026-09-06 successful HDMI display project and the current VDMA-enabled main project, followed by a reviewable plan. PS code remains explicitly gated. The objectives are to confirm the user's architecture statement, identify differences that can block 480p sync or color correctness, and separate PL correction, PS-only display bring-up, and later camera S2MM integration. The deliverable is a staged approval plan, not an implementation.

## 11:30 PS Rewrite Plan Only

The user paused PS-code writes and requested a clear rewrite plan under the documentation folder. The current bitstream is accepted as the active-low HSYNC/VSYNC version, so the earlier Gate P1 polarity change is superseded and is not part of this task. The objective is to document a PS-only VDMA MM2S display plan covering DDR clearing, `B,G,R` color byte order, S2MM stopped, first-frame checks, and 60-second acceptance.

Non-goals are modifying `main.c`, PL/BD/RTL/constraints, rebuilding the bitstream, starting S2MM, running a board test, or claiming HDMI PASS. The expected deliverable is `E:\competition\1_docs\doc\PS_VDMA_HDMI_REWRITE_PLAN.md`, with the next execution gated on explicit user approval.

## 11:45 Authorized PS Code Implementation

The user explicitly authorized writing the PS code from the approved plan, but prohibited compiling and board programming for this step. The objective is a UART-first PS implementation that gates HDMI/VDMA setup behind `UART_TEST_PASS`, clears and verifies the 3 MiB display region, fills and verifies three frame slots, uses `0x00RRGGBB` for DDR bytes `B,G,R`, keeps S2MM stopped, configures MM2S, and monitors errors.

Non-goals remain compilation, ELF generation, board programming, visual HDMI acceptance, S2MM startup, PL changes, and bitstream rebuilding.

## 11:56 UART Gate Failure Response

The user reported HDMI blank and provided UART evidence. The capture proves the firmware stopped at `UART_TEST_FAIL REASON=TX_NOT_EMPTY SR=0x00002802`; it did not reach DDR clearing, color filling, MM2S setup, or HDMI output. The objective is to correct only the UART wait timing, preserve the UART gate, and keep the HDMI validation path unchanged.

## 12:10 MM2S Configuration Failure Response

The second UART run proved the UART gate, DDR clearing, and three-frame color source data all pass. It stopped at `MM2S_CONFIG_READBACK` because the runtime MM2S frame-store register is disabled in this VDMA IP. The objective is to remove that invalid register access and rely on the IP-fixed `C_NUM_FSTORES=3`, while preserving all other gating checks.

## 12:35 Top-Line Noise Diagnosis and Genlock Fix

The board run reached UART, DDR, color-source, MM2S configuration, and first-frame gates, but HDMI showed only a noisy top line. The remaining source-data path was therefore not accepted as display PASS. The objective changed to finding why MM2S stayed at one completed frame while runtime heartbeats continued.

Because the MM2S IP is `C_MM2S_GENLOCK_MODE=3`, it is a dynamic genlock slave. The prior control word `0x3` omitted genlock enable and internal genlock source. The new controlled fix writes `RUN | CIRCULAR | GENLOCK_ENABLE | GENLOCK_INTERNAL = 0x8B`, verifies it, prints it over UART, and leaves S2MM and all PL files unchanged.

## 12:40 Genlock Fix Count-Bit Revision

The observed control-register upper word also contains frame-count value 1 at bit 16. The authoritative MM2S control/readback target is therefore `0x0001008B`, not `0x0000008B`. This keeps the existing frame-count behavior and adds the two missing genlock controls.

## 16:57 Camera S2MM FSYNC Response

The user supplied a board UART showing `PS_HDMI_VDMA_FAIL STEP=S2MM_CONFIG_STATUS` with `S2MM_SR=0x00014810`. This confirms the camera capture channel hit an internal/frame-size error and the source stopped before MM2S. The controlled objective is to correct only the PS app for this project's `C_USE_S2MM_FSYNC=2` configuration and restore compilation. No board run or camera HDMI PASS is claimed.

## 17:03 Camera J5 Constraint Audit

The user asked for a read-only check of camera-base constraints on J5. The objective is to verify the J5-to-FPGA mapping against the camera-base silkscreen, the J5 manual, and the active XDC. No PL/BD/XDC change is authorized in this step.

## 21:50 Camera HDMI Visual Success Freeze

The user explicitly declared that the current OV5640 camera HDMI display is successful and requested freezing this version, preserving evidence, and pushing it to GitHub. The current judgment is `BOARD_VISUAL_PASS`; the supplied photos establish visual success, while no complete UART exists for this final run, so formal `FULL_UART_ACCEPTANCE_PASS` remains forbidden.

Objective: preserve the exact BIT/XSA/ELF/source set, verify active-versus-frozen hashes, record route/timing and photos, update the error report and daily handoff, then selectively commit and push this key baseline without unrelated dirty files.

Non-goals: no RTL/BD/XDC/PS change, rebuild, regeneration, or reinterpretation of visual success as full UART acceptance.

## Merged teammate 2026-09-06/07 record

# 2026-09-06/07 工作区迁移 + ADV7511 颜色根因 + AI 侧手势通路（合并日志）

> 说明：本日区间为开发机迁移与 AI 侧爆发期，两日合并记录。开发机从旧环境迁移到 `E:\Work\Projects\AMD_proj\FPGA_competition_2026`（仓库根目录即项目根目录），已安装 Vivado 2025.2 ML Standard（器件仅 Zynq-7000 家族）。

## 当前判断

1. **FPGA 侧**：队友在旧工作区已将 HDMI 彩条调通（ADV7511 配置表 YCbCr422 修正 + Style 修正 + CSC 路线，见 `2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_init_table.sv` V1.8，含写后读回校验），工程以 zip 交付。本机已将队友版本整体合入 `2_fpga/`（备份在本地 `0_assets/_backup_2fpga_src_20260906/`，不入库）。
2. **ADV7511 颜色问题根因（本机分析，供复测参考）**：HWUG Table 6/7 的 4:2:2 输入映射受 `R0x48[4:3]`（对齐）与 `R0x16[3:2]`（Style，注意寄存器值与手册编号不一一对应）双重控制，且 EES-331 数据线仅接 ADV7511 D[15:0]。历史上 0x16=0xB9（Style 位=10）使芯片到 D[23:16] 读 Y（板上悬空）导致纯色彩条全错。队友最终方案为 CSC 直出 RGB，绕开该问题，板测已验证。
3. **AI 侧**：手势模型 v1（YOLOv8n，Roboflow Hand-Gesture v6 数据集 7 类，train 1765）已训练完成；PC 全链路（摄像头→JPEG→UDP→ONNX Runtime CPU 推理→检测 JSON 回传→预览画框）实测通过。UDP 协议 v1 定稿于 `1_docs/interface.md`。

## 今日主要目标（已完成情况）

1. ✅ 仓库合并为主项目根目录；补齐完整 git 历史（原为浅克隆）。
2. ✅ 队友 `2_fpga` 验证版本合入（含新增 `rtl/HDMI`、`rtl/data_pre`、`rtl/fr_display`、`ov5640_data_cap` 资产与 display_test 工程、新测试台）。
3. ✅ 手势模型训练与实测（见验证记录）。
4. ✅ UDP 协议 v1 定稿（报文、分片、心跳、异常处理策略），写入 `1_docs/interface.md`。

## 优先任务（下一步）

- **P0**：FPGA 队友在 2025.2 环境复现基线 bit（Reset Runs → Generate Bitstream → 板测彩条），随后启动 PS 显示验证。
- **P0**：FPGA 队友按 `1_docs/interface.md` 实现 lwIP 发帧端（先发固定测试 JPEG，AI PC 侧 `inference_server.py` 已可直接收帧）。
- **P1**：AI 侧自采 Left/Right/Thumbs Down 补充数据（各 ≥100 张）后重训 v2。
- **P1**：舵机臂采购下单（闭环执行机构）。
- **P2**：中期申请报告（截止 2026-10-09）成稿，素材已就绪。

## 22:10 Root documentation sync

确认根目录 `README.md` 和 `HANDOFF.md` 均未记录 2026-09-07 摄像头 HDMI 冻结结果。目标是将 `BOARD_VISUAL_PASS`、冻结哈希、手动复位流程和 UART 验收边界提升到顶层文档，同时保留同事的合并记录。
