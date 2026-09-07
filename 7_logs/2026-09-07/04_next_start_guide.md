# 2026-09-07 Next Start Guide

## First Action

If BD integration is explicitly requested, copy the relevant project outside `2_fpga` first and modify only that diagnostic copy. Do not edit or regenerate the frozen baseline in place.

## Controlled Next Step

1. Copy the project to `E:\competition\3_workspace` or another user-approved non-frozen location.
2. In the copied project, resolve the old/new module-reference conflict explicitly: either replace `hdmi_out_adv7511` with `hdmi_out_adv7511_v1_0`, or keep both versions as intentionally distinct references.
3. Refresh/compile the source hierarchy, then retry Add Module only in the diagnostic copy.
4. Archive the complete Vivado Tcl/log output under `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN` and link it here.

## Forbidden Immediate Actions

- Do not edit `E:\competition\2_fpga` without a current explicit user authorization naming that exact project.
- Do not interpret the standalone ModelSim PASS as Block Design or board-level acceptance.
- Do not overwrite the existing `display_test_hdmi_out_adv7511_0_0` evidence without preserving a hash/raw backup in an approved evidence directory.

## 08:05 Vivado Recovery Handoff

Before resetting any Vivado run, copy the relevant run directories and `vivado.log` into a new `4_metrics/logs` run folder. Then retry with lower parallelism, disable the Posix spawn parameter for this session, set `HDMI_CLK_0/FREQ_HZ` to 25 MHz, and finally rebuild `display_test_wrapper` rather than the earlier standalone-top synthesis.

## 08:39 Current Status

Batch synthesis and full implementation/bitstream generation are complete and PASS by the recorded criteria. The authoritative new bitstream is `E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.runs\impl_1\display_test_wrapper.bit`, SHA-256 `709873763E75A1D119C69ED3D01768AC6B720B25B2B30A12A3E97D98342F9FD4`.

For the next session, begin with `E:\competition\7_logs\2026-09-07\03_validation_summary.md` and the evidence root `E:\competition\4_metrics\logs\2026-09-07_vivado_full_build_run01`. If hardware display validation is desired, program this exact bitstream through a separate controlled hardware run, then capture board setup, programming log, observed display, and any UART evidence under a new `4_metrics/logs` run before making a board PASS/FAIL claim.

Do not reset `synth_1` or `impl_1`, rerun with the project default high job count, or treat the build PASS as HDMI display acceptance. Do not change the bitstream or BD unless a new named authorization and evidence-backed defect are established.

## 09:10 HDMI/VDMA Approval Gate

The read-only comparison and staged execution plan are complete. Begin the next session at `E:\competition\4_metrics\logs\2026-09-07_hdmi_vdma_review_plan_run01\DESIGN_COMPARISON_AND_PLAN.md`.

The proposed order is:

1. Gate P1: preserve current artifacts, change only Xilinx VTC HSYNC/VSYNC polarity from High to Low, rebuild with safe batch settings, and export a matching XSA.
2. Gate P2: after P1 PASS and explicit approval, write the PS-only VDMA MM2S bring-up code, keep S2MM stopped, correct DDR color order to `B,G,R`, and use three 1 MiB frame slots.
3. Gate P3: program the matching bitstream/ELF and claim board PASS only with stable 640x480p60, correct White/Black/Red/Blue/Green colors, 60-second stability, UART logs, and photograph evidence.
4. Gate P4: reintroduce camera S2MM separately with a non-overlapping buffer.

Until the user approves the plan, do not write PS code, change VTC polarity, start S2MM, program a new board run, or claim HDMI/VDMA display PASS.

## 11:30 PS Rewrite Plan Handoff

Begin with `E:\competition\1_docs\doc\PS_VDMA_HDMI_REWRITE_PLAN.md`. It reflects the current active-low bitstream and the user's pause on PS-code writes. The plan uses only PS changes for this test; no VTC polarity correction or bitstream rebuild is required.

