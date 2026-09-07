# 2026-09-07 Validation Summary

## Verified Facts

- `hdmi_out_adv7511_v1_0.v` defines one 13-port module and closes with `endmodule`.
- The project XPR marks this file, its HDL dependencies, and the old `hdmi_out_adv7511.v` as `AutoDisabled = 1` while the active synthesis top is `display_test_wrapper`.
- `display_test.bd` already contains `xilinx.com:module_ref:hdmi_out_adv7511:1.0`, instance `hdmi_out_adv7511_0`, backed by `display_test_hdmi_out_adv7511_0_0.xci`.
- The new module name is `hdmi_out_adv7511_v1_0`; the existing BD module reference is the old name `hdmi_out_adv7511`.
- Raw evidence from `E:\competition\4_metrics\logs\2026-09-06_hdmi_out_adv7511_v1_0_top_run01\modelsim_transcript.txt` shows compilation of `hdmi_out_adv7511_v1_0` and natural completion at 1260 ns.

## Assessment

The immediate Vivado prompt is best explained by the project-context/module-reference mismatch: the new RTL is visible under the simulation hierarchy but is AutoDisabled from the active synthesis hierarchy, while the BD still owns an old module-reference IP. Vivado's Add Module operation cannot resolve this as an additive module reference in the frozen project context.

## PASS/FAIL Criteria

Not applicable for this read-only diagnosis. A subsequent BD integration attempt is PASS only if the new module appears as a separate module-reference block, generation/synthesis logs are captured under `4_metrics/logs`, and validation reaches natural completion without treating an interrupted run as PASS.

## Evidence Links

- `E:\competition\4_metrics\logs\2026-09-06_hdmi_out_adv7511_v1_0_top_run01\modelsim_transcript.txt`
- `E:\competition\4_metrics\logs\2026-09-06_hdmi_out_adv7511_v1_0_top_run01\validation_report.md`

## 08:05 Vivado Run-State Review

- Historical OOC `Common 17-1257` errors completed successfully afterward; current spawn issue was retried and completed.

## 08:39 Batch Synthesis Recovery

**PASS.** The historical screenshot OOC `Common 17-1257` errors were stale state; the relevant actionable blocker was `Common 17-180 Spawn failed`. Using Vivado 2025.2 batch mode, `general.usePosixSpawnForFork=0`, disabled cluster monitoring, and `-jobs 1` avoided the spawn failure.

The recovery top was checked as `display_test_wrapper`. `synth_1` reset and rebuild completed naturally with `POST_STATUS=synth_design Complete!`, `POST_PROGRESS=100%`, `POST_NEEDS_REFRESH=0`, `__synthesis_is_complete__`, and `display_test_wrapper.dcp` present.

The successful synthesis log reports 0 errors, 1 critical warning, and 28 warnings. The critical warning says the imported incremental synthesis reference DCP is unsuitable; Vivado continued with the default flow, so this is not a synthesis failure.

## 08:39 Full Build Verification

**PASS for implementation and bitstream generation; this is not yet HDMI display board acceptance.** PASS criteria required Vivado exit code 0, `FULL_BUILD_TCL_PASS`, `POST_IMPL_STATUS=write_bitstream Complete!`, `POST_IMPL_PROGRESS=100%`, `POST_IMPL_NEEDS_REFRESH=0`, an existing `display_test_wrapper.bit`, timing constraints met, and zero routing errors. All criteria were met.

- Vivado command: `F:\vivado2025\2025.2\Vivado\bin\vivado.bat -mode batch -source E:\competition\4_metrics\logs\2026-09-07_vivado_full_build_run01\run_full_build.tcl`.
- `HDMI_CLK_0` was queried during the build and reported `CONFIG.FREQ_HZ=25000000`, confirming the user setting.
- Implementation child log has completed markers for `link_design`, `opt_design`, `place_design`, `phys_opt_design`, `route_design`, and `write_bitstream`; it contains no `ERROR:` or `CRITICAL WARNING:` lines.
- Routed timing summary: WNS +10.277 ns, TNS 0.000 ns, WHS +0.037 ns, THS 0.000 ns; `All user specified timing constraints are met.`
- Route status: 11060 of 11060 routable nets fully routed and 0 nets with routing errors.
- Pre-bitstream and routed DRC execution reported 0 errors; routed DRC/methodology warning checks must not be interpreted as errors.
- Workspace path audit `E:\competition\4_metrics\scripts\audit_project_skill_paths.ps1` returned `pass: true`.

