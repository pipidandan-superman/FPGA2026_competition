# Windows tools

This directory is the Windows host-tool delivery set for the EES-331 project.

## 2026-09-13 current PL/action delivery

- `EES331_PL_Reloader_v1.4/` is the only supported PL reloader release. v1.0 through v1.3 are obsolete and intentionally excluded from the Git delivery.
- `EES331_Gesture_Viewer_v1.0/` contains the shared frozen model runtime. Direct EXE launch is display-only.
- `EES331_Action_Viewer_v1.0/Start_Action_Verification.ps1` is the compatibility launcher used by PL Reloader v1.4; it starts the shared viewer with `--action-control` and therefore enables AXI/LED output.
- Keep every release folder intact and run `git lfs pull` after cloning. The exact teammate procedure is in `1_docs/doc/ees331_pl_reloader_v14_board_guide_2026-09-13.md`.

The v1.4 reloader completed two A-to-C board transitions on 2026-09-13, with the second run following a user-confirmed power cycle. This is a 2/2 observation, not a long-run reliability guarantee.

## Project-built tools

- `EES331_UDP_Viewer.exe`: OV56 UDP video viewer. SHA-256 and board-video evidence are recorded in the project logs.
- `EES331_Gesture_Viewer_v1.0/`: folder-form FPGA UDP gesture viewer. Keep its executable and `_internal` directory together. See its Chinese usage guide.
- `EES331_PL_Reloader_v1.4/`: board-validated online PL reloader with the fixed action BIT/HWH payload, 10-second sensor settle and 30-second first-frame gate.
- `sd_start_tool_v0.2/`: SD boot-image builder release and its source-hash manifest.

## Convenience tools and shortcuts

- `ComAssistant.exe` and `NetAssist.exe` are unsigned third-party utilities retained as supplied in the local workspace.
- `PuTTY (64-bit)/` and `Win32DiskImager.lnk` contain Windows shortcuts, not portable installers. Their targets must already exist on the destination PC.
- `wireshark/` is currently empty and therefore has no Git object to publish.

## Git storage

Executable files, DLL/PYD runtime libraries, model weights, ZIP files and shortcuts under this directory are stored with Git LFS. Clone with Git LFS installed and run `git lfs pull` if the working tree contains pointer files.

The gesture viewer bundle is large because it includes its own Windows Python, PyTorch CPU, OpenCV and model runtime. It does not require a separate Python installation, but the complete folder must remain intact.