If the user explicitly approves execution, replace only `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, preserving the existing backup and hash. Then compile with full logs, program the recorded `0A9CBC...C271F7` bitstream plus the new ELF, capture UART and photographs for at least 60 seconds, and archive all raw evidence under a new `4_metrics/logs` run.

Forbidden immediate actions: modifying `main.c` without a new explicit instruction, changing PL/BD/VTC/ADV7511 files, rebuilding the bitstream, starting S2MM, combining color and S2MM changes, or calling compile/configuration success a board PASS.

## 11:45 Post-Write Handoff

The first controlled next action is to review or compile `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c` only after the user explicitly requests that next stage. Compilation is not yet performed and must be archived with full logs. A hardware run must separately program the recorded `0A9CBC...C271F7` bitstream plus a newly built ELF, capture complete UART output, verify first frame and 60-second UART no-error, photograph the display, and only then consider board PASS.

Forbidden immediate actions: treating this written source as UART/HDMI PASS, starting S2MM, changing PL/BD/VTC/ADV7511, rebuilding the bitstream, or omitting raw UART/build evidence.

## 11:56 UART Gate Fix Handoff

Begin with `E:\competition\4_metrics\logs\2026-09-07_ps_hdmi_vdma_uart_gate_fix_run01\UART_GATE_FIX_EVIDENCE.md`. The next controlled board run must first show `UART_TEST_PASS` and then `VDMA_INITIAL_BEGIN`. If it stops again, preserve the complete raw UART text and screenshot before changing code.

Do not treat a blank display from the failed run as an MM2S/DDR/PL result. Do not bypass the UART test, start S2MM, change PL/BD, or claim HDMI PASS without the full planned evidence.

## 12:10 MM2S Frame-Store Fix Handoff

Begin with `E:\competition\4_metrics\logs\2026-09-07_ps_hdmi_vdma_fstore_fix_run01\MM2S_FSTORE_FIX_EVIDENCE.md`. The next rebuild should show `UART_TEST_PASS`, `DDR_CLEAR_PASS`, `COLOR_PATTERN_PASS`, and `VDMA_MM2S_CONFIG_PASS`; then first-frame and 60-second checks decide whether another isolated correction is needed.

Do not re-add the disabled MM2S frame-store register access, start S2MM, change PL/BD, or claim HDMI PASS without visible display and raw UART evidence.

## 12:35 Genlock Fix Handoff

Begin with `E:\competition\4_metrics\logs\2026-09-07_hdmi_topline_noise_run01\GENLOCK_FIX_EVIDENCE.md`. Build only `app_component` into a new ELF, keep programming the active bitstream with SHA-256 `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`, and preserve complete UART plus screen photographs in a new raw-evidence folder.

The next UART must show `VDMA_MM2S_GENLOCK MODE=DYNAMIC_SLAVE CONTROL=0x0000008B` and `VDMA_MM2S_CR=0x0001008B`. If the frame counter still stays at 1 while the image remains stalled, stop and archive that result before considering any PL-side change.

Board-level HDMI PASS requires visible White / Black / Red / Blue / Green bars and 60 seconds without visual or VDMA errors. Do not start S2MM, change DDR color encoding, change PL/BD, or treat UART/first-frame success as display PASS.

## 12:40 Authoritative Source Handoff

Use only the final `main.c` snapshot with SHA-256 `D8821C0E236EA1F8CE3A7665A8DCD3719D2C57280B5F92D7388DE46DC8502C72`. Its UART must print `VDMA_MM2S_GENLOCK MODE=DYNAMIC_SLAVE CONTROL=0x0001008B`; `VDMA_MM2S_CR` must read `0x0001008B`. This supersedes any earlier `0x0000008B` expectation in this file.

If CR readback fails at exactly this point, preserve the raw UART and compare bit 16 against the captured baseline before changing anything else. A visible display PASS still requires the full color-bar and 60-second criteria.

## 13:20 Packed RGB888 Fix Handoff

Use only `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `413A1D252FD485241BB3AD0F5DAE7A86B9E6B93F782D8F399BF11005A763451A`. Its banner must be `PS_HDMI_VDMA_V2` and its DDR pass marker must include `FORMAT=PACKED_RGB888`.