Evidence root: `E:\competition\4_metrics\logs\2026-09-07_vivado_full_build_run01`. Key evidence is `run_full_build.tcl`, `vivado_full_build.log`, `post_recovery_logs\synth_1\runme.log`, `post_build_outputs\impl_1\`, and `sha256_manifest.txt`.

Production bitstream: `E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.runs\impl_1\display_test_wrapper.bit`; SHA-256 `709873763E75A1D119C69ED3D01768AC6B720B25B2B30A12A3E97D98342F9FD4`.

## 09:10 HDMI/VDMA Design Review

This was a read-only comparison, not a board test. The user's architecture statement is accepted with one boundary correction: the current BD has both PS-readable display memory through VDMA MM2S and camera capture through VDMA S2MM. A PS-only display test must keep S2MM stopped so it cannot overwrite the PS frame buffer.

Confirmed architecture:

`PS DDR -> VDMA MM2S -> AXI-Stream -> v_axi4s_vid_out -> pix_frame_display -> hdmi_out_adv7511_v1_0 -> ADV7511`

The current design also contains `OV5640 -> v_vid_in_axi4s -> VDMA S2MM -> PS DDR`.

Key comparison results:

- The 2026-09-06 board PASS used `hdmi_colorbar_vtc_top`, 640x480p60, 25 MHz pixel clock, RGB888 to limited-range BT.601 YCbCr422, active-low HSYNC/VSYNC, the EES-331 physical byte swap, and negative-edge HDMI output registration.
- The current Xilinx VTC has 480p geometry matching the hand-written VTC: H 640/800 and V 480/525.
- The current VTC explicitly reports `GEN_HSYNC_POLARITY=High` and `GEN_VSYNC_POLARITY=High`; this differs from the successful active-low timing and is the primary proposed PL correction.
- Current VDMA register base is `0x43000000`; FCLK_CLK0 is 50 MHz and the HDMI pixel clock is 25 MHz.
- A 640x480 RGB888 frame is 921,600 bytes; the existing 1 MiB frame-slot spacing is sufficient for three buffers.
- The existing PS app uses display base `0x10000000`, resets S2MM, and already has a VDMA MM2S bring-up skeleton. It should not be accepted as HDMI PASS until rebuilt and tested with corrected color-byte order and explicit UART/board evidence.
- The current converter expects `RGB888 = {R,G,B}` from MSB to LSB. VDMA memory reaches AXI-Stream from the lowest DDR byte to `RGB888[7:0]`, so PS should encode 32-bit writes as `0x00RRGGBB` to produce DDR bytes `B,G,R`. The existing colorbar fill should be corrected before board display testing.

Review status: **review complete; no PL/PS implementation PASS is claimed.** The proposed plan and evidence are at `E:\competition\4_metrics\logs\2026-09-07_hdmi_vdma_review_plan_run01\DESIGN_COMPARISON_AND_PLAN.md`; provenance clarification is in `PROVENANCE_ADDENDUM.md`, and reviewed-input hashes are in `sha256_review_inputs.txt`. The plan is awaiting user approval before Gate P1 or PS code.

## 11:30 PS Rewrite Plan Documentation

This was a documentation and evidence check, not a compile, hardware, or display test.

Verified facts:

- Current `display_test_wrapper.bit` SHA-256 is `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`.
- Current VTC XCI records `GEN_HSYNC_POLARITY=Low` and `GEN_VSYNC_POLARITY=Low`; this supersedes the earlier proposed polarity correction.
- `main.c` and `main_pre_ps_hdmi_vdma.c` both have SHA-256 `4AC73C2C9C4C8B1D6273F08F3CAC6FF608AAE90B1BD0F330FA22A424ACA87B79`; `main.c` remains unchanged.
- The PS rewrite plan is `E:\competition\1_docs\doc\PS_VDMA_HDMI_REWRITE_PLAN.md`, SHA-256 `A80B9A5DCE3E70F94E9CC7A40E0AC8DFBD9F4C346525A4BE3B746AA90C723F86`.

The plan defines full clearing and readback of `0x10000000..0x102FFFFF`, three 1 MiB frame slots, 640x480 RGB888 with DDR bytes `B,G,R`, MM2S FRMSTORE/address/stride/HSIZE/VSIZE setup, VSIZE-last start, S2MM stopped, first-frame checks, and a 60-second no-error criterion.

Status: **PS rewrite plan complete; no PS code, compile, board run, or HDMI PASS is claimed.**

## 11:45 PS Code Written

**Status: implementation written only; no compile, hardware run, UART PASS, first-frame PASS, or HDMI display PASS is claimed.**

Verified facts:

- Pre-change `main.c` SHA-256 was `4AC73C2C9C4C8B1D6273F08F3CAC6FF608AAE90B1BD0F330FA22A424ACA87B79`, matching `main_pre_ps_hdmi_vdma.c`.
- Post-change `main.c` SHA-256 is `11754557F07AA3A379038967DD1E8EE1723ADDC392716BF9F928ADE022E28A5E`.
- Post-change snapshot: `E:\competition\4_metrics\logs\2026-09-07_ps_hdmi_vdma_run01\main_post_ps_hdmi_vdma.c`.
- Evidence record: `E:\competition\4_metrics\logs\2026-09-07_ps_hdmi_vdma_run01\PS_CODE_EVIDENCE.md`.
- The implementation contains the expected gating markers: `UART_TEST_PASS`, `DDR_CLEAR_PASS`, `COLOR_PATTERN_PASS`, `VDMA_MM2S_CONFIG_PASS`, `VDMA_MM2S_FIRST_FRAME_PASS`, `VDMA_MM2S_NO_ERROR_60S`, `PS_HDMI_VDMA_TEST_PASS`, and `HDMI_PS_SOURCE_RUNNING`.
- Failure paths print `DDR_FAIL`, `VDMA_RESET_FAIL`, `VDMA_S2MM_FAIL`, `PS_HDMI_VDMA_FAIL`, and full VDMA register sets where applicable.
- The active bitstream remains unchanged at SHA-256 `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`.

## 11:56 UART Gate Failure and 12:00 Source Fix

**Board result: FAIL to reach HDMI/VDMA bring-up because the UART gate stopped execution.** The screenshot shows `UART_SELFTEST` reached the terminal, so UART communication itself worked. It also shows `UART_TEST_FAIL REASON=TX_NOT_EMPTY SR=0x00002802`, so firmware stopped before `VDMA_INITIAL_BEGIN`; HDMI blank at that moment is expected and is not evidence of an MM2S, DDR, or PL fault.

`SR=0x00002802` contains TX trigger active (`0x2000`), TX active (`0x0800`), and RX FIFO empty (`0x0002`). The prior TX-empty poll had no delay and could time out before the 115200 baud token left the shifter.

Corrected `main.c` SHA-256 is `2E09F1DBA505BBD5D765C5395FD020D4D484164136E0B604F03535C96363FE70`. Evidence and corrected snapshot are at `E:\competition\4_metrics\logs\2026-09-07_ps_hdmi_vdma_uart_gate_fix_run01\UART_GATE_FIX_EVIDENCE.md`; the raw screenshot is in the same run folder. No compile or corrected board run has been performed.

## 12:10 MM2S Frame-Store Register Fix

**Prior board run: PASS through UART gate, DDR clear, and three-frame color source readback; FAIL at `MM2S_CONFIG_READBACK`.** The key readback was `FRMSTORE=0x00000000` even though the code wrote 3. This is not an image or DDR failure.

The VDMA XCI has `C_NUM_FSTORES=3` and `C_ENABLE_DEBUG_INFO_5=0`. The BSP maps `Mm2SFrmStoreRegEn` to debug info 5, so the MM2S frame-store register is disabled and returns zero. The hardware frame count is fixed at 3.

Corrected `main.c` SHA-256 is `F36CED4B897BB164D57FA3563E0AB0A4A28BFF9730AF71F3B73863455A1DD62D`. Evidence and snapshot are at `E:\competition\4_metrics\logs\2026-09-07_ps_hdmi_vdma_fstore_fix_run01\MM2S_FSTORE_FIX_EVIDENCE.md`. No compile or corrected hardware run is claimed.

## 12:35 Top-Line Noise Board Result and Genlock Source Fix

**Board result: FAIL for HDMI display acceptance.** The monitor locked to timing, but showed only one noisy top line and remained black elsewhere. Raw evidence is at `E:\competition\4_metrics\logs\2026-09-07_hdmi_topline_noise_run01\`.

The newer UART capture proves the prior run reached:

```text
UART_TEST_PASS SR=0x0000080A
DDR_CLEAR_PASS BASE=0x10000000 BYTES=3145728
COLOR_PATTERN_PASS FRAMES=3 PIXELS=921600 BYTES=2764800
VDMA_MM2S_CONFIG_PASS WIDTH=640 HEIGHT=480 STRIDE=1920 FRAMES=3
VDMA_MM2S_FIRST_FRAME_PASS SR=0x00011000 COUNT=1
VDMA_MM2S_NO_ERROR_60S FRAMES=1 SR=0x00011000
```

Heartbeats continued with `FRAMES=1`, so UART-only no-error is not display PASS. The MM2S XCI has `C_MM2S_GENLOCK_MODE=3`, dynamic genlock slave. The old control word `0x3` omitted genlock enable and internal genlock source. The corrected control word is `0x8B` (`RUN | CIRCULAR | GENLOCK_ENABLE | GENLOCK_INTERNAL`).

Changed source is `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`, SHA-256 `1665C94BD7268E0E920A938FE8B59059861FA971D438F06AFDD81893D3D32264`. Pre-change source remains hash `F36CED4B897BB164D57FA3563E0AB0A4A28BFF9730AF71F3B73863455A1DD62D`. The active bitstream was copied and remains SHA-256 `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`.

Static checks found no whitespace errors and balanced braces; no host compiler or Vitis compile was available/authorized for this step. Detailed report: `E:\competition\4_metrics\logs\2026-09-07_hdmi_topline_noise_run01\GENLOCK_FIX_EVIDENCE.md`.

Hash correction for 12:35 section: the authoritative measured `main.c` SHA-256 is `1665C94BD7268E0E920A938FE8D111000DE660F9B7C5F4CF5642B5A20847E10C`; ignore the earlier transcription typo in the same section.

## 12:40 Authoritative Genlock/Count-Bit Source Revision

Cross-checking the captured `MM2S_CR=0x00010003` shows control bit 16 is present in the normal readback. The source was revised to include frame-count value one plus the two missing genlock controls. The authoritative control/readback target is now `0x0001008B`.

Authoritative `main.c` SHA-256 is `D8821C0E236EA1F8CE3A7665A8DCD3719D2C57280B5F92D7388DE46DC8502C72`. This supersedes the two intermediate hash notes above. Evidence report and `main_after_genlock_fix.c` are updated in `E:\competition\4_metrics\logs\2026-09-07_hdmi_topline_noise_run01\`. No compile or board rerun is claimed.

## 13:20 Overlay-OK / VDMA Data-FAIL and Packed RGB888 Fix

**Board result: FAIL for HDMI display acceptance.** The new screen evidence shows the PL center frame and right-top white block are correct, so timing/overlay are visible, but the PS color-bar source is not displayed. The prior `COLOR_PATTERN_PASS` is now classified as a false CPU-side pass caused by treating RGB888 as one 32-bit word per pixel.

Confirmed defect: `fill_color_pattern()` wrote `uint32_t` per pixel while VDMA consumes a continuous 3-byte packed RGB888 stream. DDR became a repeating `B,G,R,00` sequence, so every three-byte VDMA read crossed the 4-byte cycle. The old verifier repeated the same assumption.

Corrected `main.c` now writes/verifies packed RGB888 bytes and prints `PARKPTR` / current-read-frame diagnostics. Authoritative post-fix SHA-256 is `413A1D252FD485241BB3AD0F5DAE7A86B9E6B93F782D8F399BF11005A763451A`; pre-fix source is `D8821C0E236EA1F8CE3A7665A8DCD3719D2C57280B5F92D7388DE46DC8502C72`. Evidence root: `E:\competition\4_metrics\logs\2026-09-07_hdmi_overlay_ok_packed_rgb888_fix_run01`.

No compile, board rerun, UART PASS, or HDMI display PASS is claimed. The active bitstream remains `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`.

## 14:05 Reference-Style Code Alignment

**Status: code written only. No compile, hardware run, UART PASS, or HDMI PASS is claimed.**

The user-supplied 7010 reference functions were used as flow provenance only. The active source now contains reference-style `VDMA_Reset()`, `Clear_FrameBuffer()`, `fill_color_bar()`, and `VDMA_Configure_MM2S()` while retaining this project's current address map and genlock control.

Verified static facts:

- Current `main.c` SHA-256: `23FBC0B7BE76C71266D10E915FDC315EA13C622455C3C27572EA90668A5031F0`.
- VDMA base is `0x43000000`; framebuffer is `0x10000000`; slots are `0x10000000`, `0x10100000`, `0x10200000`; stride is 1920 bytes.
- `Clear_FrameBuffer()` and `fill_color_bar()` write continuous packed RGB888 using `pixel * 3` byte offsets.
- `VDMA_Reset()` waits for both reset bits to self-clear and checks that MM2S/S2MM are stopped.
- `VDMA_Configure_MM2S()` writes CR, addresses, stride, HSIZE, then VSIZE last; control/readback target remains `0x0001008B`.
- `git diff --check` passed and brace balance is 72/72.

Snapshot and report: `E:\competition\4_metrics\logs\2026-09-07_reference_style_ps_vdma_code_run01\REFERENCE_STYLE_CODE_EVIDENCE.md`.

This revision is not board evidence. The active bitstream remains `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`.

## 14:20 No-Signal UART FAIL and Source Hotfix

**Board result: FAIL before MM2S configuration.** Two runs reproduced the same gate:

```text
DDR_FAIL STEP=CLEAR ADDR=0x100E1000 FRAME=0 BYTE_OFFSET=921600 EXP=0x00 ACT=0x78
```

The offset 921600 is exactly the end of active 640x480 packed RGB888 and the start of unused padding in the 1 MiB slot. The refactored `Clear_FrameBuffer()` cleared only active pixels while the verifier correctly checked all 3 MiB, so stale padding stopped execution. This is a source defect, not a DDR failure.

The no-signal observation also caused reversion of CR-first MM2S setup. The source now returns to this project's earlier signal-locked order: addresses 1/2/3, stride, HSIZE, CR `0x0001008B`, VSIZE last.

Authoritative post-hotfix `main.c` SHA-256 is `564F340C05A1A583570BF5F0F83420BE6E59B56ED7326C8C67D90DC3E8945745`. Evidence and snapshots are in `E:\competition\4_metrics\logs\2026-09-07_no_signal_mm2s_order_hotfix_run01`. Static checks passed with brace balance 73/73 and clean `git diff --check`.

No compile, corrected board run, UART PASS, or HDMI PASS is claimed. The bitstream remains `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`.

## 14:35 First-Row Color Bars and Genlock Isolation

**Board result: partial progress, HDMI FAIL.** The photo shows locked 640x480 timing and correct PL overlay across multiple lines, but the PS color bars occupy only the first active line. This is not consistent with HSYNC/VSYNC polarity failure; it points to the PS-source/VDMA path.

The MM2S IP is configured `C_MM2S_GENLOCK_MODE=3` (dynamic genlock slave), while the PS-only test intentionally keeps S2MM stopped. The previous `GenlockEn=1` setting therefore depends on an absent internal master. A one-variable PS diagnostic now changes MM2S control from `0x0001008B` to `0x00000003` (`RUN | CIRCULAR`, genlock disabled).

Current `main.c` SHA-256 is `F189857D3D68C6564F4D2C72DFA59C8DF950F08750420CA3671852193DBF43C2`. Evidence and photo: `E:\competition\4_metrics\logs\2026-09-07_ps_only_genlock_disabled_run01`. No compile, board rerun, or HDMI PASS is claimed; the next UART must identify `VDMA_MM2S_GENLOCK MODE=DISABLED_PS_ONLY CONTROL=0x00000003`.

## 15:05 Genlock-Diagnostic Readback Correction

**Board result: FAIL due to a false source-side readback gate, not a genlock result.** The UART reached `DDR_CLEAR_PASS` and `COLOR_PATTERN_PASS`, then failed because hardware CR readback was `0x00010003` while the temporary diagnostic expected `0x00000003`. CR bit 16 is the IP's retained `IRQFrameCount=1` value; `FrameCntEn` is not enabled.

Because the fail branch stopped MM2S/S2MM, HDMI had no source and the genlock-disabled experiment was not actually evaluated. The source now expects `CONTROL=0x00010003` with `GenlockEn=0`.

Corrected `main.c` SHA-256 is `FE563EA254EE04392B3B839EB9E67FA1B6E4C7C9A14A16013FDC555B15389AE0`. Evidence is in `E:\competition\4_metrics\logs\2026-09-07_ps_only_genlock_disabled_run01`. No compile, corrected board run, or HDMI PASS is claimed.

## 15:12 Vertical Color-Bar Column Index Fix

**Root cause confirmed in the PS pattern generator, and source fix written only.** `fill_color_bar()` previously selected a color from the global linear pixel index. With 128-pixel bars, row 0 spans indices 0..639 and exactly covers cases 0..4; row 1 begins at index 640, selects nonexistent case 5, and enters the black default. Thus rows 1..479 were correctly sent as black.

The fill and independent byte verifier now use `color_for_column(column)`, where the verifier reconstructs `column = (offset / 3) % 640`. Post-fix `main.c` SHA-256 is `0870D84CBA14D0796C1D00D34EE9CAC9937E70A8F13013EC56FABF96931565F3`; before hash was `FE563EA254EE04392B3B839EB9E67FA1B6E4C7C9A14A16013FDC555B15389AE0`. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_color_column_fix_run01`.

