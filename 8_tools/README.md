# Windows tools

This directory is the Windows host-tool delivery set for the EES-331 project.

## Project-built tools

- `EES331_UDP_Viewer.exe`: OV56 UDP video viewer. SHA-256 and board-video evidence are recorded in the project logs.
- `EES331_Gesture_Viewer_v1.0/`: folder-form FPGA UDP gesture viewer. Keep its executable and `_internal` directory together. See its Chinese usage guide.
- `sd_start_tool_v0.2/`: SD boot-image builder release and its source-hash manifest.

## Convenience tools and shortcuts

- `ComAssistant.exe` and `NetAssist.exe` are unsigned third-party utilities retained as supplied in the local workspace.
- `PuTTY (64-bit)/` and `Win32DiskImager.lnk` contain Windows shortcuts, not portable installers. Their targets must already exist on the destination PC.
- `wireshark/` is currently empty and therefore has no Git object to publish.

## Git storage

Executable files, DLL/PYD runtime libraries, model weights, ZIP files and shortcuts under this directory are stored with Git LFS. Clone with Git LFS installed and run `git lfs pull` if the working tree contains pointer files.

The gesture viewer bundle is large because it includes its own Windows Python, PyTorch CPU, OpenCV and model runtime. It does not require a separate Python installation, but the complete folder must remain intact.