Before claiming any display result, preserve complete UART and screen photos under a new raw-evidence run. Check that `PARKPTR` is printed and compare `CURRENT_READ` across heartbeats. Board PASS still requires full White / Black / Red / Blue / Green bars, 60 seconds of no VDMA errors, and unchanged bitstream `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`.

Do not start S2MM, change PL/BD, or reinterpret VDMA/UART-only success as HDMI PASS.

## 14:05 Reference-Style Source Handoff

Use only the current `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `23FBC0B7BE76C71266D10E915FDC315EA13C622455C3C27572EA90668A5031F0`.

Its reference-style flow is now: UART gate -> `VDMA_Reset()` -> packed-RGB888 clear/verify -> `fill_color_bar()`/verify -> `VDMA_Configure_MM2S()` -> first-frame gate -> 60-second gate -> runtime heartbeat. MM2S CR must read `0x0001008B`; S2MM must remain stopped.

The next explicit hardware run must preserve complete UART text and screen photographs in a new `4_metrics/logs` folder. UART or first-frame success alone is not HDMI PASS; full bars and 60 seconds of stable display are required.

Do not compile or program unless separately requested, start S2MM, change PL/BD/VTC/ADV7511, simplify MM2S control to `0x1`, or reuse the 7010 reference addresses.

## 14:20 Padding and MM2S Order Hotfix Handoff

Use only `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `564F340C05A1A583570BF5F0F83420BE6E59B56ED7326C8C67D90DC3E8945745`. This supersedes the 14:05 source hash.

The corrected flow must first show `DDR_CLEAR_PASS` over all 3 MiB. It must then show the color-fill verification, MM2S address/stride/HSIZE/CR/VSIZE readback with `CR=0x0001008B`, first-frame evidence, visible bars, and 60 seconds of stability. Preserve complete UART and photographs in a new evidence folder.

Do not accept the failed padding run as an HDMI result, start S2MM, simplify MM2S control to `0x1`, change PL/BD, or use the 7010 addresses. Compilation and board programming remain separate explicit gates.

## 14:35 Genlock-Disabled Diagnostic Handoff

Use `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `F189857D3D68C6564F4D2C72DFA59C8DF950F08750420CA3671852193DBF43C2`. This supersedes the 14:20 source hash for the next controlled run.

The next UART must show `VDMA_MM2S_GENLOCK MODE=DISABLED_PS_ONLY CONTROL=0x00000003`, then `DDR_CLEAR_PASS`, `COLOR_PATTERN_PASS`, `VDMA_MM2S_CONFIG_PASS`, first-frame evidence, and runtime heartbeats. Save complete UART plus a screen photograph.

If the screen fills, archive it as a PS-only genlock dependency result. If it remains one line, stop before changing FrameDelay or any PL/BD setting. Do not start S2MM, change sync polarity, rebuild PL, or accept UART-only success as HDMI PASS.

## 15:05 Corrected Genlock-Disabled Diagnostic Handoff

Use `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `FE563EA254EE04392B3B839EB9E67FA1B6E4C7C9A14A16013FDC555B15389AE0`. This supersedes the 14:35 source hash.

The next UART must show `VDMA_MM2S_GENLOCK MODE=DISABLED_PS_ONLY CONTROL=0x00010003`, then pass `VDMA_MM2S_CONFIG_READBACK`, first-frame evidence, runtime heartbeats, and visible full-frame bars. Save complete UART plus a screen photograph.

Do not interpret the prior stopped run as evidence that genlock-disabled mode fails. If full-frame display still fails, preserve UART and photos before changing FrameDelay or PL/BD.

