# 2026-09-06 Next Start Guide

- Read `4_metrics/logs/2026-09-05_hdmi_root_cause_run02/DIAGNOSIS.md` first.
- First action: create the recovery build from current sources by restoring only `assign sda = sda_en ? sda_out : 1'bz;` while keeping the ILA, then rerun synthesis/implementation and board display validation. Do not claim readback PASS from the display result: run01 display works while the six-byte readback remains `1F 01 FF 0F 1F 1F` and reports `match=1A/error=1`.
- Do not immediately alter ADV7511 registers, byte order, or color conversion.
- Readback rule for the next session: do not use raw full-byte equality against `ADV7511_readback_expected` as a blocking test. Refine `adv7511_readback_mask` to functional fields first and keep raw bytes as diagnostic evidence.
- Success: establish electrical I2C health and a valid ACK/readback before judging the IC.

## 12:30 next start update

- First action: rebuild `hdmi_colorbar_vtc_top` from the current sources, program
  the new bitstream, and capture a photo of the expected five solid bars plus the
  LED byte. Do not modify byte order or CSC coefficients before this test.
- Read first: `E:\competition\4_metrics\logs\2026-09-06_adv7511_config_rewrite_run01\simulation_report.md`.
- Key files: `adv7511_init_table_pkg.sv`, `hdmi_colorbar_vtc_top.v`, and
  `adv7511_cfg_top_tb.sv`.
- Do not restore `physical_data = selected_data` immediately: the new register
  mapping intentionally interprets the current swapped bus as UG Style 1.
- Do not compare raw full-byte register reads for PASS; use the six masked
  functional fields now built into the table package.
- Board PASS: five solid bars (White, Black, Red, Blue, Green), no vertical
  chroma stripes, stable 640x480@60 timing, and no controller retry loop. If
  color geometry is correct but tone is shifted, capture the actual image before
  selecting the alternate BT.601/BT.709 CSC table.

## 13:00 next start update

- V2.0 has already been board-tested and is not final: stripes disappeared but
  the RGB/CSC colors collapsed. Do not rebuild V2.0.
- Rebuild from the current V2.1 sources. The decisive new raw value is
  `R0x16=0xB1`; HDMI mode and AVI YCbCr422 metadata are also required.
- Capture both SW0 modes if the screen differs, but the color-data path is
  intentionally identical. Record whether the monitor reports the input as
  HDMI/YCbCr422 or rejects the mode.
- PASS: five solid, distinct bars with no stripes. If all colors still merge,
  archive the photo and monitor OSD mode before changing the source generator;
  do not reintroduce the RGB CSC path.

## 13:05 source-audit handoff

- The source audit and Mode TB are complete. Do not edit ADV7511 registers,
  video timing, or byte order again before the V2.1 board result.
- First action: synthesize/implement the current Vivado top, program the new
  bitstream, and photograph both SW0 modes plus the LED readback value.
- If the build uses a stale source copy or hash, stop and compare against the
  current decisive hashes in the 13:05 validation summary.
- Board PASS: five solid, distinct bars (White, Black, Red, Blue, Green), no
  vertical stripes, stable 640x480@60 timing, and no I2C retry loop. Record the
  monitor OSD format if colors or geometry are still wrong.

## 13:12 explicit-reference handoff

- If Vivado already has `project_1.xpr` open, reload or reopen the project so it
  reads the changed external package reference.
- For every future ADV7511 register change, edit only:
  `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_init_table_pkg.sv`.
- Do not edit
  `project_1.srcs\sources_1\imports\hdmi_new\adv7511_init_table_pkg.sv`; it is
  now an unreferenced legacy copy.
- After modifying the package, rebuild the bitstream and confirm the Vivado
  source editor shows the canonical `0_diaplay_test` path.

## 13:22 instantiated-table handoff

- Reload `project_1.xpr` if Vivado is already open. Expand:
  `hdmi_colorbar_vtc_top -> u_adv7511_cfg_top -> u_adv7511_iic_data_xfer ->
  u_adv7511_init_table`.
- For future register changes, edit only
  `E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_init_table.sv`.
- If changing the write count, update `INIT_ENTRY_COUNT` and the last case
  number together; if changing the read count, update
  `READBACK_ENTRY_COUNT` and the last readback case together.
- Rebuild the bitstream after any table edit. Expected board behavior remains
  V2.1: five solid bars, no stripes, in both SW0 modes.

## 13:55 RGB/Style-3 handoff

- First action in ModelSim GUI:

```tcl
do E:/competition/4_metrics/logs/2026-09-06_adv7511_rgb_style3_fix_run01/run_config.do
do E:/competition/4_metrics/logs/2026-09-06_adv7511_rgb_style3_fix_run01/run_config_mismatch.do
do E:/competition/4_metrics/logs/2026-09-06_adv7511_rgb_style3_fix_run01/run_mode.do
```

- Do not change video byte order or CSC coefficients again before these three
  simulations and one fresh board test.
- Rebuild `hdmi_colorbar_vtc_top`, record the new bit timestamp/hash, and
  capture both SW0 modes.
