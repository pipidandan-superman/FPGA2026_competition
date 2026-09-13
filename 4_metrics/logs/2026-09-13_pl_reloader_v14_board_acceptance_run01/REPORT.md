# EES-331 PL Reloader v1.4 board acceptance

## Result

`V14_SINGLE_HOT_RELOAD_VIDEO_ACTION_LED_PASS`

One controlled original-A to action-C reload completed successfully with the v1.4
software payload. All five enabled model gestures completed the UDP-to-AXI sequence and
the user physically confirmed the corresponding PL LEDs.

This is a single-run functional PASS. It is not yet a repeated hot-reload reliability
PASS and does not prove that ten seconds is the minimum sufficient settle duration.

## Reload evidence

Host evidence:
`E:\competition\4_metrics\logs\2026-09-13_173347_248500_pl_reloader_gui_run01`

- Original service baseline: active/running, PID 594.
- Payload and hardware contract: PASS, 13 files.
- Original owner stop: `ORIGINAL_STOP_SAFE`.
- PL download: `PL_LOADED`, FPGA manager `operating`.
- Timed settle: 10.0 seconds, with real-time progress events.
- First-frame gate began at monotonic 132.362049; `VDMA_STREAM_STARTED` occurred at
  132.580987, about 0.219 seconds later and well inside the 30-second window.
- VDMA observed read/write transitions `[1,1]`.
- `VIDEO_READY_BEFORE_ACTION`, `ACTION_SERVICE_READY`, `ACTION_OVERLAY_READY`, and
  `CONTROLLER_COMPLETE` all occurred.
- GUI result: `PASS / ACTION_OVERLAY_READY`.

## Gesture/action evidence

Viewer evidence:
`E:\competition\4_metrics\logs\2026-09-13_173608_873155_gesture_viewer_run01`

- 272 inference frames; 278 complete received video frames; zero lost frames.
- Initial CLEAR sequence 1 completed.
- Stop: action 4, sequence 2, three-frame stable decision, command confirmed.
- Up: action 7, sequence 3, three-frame stable decision, command confirmed.
- Down: action 1, sequence 4, three-frame stable decision, command confirmed.
- Thumbs up: action 6, sequence 5, three-frame stable decision, command confirmed.
- Thumbs Down: action 5, sequence 6, three-frame stable decision, command confirmed.
- Automatic CLEAR sequence 7 and close CLEAR sequence 8 completed.
- No viewer error or action-link error was recorded.

## Physical confirmation

The user stated: `成功，全部手势对应led成功`.

The separate manual record is:
`E:\competition\4_metrics\logs\2026-09-13_173608_873155_gesture_viewer_run01\physical_confirmation.json`.

Confirmed mapping: Stop/4 -> LED4, Up/7 -> LED7, Down/1 -> LED1,
Thumbs up/6 -> LED6, Thumbs Down/5 -> LED5.

## Evidence boundary and current state

- Board function for this run: PASS.
- Model-to-UDP-to-PS-to-AXI-to-PL LED mapping for all five enabled gestures: PASS.
- Repeated A-to-C reload reliability: NOT TESTED by this single run.
- Root cause: timing sensitivity remains the leading explanation, but the single 1-second
  failure versus 10-second success is not a controlled minimum-time proof.
- Original-video restoration after this successful run: NOT REQUESTED / NOT VERIFIED.
- No additional board command was issued while producing this report.
