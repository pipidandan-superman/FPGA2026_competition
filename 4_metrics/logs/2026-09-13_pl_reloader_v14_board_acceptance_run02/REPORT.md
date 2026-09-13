# EES-331 PL Reloader v1.4 power-cycle reproduction acceptance

## Result

`V14_POWER_CYCLE_REPRODUCTION_PASS_RUN02`

The user physically powered the board off, restarted it, and reported that v1.4 again
loaded the action PL correctly. The independent second-run logs prove a fresh original
camera service baseline followed by complete PL/video/action readiness and five gesture
command acknowledgements.

The physical power transition is user-confirmed because v1.4 did not yet record Linux
boot ID. It must not be relabelled as machine-captured boot-ID evidence.

## Reload evidence

Host run:
`E:\competition\4_metrics\logs\2026-09-13_174815_607100_pl_reloader_gui_run01`

- Original `ees331-camera` active/running with PID 596.
- Payload/HWH contract PASS and `ORIGINAL_STOP_SAFE`.
- `PL_LOADED`, FPGA manager state `operating`.
- Ten-second timed sensor-settle gate completed.
- First-frame wait began at monotonic 136.866808; `VDMA_STREAM_STARTED` occurred at
  137.101721, about 0.235 seconds later.
- Both VDMA directions observed transitions `[1,1]`.
- `VIDEO_READY_BEFORE_ACTION`, `ACTION_SERVICE_READY`, `ACTION_OVERLAY_READY`, and
  `CONTROLLER_COMPLETE` all occurred.
- GUI result: `PASS / ACTION_OVERLAY_READY`; no first-frame timeout.

## Second gesture run

Viewer run:
`E:\competition\4_metrics\logs\2026-09-13_174929_021251_gesture_viewer_run01`

- 75 inference frames, 80 complete video frames, zero lost frames.
- No viewer or action-link error.
- Up/7, Down/1, Thumbs up/6, Thumbs Down/5, and Stop/4 each met the three-frame stable
  gate and returned matching `seq == done_seq` acknowledgements.
- Automatic CLEAR and close CLEAR completed; final sequence was 8/action 0.

## Manual confirmation and boundary

User statement: `断电后重新运行运行1.4加载PL扔正确`.

Manual record:
`E:\competition\4_metrics\logs\2026-09-13_174929_021251_gesture_viewer_run01\physical_confirmation.json`.

Combined status after run01 and this run02:

- Two successful v1.4 A-to-C loads are evidenced.
- The second success followed a user-confirmed full power cycle.
- All five enabled gesture commands completed in both runs; the first run additionally
  has explicit per-LED physical mapping confirmation.
- This improves reproducibility confidence but is not the planned 10/10 cold-start or
  20/20 hot-reload reliability acceptance.
- Original-video restoration after the successful second run was not requested or
  verified in this report.