- PASS: White / Black / Red / Blue / Green solid bars, no stripes, stable
  640x480@60. If colors are geometrically correct but tone-shifted, capture the
 monitor OSD before changing CSC coefficients.

## 14:25 CSC601 rebuild handoff

- The user is generating the bitstream in the already-open Vivado session; do
  not launch another Vivado process against project_1.
- Before synthesis, force a refresh/reset of synth_1 so Vivado re-reads
  adv7511_init_table.sv, rgb2ycbcr422.sv, and hdmi_colorbar_vtc_top.v. Do not
  reuse the 13:46 bit.
- After synthesis, search runme.log/vivado.log for init_index_i width and
  unreachable case-item warnings. There must be neither warning.
- Record the new bit timestamp and SHA-256 before programming.
- At power-on/reset the LED signature is A5. After configuration, expected LED
  byte is 38 with SW0=0 and B8 with SW0=1; R0x16 raw value is 38.
- Program the newly generated bit, then photograph both SW0 modes. Board PASS:
  White / Black / Red / Blue / Green solid bars, no vertical stripes, stable
  640x480@60.
- Do not change physical_data, R0x16, or the CSC table before archiving the new
  board result. If geometry is right but tone is shifted, capture the monitor
  OSD input-format/color-format page and the photo first.

## 14:48 mandatory clean-rebuild handoff

- Close any stale editor buffer for `adv7511_init_table.sv` and
  `hdmi_colorbar_vtc_top.v` without saving an older version; reopen from disk.
- In Vivado, reset synthesis (not only implementation) and then generate
  bitstream. The new synthesis DCP timestamp must be later than both current
  source timestamps above.
- Record and compare the new bit SHA-256; it must differ from
  `2E968C73C551BDB90C4498435DCF331A05E057C79248AD6F7EBB2B554D2B29BB`.
- Program only the fresh bit. Photograph both SW0 modes and record LED byte;
  expected `38` at SW0=0 and `B8` at SW0=1.
- Do not use the 14:29 photo to justify another register/CSC/byte-order change.
- Board PASS: White / Black / Red / Blue / Green solid bars, no vertical
  stripes, stable 640x480@60.

## 15:10 final handoff

- The HDMI colorbar mapping is frozen as board-proven. First read
  `4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01/evidence_report.md`.
- Do not change `physical_data`, `R0x15`, `R0x16`, `R0x48`, or the V1.3 CSC
  table for the existing 480p colorbar.
- The generic `hdmi_out_adv7511.v` now performs the same EES-331 port swap and
  has a 16-pixel regression PASS; keep this invariant during camera/VDMA work.
- Blocker: committing and pushing require permission to write `.git`. The next
  approved action is `git add` of the focused HDMI/source/evidence/log paths,
  then one `fix:` commit and `git push origin main`.
- Because the in-session approval path failed, run this from a terminal with
  Git write permission:
  `powershell -ExecutionPolicy Bypass -File E:\competition\4_metrics\scripts\upload_2026_09_06_hdmi_pass.ps1`.
  The script uses explicit paths and does not stage the 350 MB local quarantine.

## 15:22 cleanup handoff

- Keep the frozen physical byte swap and V1.3 register table for 480p HDMI.
- The simulation references live in `6_skill/modelsim-local-sim`,
  `6_skill/modelsim-gui-sim`, and `6_skill/vita-vivado-batch-sim`; adapt the
  Vivado skill before direct EES-331 use.
- If a quarantined file is needed, recover it from
  `4_metrics/logs/2026-09-06_workspace_cleanup_run01/root_quarantine/`; do not
  recreate transient libraries at the repository root.

## 15:28 upload handoff

- The focused commit excludes generated ModelSim libraries and the 350 MB
  local quarantine. If rerunning the upload script, it now checks formatting
  only for documents and skills, not for frozen hardware source.
- Uploaded commit: `4e7d8ca`. The next task can start from camera/VDMA
  integration without reopening the frozen 480p HDMI colorbar datapath.
- The next engineering step is camera/VDMA integration, not further colorbar
  register experiments.
- If rebuilding from source, expect the same synthesizable behavior; a later
  bit artifact alone is not a new board PASS unless photographed again.

## 15:56 project skill policy handoff

- First action for future sessions: follow
  `.codex/skills/project-workspace-policy/SKILL.md`, then the relevant domain
  skill.
- Engineering logs must resolve to `E:\competition\7_logs\YYYY-MM-DD`; raw runs
  must resolve to `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN`.
- Run `powershell -ExecutionPolicy Bypass -File E:\competition\4_metrics\scripts\audit_project_skill_paths.ps1`
  after changing any skill. PASS requires JSON `pass: true` with no failures.
- Keep `E:\competition\2_fpga` read-only unless the user explicitly authorizes
  that exact change in the current instruction.
- ModelSim/Vivado skill adaptation is path/POLICY PASS only; a real simulation
  still requires a new run directory, raw transcript, stable result marker, and
  an exact coverage-boundary statement.
- Uploaded policy baseline: commit `1c9d013` on `origin/main`. Start future
  skill changes from that revision, rerun the audit, and keep evidence in a new
  `4_metrics/logs` run directory.
