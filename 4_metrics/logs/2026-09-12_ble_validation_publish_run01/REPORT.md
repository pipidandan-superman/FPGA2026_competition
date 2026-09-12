# BLE milestone publication review

User request: update engineering logs and corresponding project files, publish to the
user's personal branch. Target: codex/full/pipidandan-superman, not main.
Existing open PR: https://github.com/pipidandan-superman/FPGA2026_competition/pull/5
(head=personal branch, base=main). It will include this commit when pushed; no merge requested.

## Scope

- Development plan v1.1, dedicated validation status, README/HANDOFF entry points.
- Existing independent BLE diagnostic source under 2_fpga/1_ble_test (copied unchanged;
  no video-baseline file, generated XPR, bitstream, LTX or vendor IP tree uploaded).
- BLE console source, profiles, 8 unit tests, build script and user instructions.
- Selected implementation summaries and raw payload events, unpair result and remote reads.
- Four focused daily-log publication snapshots under 7_logs/2026-09-12. These clearly
  identify themselves as task-scoped summaries. Complete local multi-task journals remain
  at the canonical E:/competition/7_logs root and are not overwritten by the snapshots.
- Vivado standalone launcher fix: ignore echoed failure-handler source when checking actual
  diagnostic lines; add a prelaunch input manifest. No build/hardware run in this publication.

## Acceptance and limitations

Reviewed source snapshot passes all 8 BLE console unit tests. Independently rechecked raw
events: 11 BLE writes match 11 COM4 receptions; 11 COM4 writes match 11 notification payloads;
166 bytes per direction, connected 61.703 s, only an intentional final disconnect.
See verification.json and unit_tests.txt. No new board test is represented by this upload.

Plan's original B0/B1/B2 criteria remain unchanged: this is a short prevalidation, not
1000 frames, fragmentation/CRC, ten-minute concurrent traffic, reconnection/reset endurance,
or robotic-arm interoperability. PL transparent bridge is not a byte-aware UART/FIFO/CSR
controller; reset CDC limitations remain explicit. AXI-Lite/BRAM work remains design-only.

## Privacy and artifact selection

Explicit copy candidates: selected_copy_paths.txt, with per-file hashes in copy_manifest.json.
Excluded: real PIN captures, pairing dialogs/screenshots, nearby-device scan lists, BLE debug
logs containing unrelated devices, driver archives, generated Vivado trees, wheelhouse,
venv, EXE/DLL dependency bundles and bit/LTX binaries. Target's already-scoped BLE address
remains in device-specific test scripts; no secrets or unrelated device inventory is needed.
The number 654321 in the HDL testbench is explicitly synthetic, not a device credential.

Reports may name complete local-only run files as provenance; these names are not a claim
that every original is included. The decisive payload events, results and scripts are included.
Unpair/read raw events are selected; lower-level scanner logs are deliberately omitted.

## Git discipline

Original E:/competition worktree remains on its old main checkout with unrelated dirty
changes untouched. Publication uses the existing personal-branch worktree, preserving
its four pre-existing untracked history files. Only named selected files are staged.
origin/main is already an ancestor of the personal branch at preflight; no merge is needed.
Normal push only, no force, no main push and no PR merge. Final remote SHA confirmation
is recorded locally in push_receipt.json after upload; this pre-push report is not a receipt.
