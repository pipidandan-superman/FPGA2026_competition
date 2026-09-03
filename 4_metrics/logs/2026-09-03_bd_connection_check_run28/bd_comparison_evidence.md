# OV5640 + HDMI BD comparison evidence

Date: 2026-09-03  
Status: STATIC_CONNECTION_CHECK_COMPLETE

## Inputs

- Reference BD: `E:\FPGA_Project\2020_2\cam_vdma_hdmi_true\7_proj\vmda_HDMI_cam\vmda_test.srcs\sources_1\bd\design_1\design_1.bd`
  - SHA256: `AB7EE29DC214FDF2466871A42593E4C7476D8B528F059596D97526F5440F2845`
- Current BD: `E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.srcs\sources_1\bd\display_test\display_test.bd`
  - SHA256: `A644941A42A105396888D327C243B1D7EEAD3F81CD3D7EF31EC6EC4882CC5A63`

## Shared RTL identity

| Module | Reference SHA256 | Current SHA256 | Result |
|---|---|---|---|
| `cam_captrue_data` | `4511CC14AF78FBCC44CC4A68E1F1CFDA62FDD343D22EE3517E0E13D372B57EFC` | same | IDENTICAL |
| `ov5640_cfg_top` | `196AA7FF561ECF841AAD1144A8BF2BBB16BD3C6C2865EC8D72C7DEC0A266BC25` | same | IDENTICAL |
| `pix_frame_display` | `188A4DC97FF20639338009034C1A39BCD61AAF79E2083BCB182003ADC46E47F7` | same | IDENTICAL |

## Key findings

- Camera pin mapping, camera capture to Video In, Video In to VDMA S2MM, VDMA S2MM to HP1, HP0 to VDMA MM2S, VDMA MM2S to Video Out, VTC timing, Video Out to `pix_frame_display`, and `pix_frame_display` to the new HDMI module all match at the required functional boundary.
- AXI control reaches VDMA through GP0 in both projects. The current project uses SmartConnect for this control edge; the reference uses AXI Interconnect. This is an expected topology difference.
- VDMA memory ports use HP0 for MM2S and HP1 for S2MM in both projects.
- Zynq part, external clock, PS FCLK0 frequency, HDMI output architecture, IP versions, and interrupt scope are different project baselines and are not counted as errors.
- VDMA configuration matches except `C_S2MM_LINEBUFFER_DEPTH`: reference is 1024 and current generated value is 512. This is nonblocking but should remain visible for board validation.
- Current `pix_frame_display/rom_data` is tied to constant zero while the reference connects it to ROM output. This changes optional overlay behavior but not the camera-to-display main path.

## Deliverable

`E:\competition\2_fpga\0_diaplay_test\doc\bd_ov5640_hdmi_connection_checklist.md`
