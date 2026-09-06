# 2026-09-06 Daily Plan

- Current judgment: confirmed by board test. The 2026-09-05 17:08 run01 bit with push-pull SDA and ILA displays; today's open-drain SDA build does not. ILA insertion is not the root cause. Project logs are now rooted exclusively at `7_logs`.
- Readback judgment: run01 displays while raw readback reports mismatches. Therefore raw full-byte mismatch cannot be treated as proof that ADV7511 initialization is broadly wrong. The checker must compare functional fields, not reserve/status/condition bits.
- Objective: distinguish chip failure from board-level I2C electrical/configuration faults before any replacement.
- Priority: measure VADJ, SDA/SCL idle/high levels and waveforms; verify reset, address, and continuity.
- Non-goal: do not change video format or replace ADV7511 based only on failed readback.
- Deliverable: a board-level fault-isolation conclusion and next measurement record.

## 12:30 update: ADV7511 configuration rewrite

- Current judgment changed from "first isolate I2C electrical health" to "rewrite
  the register configuration from cross-checked UG/API/driver evidence." The
  board's I2C transaction flow has already demonstrated coherent address/data
  readback, while the original table had incomplete CSC and an incompatible
  YCbCr-output declaration.
- Main objective: replace the incomplete 34-entry table with a complete
  55-entry RGB444/DVI-safe configuration that accepts the physical byte-swapped
  16-bit YCbCr422 bus.
- Priorities: lock the input mapping, program the complete CSC, remove stale AVI
  metadata use, update masked readback, and validate both positive and negative
  ModelSim cases.
- Non-goals: no replacement of the IC, no change to video timing, and no blind
  byte-order trial.
- Expected deliverables: rewritten `adv7511_init_table_pkg.sv`, synchronized
  testbench, retained physical byte-swap with documented Style 1 rationale, raw
  simulation evidence, and a rebuild/board-test handoff.

## 13:00 update: V2.0 board result and V2.1 objective

- V2.0 board result: vertical stripes disappeared, proving physical Style 1 +
  right justification is correct. The first three bars collapsed to one magenta
  region, so the ADV7511 RGB/CSC stage is not accepted as the final solution.
- New objective: remove the uncertain CSC stage and use the shorter, standard
  HDMI YCbCr422 output path. Correct AVI metadata is now enabled.
- Expected deliverable: a V2.1 44-entry configuration table, positive/negative
  ModelSim evidence, and a fresh board test.

## 13:05 update: final source-state audit

- Verify that the V2.1 table, physical byte swap, top-level output assignment,
  configuration testbench, and Vivado source references all agree.
- Upgrade the stale mode testbench from checking only the internal Style 3 word
  to checking the board-level physical Style 1 mapping.
- Deliver current hashes and a separate Mode-TB PASS record before rebuilding.

## 13:12 update: package project reference

- Change the Vivado project from the imported local package copy to an explicit
  external reference to `0_diaplay_test/rtl/hdmi_new/adv7511_init_table_pkg.sv`.
- Keep the stale imported file on disk but leave it unreferenced, so future
  package edits are made in the canonical source.

## 13:22 update: table becomes an instantiated module

- Convert the V2.1 configuration data from a SystemVerilog package into the
  `adv7511_init_table` module so it appears in the Vivado instance hierarchy.
- Keep all register values, write order, and masked-readback rules unchanged.
- Verify both configuration simulations and the top-level mode simulation after
  the format change.

## 13:55 update: user RGB/Style-3 board failure

- Diagnose the magenta/blue image and the user's current RGB/CSC edits.
- Preserve the user's unswapped Style 3 bus direction, but make the ADV7511
  input style, AVI metadata, checksum, and table index width agree with it.
- Do not claim board success until the corrected bitstream is tested.

## 14:25 update: coherent CSC601 source fix

