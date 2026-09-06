# ADV7511 physical-swap board PASS

## Result

`2026-09-06` board run passed.

The monitor showed five solid bars in the intended order: White, Black, Red,
Blue, Green. There were no vertical chroma stripes and the 640x480p60 picture
was stable. Both source paths are represented by the top-level mode design.

## Frozen data-path decision

- RTL logical data is `selected_data = {Y, Cb/Cr}`.
- The EES-331 constrained port requires `physical_data =
  {selected_data[7:0], selected_data[15:8]}`.
- Do not restore the unswapped form: the earlier board image showed chroma
  stripes in the three chroma-bearing bars.
- Final key ADV7511 video settings are `R0x15=01`, `R0x16=38`, `R0x48=08`;
  the table is `ADI_CSC601_LR_TO_RGB_V1_3`.

## Evidence

| Item | Value |
|---|---|
| Board photo | `board_pass_white_black_red_blue_green.jpg` |
| Photo SHA-256 | `37414C330BCCEDCFB8DA7314FB0816169C681D0AFE0F754086076EF0274F27B3` |
| Source-edit screenshot | `source_byte_swap_edit.png` |
| Screenshot SHA-256 | `6BA7AB5E6964046B379B302D7B458E6377B51674531494EB678015772048139C` |
| ModelSim result | `MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch` |
| Stable result file | `mode_result.txt` |
| Generic output regression | `HDMI_VIDEO_PASS: pixels=16 mismatches=0 writes=4 start=1009900000` |
| Generic result file | `hdmi_video_result.txt` |

The ModelSim transcript stopped printing at the host's known `FileWatch`
terminal issue, but the simulator continued, generated a fresh WLF, and wrote
the stable PASS marker to `mode_result.txt`. Per the local simulation policy,
that stable marker is accepted when the transcript display is missing.

After the board PASS, the same byte-swap invariant was also applied to the
generic `hdmi_out_adv7511.v` output for future camera/VDMA integration. The
fast generic-output regression passed 16/16 pixels with zero YCbCr mismatches.
Its testbench was updated from an older coefficient set to the current BT.601
limited-range coefficients before this PASS.

## Build provenance

The tested bit was observed at 15:01 with SHA-256
`D57F6236CCD8F4D63B9FA9A5E338D531701E9FC2322CF2B3EF4FE29DE13CDC73` before
Vivado began another implementation run at 15:08. It is not committed because
the repository ignores `*.bit`. The logic was already the byte-swapped form;
the 15:05 source edits corrected comments and the regression testbench only.
The synthesis DCP used by that tested bit was 14:59:26.