## 15:12 Column-Index Fix Handoff

Use only `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `0870D84CBA14D0796C1D00D34EE9CAC9937E70A8F13013EC56FABF96931565F3`. It supersedes the 15:05 source hash for the next run. The expected image is now full-height vertical White / Black / Red / Blue / Green bars.

Rebuild only `app_component`, keep the unchanged bitstream `0A9CBC...C271F7`, and capture complete UART plus a photograph. HDMI PASS requires full-height bars, unchanged PL overlay, 60 seconds of visual and VDMA stability, and archived raw evidence under `E:\competition\4_metrics\logs`.

Do not start S2MM, change PL/BD, alter VTC polarity, or change VDMA control as part of this validation. Treat compile and board programming as separate explicit gates if requested.

## 15:25 Color-Bar Visual Success Handoff

The PS source now displays full-height vertical bars on HDMI. Archive further UART/photo evidence in `E:\competition\4_metrics\logs\2026-09-07_hdmi_colorbar_board_visual_run01`. The photo hash is `C75D56F47FB000841C647E88D218EB350FAEDA120CC401C030661AFD59C6A864`.

Next validation should capture complete UART output and verify `PS_HDMI_VDMA_TEST_PASS`, 60-second heartbeats, and no VDMA error. The observed bar order is White / Black / Blue / Red / Green versus source White / Black / Red / Blue / Green, so keep Red/Blue channel mapping as a separate color-calibration issue.

Do not change the PS pattern logic again for the full-screen issue; do not start S2MM or modify PL/BD during the UART acceptance run.

## 15:50 Camera-Source Handoff

Use only `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `5985897FD476330EEE09B54D2ED27D81AB02BC55EE30A79B4370B6839BCF07C1`. It supersedes the color-bar source for the next run. The source remains PS-only clear followed by S2MM camera capture and MM2S display; the color-bar fill is retained only as legacy fallback code and is not called.

The next board gate must capture complete UART and show, in order:

1. `UART_TEST_PASS`
2. `DDR_CLEAR_PASS`
3. `VDMA_S2MM_CONFIG_PASS`
4. `VDMA_S2MM_FIRST_FRAME_PASS`
5. `VDMA_MM2S_CONFIG_PASS`
6. `VDMA_MM2S_FIRST_FRAME_PASS`
7. 60-second `HDMI_HEARTBEAT` lines with no VDMA errors
8. `PS_HDMI_CAMERA_VDMA_TEST_PASS`

A board PASS additionally requires a live camera image and unchanged PL overlays. Do not change PL/BD or switch back to the color-bar source in the same experiment. The previously observed Red/Blue output swap remains a separate color-calibration issue.

## 16:57 Camera S2MM FSYNC Fix Handoff

