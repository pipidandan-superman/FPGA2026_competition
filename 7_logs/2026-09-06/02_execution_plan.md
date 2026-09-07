# 2026-09-06 Execution Plan

1. Read 2026-09-05 DIAGNOSIS.md and retain the run02 ILA evidence.
2. Power off and inspect R110/R140 placement, soldering, and continuity.
3. Power on and measure their common VADJ node and SDA/SCL idle levels.
4. Capture address transaction at ADV7511 pins; check ACK, rise time, and whether SDA remains high when released.
5. Verify ADV7511 reset/power rails and address strap; only then test a known-good device or replacement.
6. Treat I2C transaction validity, register functional-field validity, and display functionality as three separate checks. Do not infer full-byte write retention from protocol success, and do not infer initialization failure from reserved-bit readback mismatch.

## 12:30 update: execution performed

1. Re-read UG Rev. D Tables 7/10 and the ADI API field mapping. The physical
   byte-swapped bus is UG Style 1, while the API maps UG Style 1 to register
   style field 0; therefore the new `R0x16` is `0x30`, not `0xBD`.
2. Cross-checked Linux ADV7511 RGB-output behavior: `R0x16[7]` and `R0x16[0]`
   are cleared for RGB output, and a full limited-range BT.709 YCbCr-to-RGB CSC
   is programmed into `R0x18..R0x2F`.
3. Rewrote 55 entries in `adv7511_init_table_pkg.sv`, including ADI fixed
   registers, packet-map settings, right justification, full CSC, CSC update-bit
   handling, and `R0xAF=0x04`.
4. Kept the active byte swap in the top level but documented it as the physical
   Style 1 adaptation. This is a register-mapping fix, not another blind test.
5. Updated six masked readback checks: `41/15/16/48/18/AF`. Raw status bits are
   not treated as write-retention failures.
6. Updated the self-checking testbench and ran positive/negative simulations.

## 13:00 update: V2.1 execution strategy

1. Archive the V2.0 board photo and retain it as proof that byte position is
   now correct.
2. Rewrite only the output architecture: disable CSC, set `R0x16=0xB1`, enable
   the AVI packet, and program YCbCr422/VIC-1 metadata.
3. Keep `R0x15=01`, `R0x48=08`, and the current physical byte swap unchanged.
4. Use HDMI mode `R0xAF=0x12`; DVI mode is not valid for a YCbCr output.
5. Re-run positive and negative simulations before another bitstream build.

## 13:05 update: source-state audit execution

1. Read the active source files and confirm the V2.1 package constants,
   44/6 table counts, `R0x16=0xB1`, and `R0xAF=0x12`.
2. Confirm `hdmi_colorbar_vtc_top.v:233` actively byte-swaps the source and
   `HDMI_DATA` registers `physical_data` at line 241.
3. Update `hdmi_colorbar_vtc_top_mode_tb.sv` to V1.1 so its board-lane check
   uses `u_dut.physical_data` rather than `u_dut.selected_data`.
4. Compile the complete top-level Mode TB with a unique ModelSim library. Retry
   command-line execution first, then use the GUI only after the known
   `FileWatch` load failure.
5. Record current source hashes and preserve the transcript in
   `4_metrics/logs/2026-09-06_hdmi_style1_mode_tb_run01`.

## 13:12 update: explicit package reference execution

1. Audit all Vivado source entries and identify the package as the only active
   file under `$PSRCDIR/sources_1/imports/`.
2. Replace its project path with the canonical external `$PPRDIR` path.
3. Remove only the project metadata that marks it as an imported snapshot.
4. Load the XPR as XML, resolve the external path, and verify that no imported
   source entries remain.
5. Do not delete the old imported copy automatically.

## 13:22 update: table module conversion

1. Create `adv7511_init_table.sv` with explicit index ports and table outputs.
2. Instantiate it as `u_adv7511_init_table` inside
   `adv7511_iic_data_xfer`.
3. Replace package imports and function calls with table output wires.
4. Update both testbenches and build scripts to reference the new module.
5. Remove the obsolete package source after no active references remain.
6. Rerun positive, negative, and top-level mode simulations.

## 13:55 update: RGB/Style-3 correction

1. Read the user-modified table, I2C controller, video top, converter, ILA
   waveform, board photo, and Vivado synthesis warnings.
2. Widen `init_index_i` to seven bits so all 68 entries are reachable.
3. Keep the unswapped `{Y, Cb/Cr}` bus and change `R0x16` to Style 3 value
   `0x38` for RGB444 output.
4. Keep AVI RGB metadata `R0x55=0x09` and update checksum `R0x54` to `0xCB`.
5. Run the three prepared ModelSim scripts, then rebuild and board-test.

## 14:25 update: CSC601 execution

1. Verified that the current 13:46:49 bit was older than the corrected source
   and then found that the old bit path had been removed as the user began a
   rebuild.