Static checks passed with brace balance 73/73 and clean source diff whitespace. No compile, board run, UART PASS, or HDMI display PASS is claimed. The active bitstream remains `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`.

## 15:25 Full-Screen Color-Bar Board Visual Result

**Visual test SUCCESS after the column-index fix.** The board photo shows full-height color bars and the existing PL center rectangle plus right-top white block. This establishes that the PS DDR -> VDMA MM2S -> AXI-Stream -> Video Out -> HDMI display chain is functional.

Photo evidence: `E:\competition\4_metrics\logs\2026-09-07_hdmi_colorbar_board_visual_run01\board_fullscreen_colorbars.jpg`, SHA-256 `C75D56F47FB000841C647E88D218EB350FAEDA120CC401C030661AFD59C6A864`.

Observed color order is White / Black / Blue / Red / Green, while the source pattern currently encodes White / Black / Red / Blue / Green. Therefore the visual geometry/fill PASS is accepted, but Red and Blue are swapped somewhere in the output color mapping (possibly the known board-level physical byte swap or YCbCr conversion path). A complete HDMI acceptance still needs the UART log showing no VDMA error for 60 seconds and a stable photograph.

## 15:50 Camera-Source PS Code Revision

**Status: code written only; no compile, board run, UART PASS, or camera display PASS is claimed.** The current Vitis source was revised from PS color-bar source to OV5640 camera source using the current project's address map and the reference direct-register logic.