- Current judgment: the remaining image error is not a choice between swapping
  and not swapping physical_data. Three faults were active: the 13:46 bit did
  not contain the 13:55 source fixes, the CSC table was not an ADI table, and
  the RGB-to-YCbCr converter had incorrect luminance scaling plus misaligned
  blue input.
- Main objective: make the RGB/CSC Style-3 path internally coherent and leave
  the user to rebuild in the already-open Vivado session.
- Priorities: use the ADI CscYcc601ToRgb table, correct BT.601 limited-range
  conversion, align SW0 direct data with converted data, and retain
  unswapped {Y, Cb/Cr} Style 3.
- Non-goals: no remote Vivado launch against the open project, no further bus
  swapping, and no board PASS claim without the user's new bit/photo.
- Expected deliverables: updated source, three ModelSim PASS records, source
 hashes, and a post-rebuild board checklist.

## 14:25 update: coherent CSC601 source fix

- Current judgment: the remaining image error is not a choice between swapping
  and not swapping physical_data. Three faults were active: the 13:46 bit did
  not contain the 13:55 source fixes, the CSC table was not an ADI table, and
  the RGB-to-YCbCr converter had incorrect luminance scaling plus misaligned
  blue input.
- Main objective: make the RGB/CSC Style-3 path internally coherent and leave
  the user to rebuild in the already-open Vivado session.
- Priorities: use the ADI CscYcc601ToRgb table, correct BT.601 limited-range
  conversion, align SW0 direct data with converted data, and retain unswapped
  {Y, Cb/Cr} Style 3.
- Non-goals: no remote Vivado launch against the open project, no further bus
  swapping, and no board PASS claim without the user's new bit/photo.
- Expected deliverables: updated source, three ModelSim PASS records, source
  hashes, and a post-rebuild board checklist.

## 14:48 update: stale 14:29 board result

- Current judgment: the latest photo showing stripes in the Red/Blue/Green bars
  is not a valid test of V1.3 or of the 14:28 top-level fix.
- The 14:29 bit was implemented from a synthesis DCP completed at 14:27:03;
  the top-level source was saved at 14:28:03 and the V1.3 table at 14:44:56.
- Main objective remains one clean rebuild whose synthesis starts only after
  all current source timestamps, followed by a fresh hash/photo test.

## 15:10 update: board PASS and upload

- Current judgment: the byte-swapped physical port, V1.3 ADI BT.601 CSC, and
  Style-compatible 4:2:2 register set are now board-proven.
- Main objective: freeze the mapping in comments/TB, archive photo and stable
  simulation marker, commit the focused HDMI fix, and push to GitHub.
- Non-goals: no further CSC or byte-order changes, no unscoped commit of build
  artifacts, and no interpretation of a later comment-only rebuild as a new
  board result.

## 15:22 update: cleanup, skill archive, and push

- Current judgment: the successful HDMI datapath is frozen; cleanup must only
  touch root transients and generated libraries outside `2_fpga`.
- Main objective: archive root transients, copy three simulation skills,
  update logs, and push the focused result to GitHub.
- Non-goals: no deletion of quarantined material, no changes under `2_fpga`,
  and no commit of oversized generated artifacts.

## 15:56 update: project skill adaptation

- Current judgment: the active daily-log override was correct, but copied
  simulation/Vivado material still contained generic roots, historical ViTA
  executable paths, and an old desktop target.
- Main objective: make every project skill resolve writable output to the fixed
  `E:\competition` evidence/log roots and protect the frozen `2_fpga` baseline.
- Priorities: add a mandatory workspace-policy skill, adapt all `6_skill`
  documentation/scripts, add a repeatable path audit, and validate.
- Non-goals: do not edit, delete, move, rebuild, or re-synthesize anything under
  `2_fpga`; do not claim a Vivado simulation PASS because only path-tooling
  validation was run.
- Expected deliverables: adapted active/archive skill layers, EES launcher and
  checker scripts, passing skill-path audit, evidence report, and updated daily
  handoff.
