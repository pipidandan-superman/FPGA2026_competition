# 2026-09-07 Execution Plan

## Ordered Strategy

1. Apply the project workspace policy and use only `7_logs` for session records.
2. Read `hdmi_out_adv7511_v1_0.v` and verify module ports and dependencies.
3. Inspect `display_test_zynq7020_school.xpr`, `display_test.bd`, and existing module-reference metadata.
4. Search existing 2026-09-06 evidence for prior compile/elaboration proof.
5. Summarize the likely cause and recommended follow-up without changing the frozen project.

## Relevant Files

- `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_out_adv7511_v1_0.v`
- `E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.xpr`
- `E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.srcs\sources_1\bd\display_test\display_test.bd`
- `E:\competition\4_metrics\logs\2026-09-06_hdmi_out_adv7511_v1_0_top_run01\modelsim_transcript.txt`

## Risks and Fallback

Risk: adding the new module to the live BD would alter the frozen board-proven project. Fallback: keep the action plan review-only and perform any BD change in an explicit copied diagnostic project with raw evidence captured under `4_metrics/logs`.

## 08:39 Authorized Recovery Strategy

1. Preserve existing Vivado logs by copying them into a new evidence run; never overwrite prior evidence.
2. Run Vivado 2025.2 in batch mode with `general.usePosixSpawnForFork=0`, disabled cluster monitoring, and `-jobs 1`.
3. Verify the exact top is `display_test_wrapper`, query `HDMI_CLK_0` properties, and require the completed synthesis DCP before implementation.
4. Reset and rebuild `synth_1`, then reset and launch `impl_1 -to_step write_bitstream` with one job.
5. Accept the build only after Vivado exits 0, implementation progress is 100%, `display_test_wrapper.bit` exists, timing constraints are met, and route status reports zero routing errors.
6. Copy reports and the bitstream copy into `E:\competition\4_metrics\logs\2026-09-07_vivado_full_build_run01`, record SHA-256 hashes, and update these handoff files.

## 09:10 HDMI/VDMA Comparison Strategy

1. Identify the 2026-09-06 board PASS project and bit provenance from `7_logs` and `4_metrics/logs`.
2. Read the successful `hdmi_colorbar_vtc_top`, hand-written 480p VTC, RGB-to-YCbCr converter, EES-331 byte swap, and ADV7511 controller hierarchy.
3. Parse the current BD JSON, generated wrapper/netlist, VTC XCI, VDMA XCI, Video In/Out XCIs, clocking configuration, address editor entries, constraints, and PS app skeleton.
4. Compare timing geometry, sync polarity, pixel format, output byte order, clocks/resets, frame buffers, and PS-source versus camera S2MM ownership.
5. Write a reviewable staged plan in `E:\competition\4_metrics\logs\2026-09-07_hdmi_vdma_review_plan_run01` and leave PS code as a gated follow-up.
6. Do not execute Gate P1 or write PS code until the user approves the plan.

## 11:30 PS Rewrite Documentation Strategy

1. Re-read the project workspace policy and confirm `7_logs` is the only session-record root.
2. Verify the current bitstream hash and VTC active-low polarity without changing PL files.
3. Verify the existing `main.c`, its pre-change backup, and their matching hashes.
4. Create the PS rewrite plan in `E:\competition\1_docs\doc\PS_VDMA_HDMI_REWRITE_PLAN.md`.
5. Record the plan hash, approval boundary, rollback point, verification criteria, and forbidden actions in this daily log.

Risk: premature execution could mix a PS-source change with S2MM writes or obscure the proven bitstream state. Fallback: keep the work plan-only and replace `main.c` only after a separate explicit instruction.

## 11:45 PS Code Replacement Strategy

1. Confirm the pre-change `main.c` still matches the preserved backup hash.
2. Replace only `E:\competition\2_fpga\0_diaplay_test\vitis\app_component\src\main.c`.
3. Implement the planned order: UART self-test, reset/check S2MM, reset MM2S, clear/readback DDR, fill/readback three-frame RGB pattern, configure/readback MM2S, first-frame check, 60-second monitor, then continuous runtime heartbeat.
4. Add UART markers and register dumps at every gating step and failure path.
5. Archive the post-change source snapshot and hashes under `4_metrics/logs/2026-09-07_ps_hdmi_vdma_run01`.
6. Do not compile, launch Vitis, program the board, start S2MM, or claim HDMI PASS.