The code now uses S2MM at `0x43000000 + 0xA0/0xA4/0xA8/0xAC/0xB0/0xB4` with HSIZE 1920, VSIZE 480, stride 1920, and the same three 1 MiB frame slots as MM2S. The startup order is UART self-test -> reset both channels -> clear/verify 3 MiB -> S2MM first frame -> MM2S first frame -> 60-second dual-channel monitor -> runtime heartbeat. The S2MM-specific error mask `0x0000000F` is also checked.

Post-change `main.c` SHA-256 is `5985897FD476330EEE09B54D2ED27D81AB02BC55EE30A79B4370B6839BCF07C1`; before hash was `0870D84CBA14D0796C1D00D34EE9CAC9937E70A8F13013EC56FABF96931565F3`. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_camera_source_vdma_code_run01`. Static checks passed with brace balance 84/84 and clean source diff whitespace.

## 16:57 Camera S2MM FSYNC Fix and Build Result

**Board result: FAIL, as supplied by the user.** The UART reached `VDMA_S2MM_CONFIG_PASS` but then stopped at `PS_HDMI_VDMA_FAIL STEP=S2MM_CONFIG_STATUS`; `S2MM_SR=0x00014810` contains SR bit 4 (Internal Error) and bit 11 (Frame Size More Mismatch). The source stopped before MM2S, so HDMI had no display source. This is a real S2MM gate, not a UART-only false failure.

Root cause in PS code: the current VDMA XCI sets `C_USE_S2MM_FSYNC=2`, meaning the S2MM must select AXIS TUSER as its frame-sync source. The prior control word omitted CR bits [6:5]=`10`, so successive camera frames triggered frame-size mismatch. The source also incorrectly treated SR HALTED/IDLE bits [1:0] as S2MM error bits.

Corrected app-only facts:

- `VDMA_S2MM_CONTROL` now includes `VDMA_CR_FSYNC_TUSER=0x40`; the expected stopped-CR write value is `0x00010043`.
- SR error checks now use the documented `VDMA_SR_ERROR_MASK=0x00000FF0`; invalid `VDMA_S2MM_ERROR_MASK=0x0000000F` was removed.
- The missing `wait_first_s2mm_frame()` was restored. It uses PARKPTR current-write movement and returns a warning on camera timeout instead of silently passing.
- `wait_first_vdma_frame()` now uses PARKPTR current-read movement.

ARM build PASS with Ninja/Vitis GCC: `app_component.elf` generated, text=41053, data=1428, bss=22996. Two harmless warnings remain for unused legacy `fill_color_pattern()` and `verify_color_pattern()`.

Post-fix source SHA-256 is `39FE691B3C5113B137A744E77EB6D6BE3D5A0BD30B12C7FF97933B463D42BBA4`; ELF SHA-256 is `C44A8DC5C9D5CA1C1AB49893F535776E0A4BC9AD5B9E409F4CB9965A612DA8FC`. Raw source/build/hash evidence is at `E:\competition\4_metrics\logs\2026-09-07_camera_s2mm_fsync_fix_run01`.

No new board run, UART PASS, camera image, or HDMI display PASS is claimed. The active bitstream remains `0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7`.

## 17:03 Camera J5 Constraint Audit

**Result: data/timing constraints PASS; camera reset/power control FAIL.** Using the user-confirmed SDA/3.3 V/GND orientation, the active XDC correctly maps SCK=Y20/J5-15, SDA=Y21/J5-16, VS=AA21/J5-17, HS=AB21/J5-18, PCK=AA22/J5-19, XCK=AB22/J5-20, and D7..D0=V18,V19,U20,V20,W20,W21,V22,W22 for J5-21..J5-28. All use LVCMOS33.

The adapter's RST and PWDN map to J5-29/T22 and J5-30/U22, but there are no matching FPGA ports or XDC constraints. The existing `resetn_0=L18` feeds only `clk_wiz_0/resetn` and is not the camera reset. If the adapter has no suitable pullup/pulldown, RST/PWDN may leave the OV5640 held in reset or powered down.

Audit evidence and the full mapping are at `E:\competition\4_metrics\logs\2026-09-07_camera_j5_constraint_audit_run01\CAMERA_J5_CONSTRAINT_AUDIT.md`. No XDC/BD/RTL file was changed.

## 17:12 Successful Reference Camera Constraint Audit

**Read-only audit result: reference has camera data/timing constraints, but no physical camera RST/PWDN constraints.** The reference XDC explicitly maps SCCB SCK/SDA, XCLK/PCLK, HREF/VS, D7..D0, `sccb_cfg_done_0`, and `sys_rst_n_0`, and sets `CLOCK_DEDICATED_ROUTE FALSE` for `cam_pclk_0_IBUF`.

The reference `sys_rst_n_0=U15` is not the OV5640 physical reset. A case-insensitive search found no camera `RST` or `PWDN` output. The reference pins also cannot be copied because it targets `xc7z010clg400-1`, not the current `xc7z020clg484-1`; only its design logic and constraint presence are reusable evidence.

Reference XDC SHA-256 is `2EBCFE5D5FC30DD454EDACD6796ACAD7785C6A94E02AB4A2F846413BD1A84318`; current XDC SHA-256 is `E523CE91F3AD3350F828E7681CFC179040C8C942D5059D956A43AB8CDBE32B2A`. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_reference_camera_constraint_audit_run01\REFERENCE_CAMERA_CONSTRAINT_AUDIT.md`. No project file was changed.

