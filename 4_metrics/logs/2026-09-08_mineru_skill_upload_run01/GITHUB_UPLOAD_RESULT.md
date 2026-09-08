# Personal Branch Upload Result

Date: 2026-09-08

## Target

- Repository: `pipidandan-superman/FPGA2026_competition`
- Branch: `codex/full/pipidandan-superman`
- Clean worktree: `E:\competition_worktrees\FPGA2026_competition\pipidandan-superman`
- Remote HEAD after content push: `192323b63854f1d00c146122cd969480f66cc627`
- Verification: local HEAD equals `git ls-remote` result.

## Uploaded Commits

1. `7b6dcc6` — `docs: document OV5640 HDMI verified release`
2. `192323b` — `feat: add project MinerU document parsing`

## Camera And HDMI Version

The personal branch contains the board-proven OV5640 camera plus ADV7511 HDMI display version identified by tag `camera-hdmi-visual-pass-20260907`.

- Result boundary: `BOARD_VISUAL_PASS`
- Video path: OV5640 DVP → Video In to AXI4-Stream → VDMA S2MM → DDR → VDMA MM2S → Video Out/VTC → ADV7511 → HDMI
- Display: live 640×480 camera image displayed correctly over HDMI
- UART boundary: full startup-to-60-second UART acceptance remains pending and is not claimed by this upload.

Required board recovery sequence:

1. Program the frozen BIT.
2. Load the paired ELF.
3. After transfer, manually reset the camera capture once.
4. Inspect the live image after the reset.

The current board-proven behavior is that the camera capture needs one reset after BIT/ELF transfer before the live image displays normally.

## Necessary `2_fpga` Files

- Before this upload, the personal branch already contained every one of the 66 source-tracked files under the local `2_fpga/0_diaplay_test` baseline with no content difference when CRLF/LF differences were ignored.
- The branch also contained the four `rtl/data_pre` files and selected project metadata from its earlier reviewed source publication.
- This upload adds `2_fpga/0_diaplay_test/doc/camera_hdmi_correct_version_2026-09-08.md`, bringing the branch count under `2_fpga/0_diaplay_test` to 76 tracked files.
- No camera RTL, HDMI RTL, BD, XCI, XDC, XPR, or Vitis application source was overwritten because the remote personal branch already held the matching board-proven content.
- `_ide`, BSP, platform caches, synthesis/implementation temporary trees, compile databases, and other generated directories were not newly uploaded.
- The untracked local `rtl/data_pre` copies were not treated as new dependencies because those modules are not instantiated by the current camera + HDMI BD; corresponding reviewed files already existed on the personal branch.

## Frozen Artifact Pair

The exact board-proven artifacts were already tracked under `4_metrics/logs/2026-09-07_camera_display_success_freeze_run01/frozen_artifacts/` and remain present on the remote branch:

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `display_test_wrapper.bit` | 4,045,696 | `16DBACBFCA755D69B08AE1720AF10D6C642E97B12F34F410241CEC1F29130624` |
| `display_test_wrapper.xsa` | 519,790 | `7374BD4EE2D30C726FC0135E1960BA2BE19BD22C3B9D75B0AB0BBEE1CE64A6E1` |
| `app_component.elf` | 219,968 | `040B57D048D76A60AAED8262F4E7E05204E6A96E8EF01AD6598BE4EE93BDD990` |

Do not mix this BIT, XSA, or ELF with newly generated artifacts when reproducing the visual PASS.

## MinerU And OV5640 Documentation

The upload also includes:

- Project-local active and reusable MinerU skills.
- Mandatory MinerU routing and project evidence rules.
- `1_docs/OV5640配置审计报告_2026-09-08.md`.
- The 251-entry parsed OV5640 register list.
- MinerU skill adaptation report and minimal smoke-test marker/result evidence.

The full datasheet PDF and bulk MinerU images/output tree were not uploaded.

## Exclusions And Safety

- No direct push to `main` was performed.
- No force push, reset, clean, or history rewrite of the remote branch was performed.
- The polluted source workspace at `E:\competition` was not switched, reset, cleaned, or bulk-staged.
- Named paths were staged explicitly; `git add .` and `git add -A` were not used.
- The push delta contained no newly uploaded `_ide`, `.cache`, `.gen`, `.runs`, `.sim`, `.hw`, `xsim.dir`, `display_test_plat`, compile database, or Vitis generated-tree paths.

## Evidence Files

- `source_git_status.txt`
- `source_git_branches.txt`
- `source_untracked_paths.txt`
- `source_tracked_changes.txt`
- `tracked_2_fpga_0_diaplay_test_differences.csv`
- `semantic_2_fpga_differences.csv`
- `copied_file_manifest.csv`
- `prepush_name_status.txt`
- `push_first.txt`
- `remote_head_after_push.txt`
- `local_head_after_push.txt`

## Result

`PERSONAL_BRANCH_UPLOAD_PASS`