Use `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `39FE691B3C5113B137A744E77EB6D6BE3D5A0BD30B12C7FF97933B463D42BBA4`, and ELF SHA-256 `C44A8DC5C9D5CA1C1AB49893F535776E0A4BC9AD5B9E409F4CB9965A612DA8FC`.

The next UART must show `VDMA_S2MM_CONFIG_PASS`, `VDMA_S2MM_FIRST_FRAME_PASS` with PARKPTR movement, `VDMA_MM2S_CONFIG_PASS`, `VDMA_MM2S_FIRST_FRAME_PASS`, 60 seconds of heartbeats, and `PS_HDMI_CAMERA_VDMA_TEST_PASS`. A camera-display PASS additionally requires a live image and archived photographs. If it times out, `VDMA_S2MM_WARN REASON=CAMERA_STREAM_TIMEOUT` must remain visible while MM2S starts; that is not a camera PASS.

Do not modify PL/BD, regenerate the bitstream, reinterpret a timeout as PASS, or restore the invalid SR [1:0] S2MM error mask. Treat the Red/Blue visual swap separately after camera geometry is stable.

## 17:03 Camera J5 Constraint Audit Handoff

Read `E:\competition\4_metrics\logs\2026-09-07_camera_j5_constraint_audit_run01\CAMERA_J5_CONSTRAINT_AUDIT.md` before any camera rebuild. The data/timing/SCCB mapping is correct, but J5-29/J5-30 RST/PWDN are unconstrained. Do not assume the OV5640 starts without verified idle states.

The smallest next check is to measure or otherwise verify RST=high and PWDN=low on the adapter. If not, the authorized PL change should add two LVCMOS33 outputs at T22/U22, drive them from a controlled reset sequence, then rebuild only after preserving the current bitstream evidence. Do not change data pins or PL timing based on this audit.

## 17:12 Reference Constraint Audit Handoff

Read `E:\competition\4_metrics\logs\2026-09-07_reference_camera_constraint_audit_run01\REFERENCE_CAMERA_CONSTRAINT_AUDIT.md` before citing the successful reference project. It confirms camera data/timing/SCCB constraints exist, but has no camera RST/PWDN evidence and uses a different Zynq package.

Do not copy any reference pin into the current 7020 project. Treat the unresolved J5-29/J5-30 RST/PWDN idle levels as the highest-priority camera bring-up gate before another PS-only experiment is interpreted as a camera-stream failure.

## 17:35 Startup-Clear Run Handoff

Use `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `91B77688A6B360F85B38D0CA6A5ABA61A4649092A6F3A1BC38A22CCC080A1C4A`, and ELF SHA-256 `5E44F54434AD55CB8AC904A5F92F5118ADF34F2CED94770D21E3B8AADC9C34D1`.

The next UART must contain `VDMA_S2MM_STARTUP_CLEAR BEFORE=0x00014810 AFTER=0x00000000` or another clean post-clear value, then `VDMA_S2MM_CONFIG_PASS`, `VDMA_S2MM_FIRST_FRAME_PASS`, `VDMA_MM2S_CONFIG_PASS`, 60-second heartbeats, and an archived live-camera photo for display PASS.

If `AFTER` contains any bit in `0x00000FF0`, or the same SOF/internal errors return before first frame, stop PS-only experiments. Preserve the full UART, then capture S_AXIS S2MM `TVALID/TREADY/TLAST/TUSER` with ILA to measure actual frame geometry. Do not change PL/BD or RST/PWDN in this experiment.

## 17:55 HDMI Keep-Alive Handoff

Use `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `5B33C92AA2F8DF71194F010A8D25C598B17E45B3C5C9C85E86A229BF98FF6525`, and ELF SHA-256 `145637D81FBFFC11245569BA2BB8F37A980B0FB6849F81CDA60938F784E3DC39`.

The expected diagnostic minimum is `VDMA_MM2S_CONFIG_PASS`, `VDMA_MM2S_FIRST_FRAME_PASS`, repeated `CAMERA_STREAM_FAIL`, and a locked HDMI signal/black image. A locked signal with persistent `S2MM_SR=0x00014810` proves the failure is isolated to the camera AXIS-to-S2MM geometry/TUSER path. A camera PASS still requires `VDMA_S2MM_FIRST_FRAME_PASS`, 60 seconds of `CAMERA_OK=1`, and an archived live image.

If MM2S passes and HDMI remains no-signal, stop changing S2MM/PS data code and inspect the MM2S-to-video-out clock/timing chain. If HDMI shows black while S2MM fails, preserve UART/photo and then use ILA on S2MM AXIS `TVALID/TREADY/TLAST/TUSER` to measure actual frame length.

## 18:05 Exact Reference Sequence Handoff

Use `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `A91FFA133BFC54092AAA06DA78D94A990F0ABB2840D2329DB3D7883F9D665A10`, and ELF SHA-256 `1AC1F422878A277D5E7DB7A53FD9A4A9EA6289F552334D80C19C3D2129A800F2`.