## 11:56 UART Gate Fix Strategy

1. Decode `SR=0x00002802` against the Zynq UARTPS status bits.
2. Preserve the user-provided screenshot as raw evidence.
3. Add a 100 microsecond delay to `wait_uart_tx_empty()`, allowing up to one second for the direct UART token to drain.
4. Archive the corrected source snapshot and hashes under `4_metrics/logs/2026-09-07_ps_hdmi_vdma_uart_gate_fix_run01`.
5. Do not compile or program the board unless the user explicitly requests the next stage.

## 12:10 MM2S Frame-Store Fix Strategy

1. Compare the observed `FRMSTORE=0` with the VDMA XCI and BSP debug-feature mapping.
2. Confirm `C_NUM_FSTORES=3` and `C_ENABLE_DEBUG_INFO_5=0`; therefore the MM2S frame-store register is disabled.
3. Remove the runtime `VDMA_MM2S_FRMSTORE` write and impossible readback condition.
4. Keep address, stride, HSIZE, VSIZE, status, first-frame, S2MM-stopped, and 60-second checks.
5. Archive the corrected source snapshot and hashes; do not compile or run hardware unless separately requested.

## 12:35 Top-Line Noise Genlock Strategy

1. Copy the board screenshot, two UART captures, and pre-change source into `2026-09-07_hdmi_topline_noise_run01` before editing.
2. Read the VDMA XCI and BSP mappings; confirm mode 3 means dynamic genlock slave.
3. Add genlock enable bit 3 and internal genlock source bit 7 to the MM2S control word.
4. Require exact `CR=0x8B` readback and print the expected control word.
5. Archive before/after source snapshots, the active bitstream, hashes, and an evidence report.
6. Keep S2MM stopped, preserve DDR/color logic, do not compile or board-test without a new explicit run request, and do not claim display PASS.

## 12:40 Count-Bit Revision Strategy

Cross-check the board CR value before finalizing the readback gate. Preserve the observed frame-count-one bit 16, include genlock enable/source bits, require `CR=0x0001008B`, overwrite the post-fix source snapshot, and record the final source hash `D8821C0E236EA1F8CE3A7665A8DCD3719D2C57280B5F92D7388DE46DC8502C72`.

## 13:20 Packed RGB888 Correction Strategy

1. Archive the overlay-OK / PS-data-fail UART and screen photo before editing.
2. Confirm the PS bug: RGB888 is a continuous 3-byte stream, not one 32-bit word per pixel.
3. Replace DDR clear, fill, and verification with byte-wide packed RGB888 operations.
4. Add VDMA PARKPTR and current-read-frame diagnostics without changing VDMA control or PL/BD.
5. Archive before/after source snapshots and hashes; do not compile or rerun hardware unless separately requested.

## 14:05 Reference-Style PS Code Alignment

1. Re-read the user-supplied 7010 reference functions for reset, framebuffer clear, and MM2S setup.
2. Reuse their flow and names, but retain this project's `0x43000000`, `0x10000000`, 3 x 1 MiB slots, stride 1920, and MM2S control `0x0001008B`.
3. Implement packed-RGB888 row/column clear/fill with a three-byte pixel stride.
4. Reset MM2S/S2MM with timeout diagnostics, keep S2MM stopped, and configure MM2S in the order CR, addresses, stride, HSIZE, VSIZE.
5. Archive the source snapshot and static checks; do not compile, program, or claim display PASS.

## 14:20 No-Signal Padding and Order Hotfix

1. Decode the repeated board UART stop at `0x100E1000` as the first 1 MiB slot's active-frame boundary.
2. Fix `Clear_FrameBuffer()` to clear the full current-project 1 MiB slot before filling the active packed-RGB888 pixels.
3. Keep the previously signal-locked MM2S order: addresses, stride, HSIZE, CR, VSIZE last.
4. Archive the supplied UART, before/after source snapshots, hashes, and static checks.
5. Stop before compile/board unless separately requested.

## 14:35 PS-Only Genlock Isolation