## 17:20 Evidence Boundary Correction

The successful reference project's lack of camera `RST`/`PWDN` constraints means only that this reference setup did not require explicit FPGA control on those pins under its hardware and adapter conditions. It cannot prove that the current J5 adapter always has valid OV5640 idle levels.

For current debugging, therefore, camera `RST`/`PWDN` is downgraded from a confirmed root cause to an unverified electrical risk. The active failure evidence remains the supplied UART stop at `PS_HDMI_VDMA_FAIL STEP=S2MM_CONFIG_STATUS` with `S2MM_SR=0x00014810` after the PS-side TUSER FSYNC correction was built but before its board rerun result was supplied.

## 17:35 S2MM Reference CR Board Result and Startup-Clear Fix

**Board result: FAIL, but the controlled CR experiment completed.** The supplied UART confirmed `S2MM_CR=0x00010001`; therefore the prior removal of Circular/TUSER/IRQFrameCount extras was loaded correctly. The S2MM still immediately reported `S2MM_SR=0x00014810` at `S2MM_CONFIG_STATUS`, so these extra control bits were not the sole cause.

A second one-variable PS-only diagnostic now tolerates the free-running camera startup race: after S2MM VSIZE is written, code waits 2 ms, prints `VDMA_S2MM_STARTUP_CLEAR BEFORE/AFTER`, writes the SR error/IRQ masks as W1C, and continues only if the error mask remains clear. No PL/BD/XDC/bitstream change was made.

