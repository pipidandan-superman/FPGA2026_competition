# PL Reloader v1.4 GitHub publication report

## Result

`PL_RELOADER_V14_PERSONAL_BRANCH_PUBLISH_PASS`

Target branch: `codex/full/pipidandan-superman`.

This publication is assembled in the independent worktree
`E:\competition_worktrees\FPGA2026_competition\pipidandan-superman`. The dirty main
workspace is not switched, stashed, reset, cleaned, or bulk-copied. The frozen
`2_fpga/` tree is excluded.

## User-requested cleanup

Only the following obsolete local release directories were removed from
`E:\competition\8_tools` after resolving and checking each absolute path:

| Directory | Files | Bytes | Result |
|---|---:|---:|---|
| `EES331_PL_Reloader_v1.0` | 1005 | 33,054,019 | removed |
| `EES331_PL_Reloader_v1.1` | 1005 | 33,055,661 | removed |
| `EES331_PL_Reloader_v1.2` | 1007 | 40,273,355 | removed |
| `EES331_PL_Reloader_v1.3` | 1007 | 40,274,978 | removed |

`EES331_PL_Reloader_v1.4`, source, build reports and all failed-run evidence remain.
The deleted binaries were untracked local build products; they are not recoverable by
undoing this Git publication, but can be rebuilt from retained source/evidence if ever
needed.

## Selected publication scope

- `3_host/pynq/pl_reloader/`: six v1.4 source, build, test and README files; no
  `__pycache__`.
- `8_tools/EES331_PL_Reloader_v1.4/`: complete 1007-file Windows release directory.
- `9_pynq/overlays/action_v1_20260913/`: updated camera wait logic, matching manifest
  and current README; fixed board-proven BIT/HWH remain unchanged.
- `8_tools/EES331_Gesture_Viewer_v1.0/`: only the action-capable EXE,
  `_internal/base_library.zip`, and usage note are changed; all other existing runtime
  files are reused.
- `8_tools/EES331_Action_Viewer_v1.0/`: lightweight action launcher and explanation;
  it reuses the adjacent Gesture Viewer runtime instead of duplicating roughly 761 MB.
- Root README/HANDOFF, tool/model/overlay/reloader READMEs, the new teammate board guide,
  and the four canonical daily log files.
- 29 selected evidence files: source tests, package verification, v1.3 first-frame
  failure audit, two v1.4 success runs, user physical confirmations, and the
  display-only reopen diagnosis/recovery.

Large prediction streams, screenshots, temporary build trees, credentials, SD images,
and unrelated historical runs are intentionally excluded. Password `xilinx` is the
user-requested UI default; it is not written to the evidence logs or command line.

## Verification before commit

- PL reloader source regression: 19 tests PASS.
- Gesture Viewer source regression: 5 tests PASS. The first invocation from the
  repository root failed only because the module directory was not on `sys.path`; the
  corrected invocation from `3_host/model_env` passed all tests without code changes.
- v1.4 packaged self-test: exit 0, `PL_RELOADER_SELF_TEST_PASS`, version 1.4.
- v1.4 package manifest: 1006 listed payload/runtime files, zero missing or hash
  failures; the 1007th physical file is the manifest itself.
- Shared action-capable Viewer self-test: exit 0.
- v1.4 EXE SHA-256:
  `aa46d21540109ce9387822802b18d96d493643663f735d8eea0bd641cd063d90`.
- Shared Viewer EXE SHA-256:
  `92790d9d232fa66604cab34c8560cce5439eba3f6a78a673aee44cc972b9e1aa`.
- Shared Viewer `base_library.zip` SHA-256:
  `ab41a8807584e1ed863491ce597364d24b0102683b316f5eeab679a2a85a4c68`.
- BIT SHA-256:
  `bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d`.
- HWH SHA-256:
  `64ff7724c56c97b52fac699168f762e30ea42b4d25910a30caf00f58c8b55ed0`.

## Board-evidence boundary

The first v1.4 run passed A-to-C loading and all five enabled gesture-to-LED mappings.
The independent second run passed after a user-confirmed power cycle. The viewer reopen
case proved that direct EXE launch was display-only (`protocol=null`); reopening from
v1.4 restored `ACTION_INITIAL_CLEAR`, `ACTION_LINK_READY`, and command acknowledgements
without another PL reload.

The combined evidence is 2/2 successful v1.4 transitions, not a 10/10 cold-start or
20/20 hot-reload reliability result. The second power cycle is user-confirmed because
v1.4 does not capture Linux boot ID. This publication stage itself performs no new board
command or PL download.

## Remote receipt

- Content commit: `63343aa314c27bd64f44210cc35ae144bdc16c13` (`feat: publish
  board-validated PL reloader v1.4`).
- Push: `612d7b3..63343aa` to `origin/codex/full/pipidandan-superman`.
- Git LFS upload: 20/20 objects, 72 MB, complete.
- Fresh `git fetch` plus `git ls-remote` returned remote branch HEAD
  `63343aa314c27bd64f44210cc35ae144bdc16c13`, exactly matching local HEAD.
- `git lfs push --dry-run origin HEAD` reported no remaining object to upload.
- The branch contains no staged/committed `2_fpga/` path and no PL reloader v1.0-v1.3
  path from this publication.

The four pre-existing untracked audit files in the independent worktree were left
unmodified and uncommitted. A small follow-up receipt commit will update this report;
the final remote HEAD must be rechecked after that push.
