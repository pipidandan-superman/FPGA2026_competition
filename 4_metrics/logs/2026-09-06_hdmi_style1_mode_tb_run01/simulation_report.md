# HDMI physical Style 1 mode simulation report

Date: 2026-09-06 13:00  
Run: `2026-09-06_hdmi_style1_mode_tb_run01`  
Result: PASS

## Scope

This run audits the latest source state after the V2.1 ADV7511 rewrite:

1. `adv7511_init_table_pkg.sv` remains V2.1 with 44 writes and six masked
   readback checks.
2. `hdmi_colorbar_vtc_top.v` retains the active physical-bus byte swap:
   `physical_data = {selected_data[7:0], selected_data[15:8]}`.
3. `HDMI_DATA` is driven from `physical_data`, not directly from the internal
   logical Style 3 word.
4. `hdmi_colorbar_vtc_top_mode_tb.sv` was updated from V1.0 to V1.1 so the
   board-lane check uses `physical_data` instead of `selected_data`. It now
   explicitly covers the physical `{Cb/Cr, Y}` mapping to `HDMI_DATA`.

## Execution

The mandatory `vsim -c` path compiled all sources but failed design loading with
the host-specific Tcl error:

```text
Error: can't read "FileWatch(fileName)": no such element in array
```

The same run-local `run_mode.do` was then executed through the approved ModelSim
GUI fallback. Complete disk transcript:
`modelsim_transcript.txt`.

## Result

```text
MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch
```

The test checks both SW0 modes and verifies that the frame-safe mode switch does
not alter the active frame. The V1.1 board-lane assertion checks that the output
bus equals the current physical Style 1 word.

This is RTL simulation evidence only. It does not replace a fresh board test.

## SHA-256

```text
02C6DC9620215C2914251DDD6C3D2B8E7C1C79F7EC850A77E32B36E77538D48A  adv7511_init_table_pkg.sv
16EEFA17DC5357F74AE0146CE36F911DFF505470E6B5BF35D9AFF2FAF6831447  hdmi_colorbar_vtc_top.v
8887B57DCDDDB5630B81A2C84E5E0C48C3E28AD51BCF4804073C237D302584BE  adv7511_cfg_top_tb.sv
734A933CAF399203C13212DB6DF7055B22FD81A4E506D428DE1C07F88FF672D8  hdmi_colorbar_vtc_top_mode_tb.sv
55600930E8AFDC8D9747284F91B494E007EDC7D0C8CDFE896CEDCB5E11F1727A  modelsim_transcript.txt
```