The next UART must show `VDMA_S2MM_REFERENCE_SEQUENCE_DONE`, then either `VDMA_S2MM_FIRST_FRAME_PASS` with `CAMERA_OK=1`, or `VDMA_S2MM_FIRST_FRAME_FAILED_KEEPING_HDMI` with a locked HDMI signal. Do not add startup-clear/readback/status gating back during this run.

## 18:02 Clean Warning Build Handoff

Use `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `78A0AA9F9D4801F8941DCB64B6F9E522FA71A64F50BC8BF0AC52C75413B1F738`, and ELF SHA-256 `BDD215B823C9AEBBAE33E5B373CB8576EF5E318F2B250BC51FACCA1021604A47`. This is the exact-reference S2MM sequence build with retired color-bar code removed.

Expected next evidence remains `VDMA_S2MM_REFERENCE_SEQUENCE_DONE`, first-frame/MM2S gates, 60-second `CAMERA_OK` status, and an archived live HDMI photo for a display PASS.

## 18:10 Known-Good Color-Bar A/B Handoff

First program only the archived bitstream at `E:\competition\4_metrics\logs\2026-09-07_hdmi_topline_noise_run01\display_test_wrapper_active.bit`, SHA-256 `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`. Then run only `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\build\app_component.elf`, SHA-256 `C99A1D8A9567B27B317D9B3D152F10249E4361769CEAECC71FECB8AFA233EF3B`.

Expected UART is `PS_HDMI_VDMA_V2`; expected display is full-height color bars. Archive the complete UART and a screen photograph under a new evidence folder. If this exact pair restores HDMI, resume camera S2MM only afterward. If it still has no signal, do not blame camera PS code; inspect programming, HDMI cable/input, board reset/power, or downstream video output.

Do not program the current default platform bit, SHA-256 `E7950A1A038BA4E7640FFEA9BCF5CDD88888F8ACD2EBD0E59CDBDC8FEC4B5FDC`, during this A/B. Do not change PL/BD/XDC, camera constraints, S2MM logic, or the restored source in this experiment.

## 18:18 Camera Retry With Manual Reset Handoff

Use the archived bitstream `E:\competition\4_metrics\logs\2026-09-07_hdmi_topline_noise_run01\display_test_wrapper_active.bit`, SHA-256 `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`, and the camera ELF `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\build\app_component.elf`, SHA-256 `BDD215B823C9AEBBAE33E5B373CB8576EF5E318F2B250BC51FACCA1021604A47`.

After programming, run the ELF and perform the manual reset now known to be required for HDMI output. Archive complete UART and a screen photo. Camera PASS requires `VDMA_S2MM_FIRST_FRAME_PASS`, `VDMA_MM2S_FIRST_FRAME_PASS`, `PS_HDMI_CAMERA_VDMA_TEST_PASS`, a live image, and 60 seconds without errors.

If `S2MM_FIRST_FRAME_STATUS SR=0x00014810` still appears, preserve the complete UART and photo and treat that as a separate camera AXIS-to-S2MM failure. Do not alter PL/BD/XDC, the bitstream, source, frame buffers, or constraints before reviewing that evidence.

## 18:35 Camera Dynamic Genlock Handoff

Use archived bit `E:\competition\4_metrics\logs\2026-09-07_hdmi_topline_noise_run01\display_test_wrapper_active.bit`, SHA-256 `0A9CBC...C271F7`, plus new ELF `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\build\app_component.elf`, SHA-256 `5C9246...98C65`. Program, run, perform manual reset, then archive complete UART and screen photos.

The next UART must show `MODE=DYNAMIC_MASTER CONTROL=0x000180CB`, `MODE=DYNAMIC_SLAVE CONTROL=0x0001008B`, no `S2MM_SR` error, and 60 seconds without `CAMERA_STREAM_FAIL`. If flicker is eliminated but color/noise remains, stop before more S2MM changes and open the separate PL issue: XDC says `cam_pclk=24.038 MHz` while OV5640 registers configure about `51 MHz`. A PL/XDC change and bit rebuild require explicit authorization and must be a new isolated experiment.

## 18:50 Clock Tree Audit Handoff

First read `E:\competition\4_metrics\logs\2026-09-07_reference_clock_tree_audit_run01\REFERENCE_CLOCK_TREE_AUDIT.md`. The 2020 clock-tree format is valid and is not the primary root-cause suspect. Do not make another PS-only S2MM timing change while recognizable but striped camera data is present.

The smallest next PL-only experiment, requiring explicit authorization, is to change only AXI VDMA `S2MM Line Buffer Depth` from `512` to `1024`, matching the proven 2020 project. Keep clocks, XDC, OV5640 registers, capture RTL, frame buffers, and PS VDMA controls unchanged; then validate BD, rebuild PL, export XSA, and archive UART plus live photos.

## 19:05 Color Format Chain Handoff

First read `E:\competition\4_metrics\logs\2026-09-07_camera_color_format_chain_audit_run01\CAMERA_COLOR_FORMAT_CHAIN_AUDIT.md`. The current ADV7511 path intentionally converts RGB888 to YCbCr422 and is board-proven for the synthetic output. Do not label its active settings as RGB444 based on stale comments, and do not change ADV7511 format in the line-buffer experiment.

After `S2MM Line Buffer Depth=1024` stabilizes geometry, run a separate color-only experiment if distortion remains. Preserve exact UART/photos and change only one of: RGB565 channel mapping, RGB888 channel mapping, BT.601/full-range CSC coefficients, or ADV7511 AVI/output metadata. A camera PASS requires stable geometry plus acceptable live color.

## 19:40 Consolidated Error Report Handoff

Start with `E:\competition\1_docs\摄像头采集显示错误分析报告_2026-09-07.md`. Its first hardware action is zero-change: run the current dynamic Genlock ELF against the archived BIT, perform manual reset, and capture complete UART plus photos. Do not claim PASS without full UART.

If tearing/flicker persists after that UART evidence, use the report's isolated PL gate: only change AXI VDMA `S2MM Line Buffer Depth` from `512` to `1024`, then rebuild and retest. Keep PCLK and color-format changes out of that experiment.

## 21:12 Sync Polarity Recovery Handoff

First restore only the two `pix_frame_dispaly.v` synchronization assignments to `hdmi_hsync <= ~vio_hsync;` and `hdmi_vsync <= ~vio_vsync;`. Keep the new `S2MM Line Buffer Depth=1024` unchanged. Then regenerate the module, rebuild PL/XSA, program BIT, run ELF, manually reset, and capture UART/photos.

Do not change XDC, OV5640, ADV7511, or PS VDMA controls in this recovery. If HDMI signal returns, judge camera geometry against line-buffer 1024 separately from color.

## 21:55 Frozen Camera HDMI Baseline Handoff

First read `E:\competition\4_metrics\logs\2026-09-07_camera_display_success_freeze_run01\CAMERA_DISPLAY_SUCCESS_FREEZE_REPORT.md`. This exact BIT `16DBACBF...29130624` plus ELF `040B57D0...93BDD990` is the recoverable `BOARD_VISUAL_PASS` baseline; always run it through the recorded program/load/manual-reset sequence.

The next useful action is a zero-change formal UART run using the same frozen BIT and ELF. Archive complete serial text for the entire startup and at least 60 seconds. Only after that evidence passes may the result be called `FULL_UART_ACCEPTANCE_PASS`; otherwise retain visual PASS and record the UART failure.

Forbidden immediate actions: editing the frozen source/artifacts, rebuilding the platform, changing S2MM/MM2S controls, sync polarity, line-buffer depth, XDC, or color formatting, and describing the current photos as full UART acceptance. Use a new branch/evidence run for any future experiment.
