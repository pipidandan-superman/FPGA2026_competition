# Action Viewer reopen diagnosis

## Result

`DISPLAY_ONLY_REOPEN_CAUSE_CONFIRMED`

The action PL/video service did not show a new failure. The newly opened viewer was
started in display-only inference mode, so it never opened UDP action control and could
not send commands to the board/AXI/LED path.

## Evidence

New viewer run:
`E:\competition\4_metrics\logs\2026-09-13_175035_407501_gesture_viewer_run01`

- `status.json`: 584 inference frames, 590 complete video frames, zero lost frames,
  `error=null`, but `protocol=null`.
- `events.jsonl`: only `START`; it contains no `ACTION_INITIAL_CLEAR`,
  `ACTION_LINK_READY`, `ACTION_DECISION`, or `ACTION_CONFIRMED`.
- `predictions.jsonl` continued to grow, proving recognition/video continued while the
  action transport was absent.

Launcher contract:

- Directly opening `EES331_Action_Viewer.exe` is intentionally display-only.
- `E:\competition\8_tools\EES331_Action_Viewer_v1.0\Start_Action_Verification.ps1`
  launches the same EXE with `--action-control --action-host 192.168.240.10`.
- The v1.4 PL Reloader's `打开动作识别` button calls that action-enabled launcher.

## Safe recovery

Do not reload PL. Close only the current display-only viewer, then click
`打开动作识别` in the v1.4 PL Reloader. The new viewer must log
`ACTION_INITIAL_CLEAR` followed by `ACTION_LINK_READY` before LED testing.

No board command or file modification was performed for this diagnosis.

## Resolution confirmation

The user closed the display-only instance and launched Action Viewer through the v1.4
internal `打开动作识别` button. Run
`E:\competition\4_metrics\logs\2026-09-13_175441_976385_gesture_viewer_run01`
then recorded `ACTION_INITIAL_CLEAR` at sequence 9, continuing from board sequence 8,
followed by `ACTION_LINK_READY` and successful gesture acknowledgements through final
CLEAR sequence 17. The result contains 85 complete frames, zero lost frames,
`error=null`, and `action_error=null`.

The user physically confirmed the action behavior recovered. Resolution marker:
`ACTION_VIEWER_INTERNAL_LAUNCH_RECOVERY_PASS`. No PL reload was needed.