`app_component` build PASS with text=41173, data=1428, bss=22996. Source SHA-256 is `91B77688A6B360F85B38D0CA6A5ABA61A4649092A6F3A1BC38A22CCC080A1C4A`; ELF SHA-256 is `5E44F54434AD55CB8AC904A5F92F5118ADF34F2CED94770D21E3B8AADC9C34D1`. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_s2mm_startup_clear_run01\S2MM_STARTUP_CLEAR_REPORT.md`. No board rerun or display PASS is claimed.

## 17:55 Persistent S2MM Fault and HDMI Keep-Alive

**Board result: FAIL for camera; no-signal behavior explained.** The supplied startup-clear UART showed `BEFORE=0x00014810` and `AFTER=0x00010000`, but the next status was already `0x00014810` again. This proves a persistent SOF/frame-size fault, not a transient cold-start race. The old code returned before MM2S, so HDMI timing was never started; this explains no signal rather than black screen.

A PS-only keep-alive revision now continues to MM2S after S2MM config/first-frame failure. MM2S remains the sole fatal display gate; S2MM failures are logged continuously as `CAMERA_STREAM_FAIL` / `CAMERA_OK=0` without stopping HDMI. A 60-second stable MM2S run with a bad S2MM now reports `PS_HDMI_SIGNAL_PASS_CAMERA_FAIL`, never camera PASS.

`app_component` build PASS with text=41637, data=1428, bss=22996. Source SHA-256 is `5B33C92AA2F8DF71194F010A8D25C598B17E45B3C5C9C85E86A229BF98FF6525`; ELF SHA-256 is `145637D81FBFFC11245569BA2BB8F37A980B0FB6849F81CDA60938F784E3DC39`. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_hdmi_keepalive_camera_fail_run01\HDMI_KEEPALIVE_CAMERA_FAIL_REPORT.md`. No board rerun or display PASS is claimed.

## 18:05 Exact Reference S2MM Sequence

**Status: PS-only change written and built; no board run claimed.** To match the user-approved simplest bring-up, `VDMA_Configure_S2MM()` now uses the successful reference project's exact write order: CR first, three frame addresses, stride, HSIZE, then VSIZE last. The startup-clear, register-readback gate, and immediate S2MM status gate were removed.