2. Replaced the modified/approximate CSC bytes with the exact ADI API
   CscYcc601ToRgb table for R0x18..R0x2F.
3. Rewrote rgb2ycbcr422 as a clean three-stage pipeline. R, G, and B are now
   captured on the same edge; standard limited-range BT.601 coefficients are
   scaled for the 12-bit accumulator.
4. Updated the SW0 direct YCbCr constants to the same BT.601 values as the
   converter: White EB80, Black 1080, Red 515A/51EF, Blue 28EF/286D,
   Green 9035/9022.
5. Updated Mode TB expected words to check the converter and direct source at
   the same pixel positions.
6. Ran positive configuration, negative configuration, and top-level mode
   simulations; preserved raw console outputs in the CSC601 rebuild run folder.
7. Did not launch Vivado because the user explicitly chose to generate the
  bitstream from the already-open session.

## 14:25 update: CSC601 execution

1. Verified that the current 13:46:49 bit was older than the corrected source
   and then found that the old bit path had been removed as the user began a
   rebuild.
2. Replaced the modified/approximate CSC bytes with the exact ADI API
   CscYcc601ToRgb table for R0x18..R0x2F.
3. Rewrote rgb2ycbcr422 as a clean three-stage pipeline. R, G, and B are now
   captured on the same edge; standard limited-range BT.601 coefficients are
   scaled for the 12-bit accumulator.
4. Updated the SW0 direct YCbCr constants to the same BT.601 values as the
   converter: White EB80, Black 1080, Red 515A/51EF, Blue 28EF/286D,
   Green 9035/9022.
5. Updated Mode TB expected words to check the converter and direct source at
   the same pixel positions.
6. Ran positive configuration, negative configuration, and top-level mode
   simulations; preserved raw console outputs in the CSC601 rebuild run folder.
7. Did not launch Vivado because the user explicitly chose to generate the
   bitstream from the already-open session.

## 14:48 update: build-freshness audit

1. Compared source, synthesis-DCP, and bit timestamps. The synthesis DCP was
   14:27:03.709-era while `hdmi_colorbar_vtc_top.v` was saved at 14:28:03.871
   and `adv7511_init_table.sv` at 14:44:56.361.
2. Concluded that the 14:29:08 bit cannot contain either the 14:28 top-level
   mapping update or V1.3 CSC. Marked the latest board photo as stale-build
   evidence only.
3. Preserved the stale photo and prepared the next rebuild to require a reset
   synthesis run, post-build hash, and two board photos.

## 15:10 update: final verification and push

1. Archived the user's PASS photo and source-edit screenshot under
   `4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/`.
2. Updated top-level comments, register-table comments, and Mode TB to check
   `physical_data` as the required byte swap.
3. Ran the updated Mode TB. The CLI displayed the known FileWatch load message,
   but the simulator continued and wrote the stable PASS marker to
   `mode_result.txt`; retained the transcript, WLF, and result file.
4. Updated the board adaptation document and handoff; excluded generated
   bitstreams, ModelSim libraries, and Vivado runs from the commit.

## 15:22 update: cleanup and skill archive execution

1. Created a quarantine under
   `4_metrics/logs/2026-09-06_workspace_cleanup_run01/root_quarantine/`.
2. Moved root ModelSim libraries, Vivado transient directories, screenshots,
   backup ZIPs, transcript/WLF files, and temporary notes by explicit path.
3. Added `.gitignore` protection for the local-only quarantine and preserved a
   manifest with the protection/fallback note.
4. Copied `modelsim-local-sim`, `modelsim-gui-sim`, and
   `vita-vivado-batch-sim` into `6_skill/`; documented that the Vivado skill is
   a ViTA-specific reference requiring adaptation.
5. Did not modify or traverse `2_fpga` for cleanup.

## 15:56 update: project skill adaptation execution

1. Read the active daily-log override and all `6_skill/SKILL.md` files; inspected
   companion Tcl, PowerShell, RTL, Markdown, and YAML files.
2. Added `.codex/skills/project-workspace-policy/SKILL.md` as the project-wide
   precedence layer and referenced it from `AGENTS.md`.
3. Changed `6_skill/daily-engineering-log` from generic `<workspace>` wording to
   the exact `E:\competition\7_logs\YYYY-MM-DD` destination.
4. Added explicit project overrides to engineering organization, RTL standards,
   ModelSim CLI, ModelSim GUI, and Vivado batch skills.
5. Redirected Vivado artifacts to `4_metrics/logs`, replaced historical ViTA
   markers with `EES_VIVADO_RESULT`, and created project-local launcher/checker
   scripts plus archive wrappers.
6. Added `4_metrics/scripts/audit_project_skill_paths.ps1` to check front-matter
   names, fixed roots, and forbidden executable path tokens in skill files and
   companions.
7. Updated `6_skill/README.md` and `SKILL_REVIEW_PENDING.md` so the archive
   agrees with the active policy layer.
