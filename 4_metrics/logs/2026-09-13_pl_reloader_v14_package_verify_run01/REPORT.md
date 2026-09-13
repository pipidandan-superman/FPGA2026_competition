# EES-331 PL Reloader v1.4 offline delivery report

## Result

`PL_RELOADER_V14_PACKAGE_PASS`

This stage is an offline software/package PASS only. No SSH connection, service stop,
PL download, MMIO access, reboot, or board test was performed. The frozen
`E:\competition\2_fpga` tree was not modified.

## User-requested change

- Increased the post-download OV5640 timed settle gate from 1.0 s to 10.0 s.
- Increased the first real VDMA slot-transition window from 5.0 s to 30.0 s.
- Added one-second `SENSOR_SETTLE_PROGRESS` and `FIRST_FRAME_WAIT` events.
- Preserved fail-closed behavior: 30 s without a real transition still emits
  `FIRST_FRAME_TIMEOUT`, stops the action runtime, and requests original-video recovery.
- The timed gate is explicitly labelled `TIMED_WAIT_NOT_SENSOR_PROOF`; it does not claim
  SCCB, PCLK, VSYNC, capture, or DDR readiness.

## v1.4 observability

- The board controller incrementally forwards new action-service journal lines.
- The Windows SSH wrapper streams stdout into the GUI and durable application log while
  the command is running instead of displaying it only after process exit.
- Controller READY deadline is 75 s and host load-command timeout is 180 s, covering the
  10 s settle plus the 30 s first-frame window and normal setup/cleanup time.

## Verification

- Source regression: 19 tests passed with `ResourceWarning` promoted to an error.
- Syntax compilation: `PL_RELOADER_V14_SYNTAX_PASS`, 3 files.
- Packaged self-test: exit 0, version 1.4, `PL_RELOADER_SELF_TEST_PASS`.
- Package manifest: 1006 listed files, zero hash failures; 1007 physical files including
  `package_manifest.json` itself.
- Payload manifest: 13 verified files.
- Packaged camera source contains 10.0 s settle and 30.0 s first-frame constants.
- BIT SHA-256 unchanged:
  `bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d`.
- HWH SHA-256 unchanged:
  `64ff7724c56c97b52fac699168f762e30ea42b4d25910a30caf00f58c8b55ed0`.
- EXE SHA-256:
  `aa46d21540109ce9387822802b18d96d493643663f735d8eea0bd641cd063d90`.
- AskPass SHA-256:
  `156e1a0e033d1230e361b0f1cb83f088f33ec314b873376b6372ac67a34f73a1`.

Raw evidence:

- `E:\competition\4_metrics\logs\2026-09-13_pl_reloader_v14_code_run02\tests.txt`
- `E:\competition\4_metrics\logs\2026-09-13_pl_reloader_v14_code_run02\syntax.txt`
- `E:\competition\4_metrics\logs\2026-09-13_pl_reloader_v14_build_run01`
- `E:\competition\4_metrics\logs\2026-09-13_pl_reloader_v14_package_verify_run01\packaged_self_test.json`
- `E:\competition\4_metrics\logs\2026-09-13_pl_reloader_v14_package_verify_run01\verification.json`

## Deliverable and next gate

Deliverable: `E:\competition\8_tools\EES331_PL_Reloader_v1.4`.

Board status: `NOT_RUN`. The next authorized action should be one controlled v1.4 load
from a user-confirmed dynamic original HDMI/UDP baseline. Do not repeat the load after a
failure; preserve the first v1.4 evidence and confirm automatic original-video recovery.