The HDMI keep-alive logic remains active, so a persistent S2MM fault cannot prevent MM2S/HDMI startup. `app_component` build PASS with text=41165, data=1428, bss=22996. Source SHA-256 is `A91FFA133BFC54092AAA06DA78D94A990F0ABB2840D2329DB3D7883F9D665A10`; ELF SHA-256 is `1AC1F422878A277D5E7DB7A53FD9A4A9EA6289F552334D80C19C3D2129A800F2`. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_s2mm_exact_reference_order_run01\S2MM_EXACT_REFERENCE_ORDER_REPORT.md`.

## 18:02 Clean Unused Color-Bar Warnings

**Code hygiene PASS; no board run claimed.** Removed the retired color-bar helper chain (`color_for_column`, `expected_display_byte`, `fill_color_bar`, `fill_color_pattern`, and `verify_color_pattern`) that caused the two IDE unused-function warnings. This does not alter VDMA configuration, address/size parameters, PL files, or the bitstream.

`app_component` rebuilt PASS with no compiler warnings: text=39981, data=1428, bss=22996. Source SHA-256 is `78A0AA9F9D4801F8941DCB64B6F9E522FA71A64F50BC8BF0AC52C75413B1F738`; ELF SHA-256 is `BDD215B823C9AEBBAE33E5B373CB8576EF5E318F2B250BC51FACCA1021604A47`. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_remove_unused_colorbar_code_run01\REMOVE_UNUSED_COLORBAR_CODE_REPORT.md`.

## 18:10 Color-Bar Restore and Bitstream Mismatch

**Build PASS; board result pending.** The camera source was archived, the exact full-screen color-bar source was restored, and `app_component` rebuilt with exit code 0 and no warnings. The restored source is `0870D8...65F3`; the new ELF is `C99A1D...3EF3B`.

A critical controlled-variable mismatch was found: the known-good color-bar bitstream archive is `0A9CBC...C271F7`, while the current default Vitis/platform and implementation-directory bits are `E7950A...5FDC`. The platform bit was refreshed after the color-bar PASS. The firmware's printed hash is only a compile-time constant and cannot identify the image actually loaded into the FPGA.

Evidence: `E:\competition\4_metrics\logs\2026-09-07_hdmi_no_signal_colorbar_restore_run01\COLORBAR_RESTORE_AND_BITSTREAM_MISMATCH_REPORT.md`.

## 18:18 Color-Bar Manual-Reset PASS

**Board PASS for the color-bar A/B restore.** The archived bitstream `0A9CBC...C271F7` plus restored color-bar ELF `C99A1D...3EF3B` produced full-screen bars after one manual reset. Photo SHA-256 is `6C10DC...919B5C`. This confirms the archived PL/HDMI image is good and establishes manual reset as a required load step.

**Camera status remains unproven.** The camera source `78A0AA...F738` was restored and rebuilt PASS into ELF `BDD215...A47`. The prior `VDMA_S2MM_FAIL REASON=FIRST_FRAME_STATUS SR=0x00014810` may have been affected by reset sequencing, but it cannot be declared solved until the exact archived bit plus this camera ELF is retested with manual reset.

Evidence: `E:\competition\4_metrics\logs\2026-09-07_colorbar_manual_reset_pass_run01\COLORBAR_MANUAL_RESET_PASS_AND_CAMERA_RETRY_REPORT.md`.

## 18:35 Camera Dynamic Genlock Fix

**PS-only change written and built; board result pending.** The VDMA XCI confirms S2MM is a dynamic Genlock master with TUSER Fsync, and MM2S is a dynamic Genlock slave. The prior firmware did not enable those CR bits, so MM2S could race S2MM writes. The corrected controls are S2MM `0x000180CB` and MM2S `0x0001008B`.

Build PASS with source SHA-256 `705B03...F9C0` and ELF SHA-256 `5C9246...98C65`. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_camera_dynamic_genlock_fix_run01\CAMERA_DYNAMIC_GENLOCK_FIX_REPORT.md`.

A separate PL evidence issue was recorded: the XDC constrains `cam_pclk` at 24.038 MHz while OV5640 registers configure PCLK to about 51 MHz. This is a likely source of remaining camera noise/color bit misalignment but must not be combined with the Genlock board test.

## 18:50 Reference Clock Tree Audit

**Read-only audit PASS for comparator validity.** The 2020 project reproduces the current requested clock plan: `pclk=25 MHz`, `pclk_x5=125 MHz`, `xclk=24 MHz`, and `clk_50m=50 MHz`. The only PLL input difference is 50 MHz in 2020 versus 100 MHz currently; both produce the same requested output plan. Current routed clocks are PS `FCLK_CLK0=50 MHz`, `pclk=25 MHz`, `xclk=24.038 MHz`, `clk_50m=50 MHz`, and camera PCLK constrained at 24.038 MHz.

Current `pclk_x5=125 MHz` is optimized out because the current ADV7511 parallel RGB output consumes only `PIX_CLK=25 MHz`; the 2020 custom TMDS output consumes `pclk_x5`. This is an architecture difference, not a current clock-tree fault. Both projects use async video-in/video-out FIFOs, 1 pixel/clock, and 24-bit RGB, with VDMA AXIS/AXI domains on PS `FCLK_CLK0`.

Camera capture and OV5640 configuration sources are byte-identical: `cam_cap_data.v` SHA-256 prefix `4511CC14AF78`, `SCCB.v` `06BB5316BEA2`, `OV5640_REG.v` `182EAA6BAB0C`, and `ov5640_cfg_top.v` `196AA7FF561E`. The confirmed high-priority PL difference is AXI VDMA `S2MM Line Buffer Depth`: current `512` versus successful reference `1024` for a 640-pixel line.

The three new camera-board photos were archived under `E:\competition\4_metrics\logs\2026-09-07_camera_dynamic_genlock_board_run01` with SHA-256 prefixes `B5CFF52853AE`, `0723C6B15571`, and `03D32B7334BB`. The complete clock-tree audit is at `E:\competition\4_metrics\logs\2026-09-07_reference_clock_tree_audit_run01\REFERENCE_CLOCK_TREE_AUDIT.md`. No project file was changed.

## 19:05 Camera Color Format Chain Audit

**Read-only audit PASS.** The current output path is confirmed to convert `RGB888` to BT.601 limited-range `YCbCr422` in `hdmi_out_adv7511_v1_0.v` before the board byte swap and ADV7511. `pix_frame_display` passes the 24-bit VDMA/video-out pixel unchanged outside overlays. The 2020 reference instead sends RGB directly to TMDS encoders, so it proves the camera/SCCB/register chain but does not prove identical current color transport.

The current YCbCr422 transport is not unproven: the 2026-09-06 board PASS used logical `{Y,Cb/Cr}`, physical byte swap, `R0x15=01`, `R0x16=38`, and `ADI_CSC601_LR_TO_RGB_V1_3`; the recent synthetic color-bar PASS exercised the same output block. The misleading RGB comments in `adv7511_init_table.sv` must not be treated as a functional RGB444 configuration.

This conversion can explain color shift, chroma softening, and RGB/RGB565 channel-order distortion, but not line tearing/flicker as well as the confirmed `S2MM Line Buffer Depth=512` versus reference `1024`. Keep the S2MM line-buffer experiment separate from any ADV7511/camera color experiment. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_camera_color_format_chain_audit_run01\CAMERA_COLOR_FORMAT_CHAIN_AUDIT.md`. No project file was changed.