1. Classify the first-row color-bar result as a VDMA data-path issue, not HSYNC/VSYNC polarity.
2. Disable only `GenlockEn` for the PS-only test because the S2MM dynamic-genlock master is intentionally stopped.
3. Change MM2S control from `0x0001008B` to `0x00000003` and keep all packed-RGB888/address/order changes unchanged.
4. Archive the board photo, source snapshot, and diagnostic report.
5. Require the next UART to show `MODE=DISABLED_PS_ONLY CONTROL=0x00000003`.

## 16:57 Camera S2MM FSYNC Strategy

1. Confirm the active VDMA XCI sets `C_USE_S2MM_FSYNC=2` and the BSP maps FSYNC source value 2 to CR bits [6:5] = `10`.
2. Add `VDMA_CR_FSYNC_TUSER=0x40` to the S2MM control word, while retaining RUN, circular mode, and IRQFrameCount=1.
3. Remove the invalid `VDMA_S2MM_ERROR_MASK=0x0000000F`; SR bits [1:0] are HALTED/IDLE state, not S2MM error bits.
4. Re-add the missing `wait_first_s2mm_frame()` and use PARKPTR current-write movement as first-frame evidence.
5. Rebuild only `app_component`, archive source/build/hash evidence, and stop before any new board run unless the user explicitly runs it.

## 17:03 Camera J5 Constraint Audit Strategy

1. Read `pin_zynq7020_cam.xdc` and map every camera port to the J5 table using the user-confirmed SDA/3.3 V/GND orientation.
2. Check D0-D7, XCK/PCK, HS/VS, and SCCB SCK/SDA independently against the camera-base silkscreen.
3. Verify whether J5-29/J5-30 RST/PWDN are connected to any BD port or FPGA output.
4. Preserve the XDC, screenshots, and audit report in one read-only evidence folder.
5. Do not edit XDC/BD/RTL or rebuild PL; recommend the minimum next hardware/build check if RST/PWDN are missing.

## 17:35 Continuation

After the `CR=RUN` board failure, the next single-variable experiment is to tolerate and clear a transient S2MM startup alignment error, then require the post-clear status to remain error-free. Keep the PL frozen and keep RST/PWDN out of this experiment.

## 18:50 Reference Clock Tree Audit

1. Compare the 2020 board-proven project and current project only by clock source, MMCM request/actual outputs, BD clock connections, video async-clock settings, and camera capture source hashes.
2. Treat the 2020 project as valid comparator evidence; do not dismiss it because the Zynq package differs.
3. Preserve the frozen current project and record any proposed PL parameter change without executing it until explicitly authorized.
4. Report the highest-priority isolated PL-only candidate from the comparison.

## 19:05 Camera Color Format Chain Audit

1. Audit the current pixel path from VDMA RGB888 through `pix_frame_display`, ADV7511 formatting, and physical HDMI data mapping without editing frozen RTL.
2. Compare it with the 2020 project's direct RGB TMDS output and classify which symptoms the YCbCr422 path can and cannot explain.
3. Preserve the proven ADV7511 transport and keep any format correction separate from the S2MM line-buffer experiment.

## 19:40 Camera Display Error Report Delivery

1. Consolidate color-bar, camera UART, constraint, clock-tree, VDMA, and color-format evidence under `1_docs`.
2. Separate confirmed facts from unverified root-cause candidates.
3. Define the zero-change UART baseline and isolated S2MM line-buffer experiment gate.

## 21:50 Freeze, Evidence, and Push Strategy

1. Verify that the active BIT/XSA/ELF/main.c/pix_frame/BD/VDMA-XCI copies match the frozen evidence copies by SHA-256.
2. Write the freeze conclusion into the existing error report and create a dedicated evidence report under the success-run folder.
3. Preserve the explicit boundary: three photos prove `BOARD_VISUAL_PASS`; absent UART proves formal `FULL_UART_ACCEPTANCE_PASS` is not claimed.
4. Add narrow `.gitignore` exceptions only for the two frozen success binaries.
5. Add a `.gitattributes` rule that disables text conversion for the entire frozen evidence directory so archived source snapshots remain byte-identical.
6. Stage only selected source/config/evidence/log files, audit the staged diff, commit, tag, and push `main` plus the tag.
7. Run the project skill-path audit after all writes.
