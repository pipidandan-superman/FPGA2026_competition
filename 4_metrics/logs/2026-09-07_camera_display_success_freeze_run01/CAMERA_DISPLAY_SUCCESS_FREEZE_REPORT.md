# Camera Display Success Freeze Report

- Time: 2026-09-07 21:55
- Workspace: `E:\competition`
- Project: `E:\competition\2_fpga\0_diaplay_test`
- Freeze result: `BOARD_VISUAL_PASS`
- Formal acceptance boundary: `FULL_UART_ACCEPTANCE_PASS` is **not** claimed because no complete UART capture was supplied for this final run.

## 1. Board Evidence

Three user-supplied success photos were archived in this directory:

| File | SHA-256 | Size (bytes) |
|---|---|---:|
| `DISPLAY_SUCCESS_PHOTO_01.jpg` | `86DB0EEC5299904266BDAD9735E14DDAD9DECC912087C1739F33F1F386CF83F5` | 206106 |
| `DISPLAY_SUCCESS_PHOTO_02.jpg` | `7339D41B04135D136DACA92661EDCC612563017BE334B87CA2E5BC63E0963D2F` | 166276 |
| `DISPLAY_SUCCESS_PHOTO_03.jpg` | `0B780CD8228FD8485D521DA1E10E32530E6114BC46D64CF6FB93B9D8AB88B51D` | 180401 |

The photos were captured after the final BIT/XSA/ELF sequence and show a live OV5640 camera image on HDMI with the existing PL overlay intact. The evidence level is therefore visual board PASS only.

## 2. Frozen Artifacts

All binary artifacts and representative sources below are copied under `frozen_artifacts/`.

| Artifact | SHA-256 | Size (bytes) |
|---|---|---:|
| `display_test_wrapper.bit` | `16DBACBFCA755D69B08AE1720AF10D6C642E97B12F34F410241CEC1F29130624` | 4045696 |
| `display_test_wrapper.xsa` | `7374BD4EE2D30C726FC0135E1960BA2BE19BD22C3B9D75B0AB0BBEE1CE64A6E1` | 519790 |
| `app_component.elf` | `040B57D048D76A60AAED8262F4E7E05204E6A96E8EF01AD6598BE4EE93BDD990` | 219968 |
| `main.c` | `705B0317DC688022DF5956EC985A041D87E47D4348BFB6107C1D614D6CE5F9C0` | 20956 |
| `display_test.bd` | `231E9F7221EF371A3BEA2DDEB79F967933C80D1ECCD0D105913C92592D50C003` | 76815 |
| `display_test_axi_vdma_0_0.xci` | `2C442A8B31361CA2E67121668B7A1E43EA018C146D923E3AC9F1D8E3198101E1` | 139783 |
| `pix_frame_dispaly.v` | `459BDB36FFF8E9655198E2B1F57DCC3621D520C1011152E9E71606EB88EC36D5` | 3016 |
| `pin_zynq7020_cam.xdc` | `E523CE91F3AD3350F828E7681CFC179040C8C942D5059D956A43AB8CDBE32B2A` | 5236 |

## 3. Final Configuration

The final successful PL configuration contains:

- AXI VDMA `C_S2MM_LINEBUFFER_DEPTH=1024`.
- AXI VDMA `C_MM2S_GENLOCK_MODE=3` (dynamic slave).
- AXI VDMA `C_S2MM_GENLOCK_MODE=2` (dynamic master).
- AXI VDMA `C_USE_S2MM_FSYNC=2` (AXIS TUSER frame sync).
- `C_NUM_FSTORES=3`.
- Restored board-proven sync polarity in `pix_frame_dispaly.v`:
  - `hdmi_hsync <= ~vio_hsync;`
  - `hdmi_vsync <= ~vio_vsync;`

The final application source is the camera VDMA path at `main.c` hash `705B0317DC688022DF5956EC985A041D87E47D4348BFB6107C1D614D6CE5F9C0`.

## 4. Build Quality

The archived routed reports establish:

- Routable nets: 11060.
- Fully routed nets: 11060.
- Routing errors: 0.
- WNS: 9.510 ns.
- TNS: 0.000 ns.
- TNS failing endpoints: 0.
- Vivado timing report statement: `All user specified timing constraints are met.`

Timestamps align as one final sequence: implementation BIT at 21:30, XSA export at 21:31, ELF build at 21:33, success photos after 21:50.

## 5. Required Recovery Procedure

Use this exact procedure to reproduce the frozen result:

1. Program only the frozen BIT with SHA-256 `16DBACBFCA755D69B08AE1720AF10D6C642E97B12F34F410241CEC1F29130624`.
2. Load only the frozen ELF with SHA-256 `040B57D048D76A60AAED8262F4E7E05204E6A96E8EF01AD6598BE4EE93BDD990`.
3. Perform one manual board reset. Current evidence identifies this step as required for HDMI signal appearance.
4. Confirm the live camera image and PL overlay remain visible.
5. For formal acceptance, capture complete UART from ELF startup through at least 60 seconds and archive it as a new evidence run.

Do not mix this frozen pair with a regenerated BIT, rebuilt ELF, or unrelated source change when reproducing this result.

## 6. Acceptance Boundary

This run is classified as:

- `BOARD_VISUAL_PASS`: yes.
- `FULL_UART_ACCEPTANCE_PASS`: no evidence, not claimed.

A later formal UART run must use this exact BIT and ELF pair. It must preserve the full serial text, include the normal startup gates and 60-second heartbeat window, record any S2MM/MM2S error honestly, and archive the run before changing the acceptance label.