## 19:40 Camera Display Error Report Delivery

**Documentation deliverable created.** The consolidated analysis is at `E:\competition\1_docs\摄像头采集显示错误分析报告_2026-09-07.md`. It records the full camera-to-HDMI data path, confirmed fixes, S2MM startup evidence, clock-tree comparison, J5 constraint status, ADV7511 RGB888-to-YCbCr422 conversion, current BIT/ELF hashes, symptom-to-cause matrix, and isolated next experiments.

The report correctly retains the evidence boundary: the camera image is visible but there is still no complete camera PASS because the latest dynamic Genlock run lacks full UART. It ranks `S2MM Line Buffer Depth=512` versus reference `1024` as the highest-priority confirmed configuration mismatch, while keeping PCLK constraint and color-format issues separate.

## 21:12 pix_frame Sync Polarity Regression

**High-confidence regression found; no frozen source edited yet.** The latest 21:03 BIT completed with routed timing PASS and was exported to the Vitis platform. Its SHA-256 is `0B83DEB6CBC1A4A45532D0D7CEDDD86B71ACF7B47E5B62E910514717E05D028A`.

`pix_frame_dispaly.v` was changed at 20:57 from the board-working inverted synchronization form (`~vio_hsync`, `~vio_vsync`) to straight-through synchronization (`vio_hsync`, `vio_vsync`). This is the highest-probability cause of the new no-signal state. The new VDMA `S2MM Line Buffer Depth=1024` is confirmed present and should remain unchanged during recovery. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_pix_frame_sync_polarity_regression_run01\PIX_FRAME_SYNC_POLARITY_REGRESSION.md`.

## 21:50 Camera HDMI `BOARD_VISUAL_PASS` Freeze

**Result: `BOARD_VISUAL_PASS`, not formal full UART acceptance.** Three archived success photos show live OV5640 camera data rendered by the frozen BIT/XSA/ELF chain after the required manual reset. Photo SHA-256 values are `86DB0EEC5299904266BDAD9735E14DDAD9DECC912087C1739F33F1F386CF83F5`, `7339D41B04135D136DACA92661EDCC612563017BE334B87CA2E5BC63E0963D2F`, and `0B780CD8228FD8485D521DA1E10E32530E6114BC46D64CF6FB93B9D8AB88B51D`.

The frozen artifacts verify as BIT `16DBACBFCA755D69B08AE1720AF10D6C642E97B12F34F410241CEC1F29130624`, XSA `7374BD4EE2D30C726FC0135E1960BA2BE19BD22C3B9D75B0AB0BBEE1CE64A6E1`, ELF `040B57D048D76A60AAED8262F4E7E05204E6A96E8EF01AD6598BE4EE93BDD990`, `main.c` `705B0317DC688022DF5956EC985A041D87E47D4348BFB6107C1D614D6CE5F9C0`, `pix_frame_dispaly.v` `459BDB36FFF8E9655198E2B1F57DCC3621D520C1011152E9E71606EB88EC36D5`, BD `231E9F7221EF371A3BEA2DDEB79F967933C80D1ECCD0D105913C92592D50C003`, and VDMA XCI `2C442A8B31361CA2E67121668B7A1E43EA018C146D923E3AC9F1D8E3198101E1`. Active project copies match these frozen copies.

Final PL fixes are `S2MM Line Buffer Depth=1024` and restored `~vio_hsync` / `~vio_vsync` polarity. Route status reports 11060/11060 fully routed and 0 errors; timing reports WNS `9.510 ns`, TNS `0.000 ns`, no failing setup endpoints, and all user constraints met. Evidence is at `E:\competition\4_metrics\logs\2026-09-07_camera_display_success_freeze_run01`.

No complete UART was supplied with the photos. Therefore the 60-second register/no-error condition cannot be evaluated, and this must remain `BOARD_VISUAL_PASS` until a later same-BIT/same-ELF UART run passes.
