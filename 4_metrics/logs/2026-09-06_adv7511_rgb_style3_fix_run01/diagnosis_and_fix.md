# RGB/Style-3 HDMI diagnosis and source fix

Date: 2026-09-06 13:55  
Status: source corrected; corrected simulation and board test pending

## Observed evidence

- Board image before the fix: large blue field with magenta side bars. Archived
  as `board_before_rgb_style3_fix.jpg`.
- ILA waveform before the fix is archived as
  `ila_before_rgb_style3_fix.png`.
- The failing bitstream was built at 13:46:49.
- The synthesis log used the 68-entry table but reported:

```text
WARNING: case item ...64 is unreachable
WARNING: case item ...67 is unreachable
WARNING: width (7) of port connection 'init_index_i'
         does not match port width (6)
```

## Root causes

1. The user's RGB/CSC table grew to 68 entries, but `init_index_i` remained
   six bits wide. Therefore indices 64 through 67 were unreachable; the last
   four CSC coefficient registers (`0x2C..0x2F`) could not be selected.
2. The video bus was changed to the unswapped Style 3 order:

```text
HDMI_DATA = {Y, Cb/Cr}
```

   But `R0x16=0x30` selected Style 0, which matches the swapped bus:

```text
HDMI_DATA = {Cb/Cr, Y}
```

   The ADV7511 therefore interpreted luma and chroma bytes in the wrong
   positions. This explains the absurd two-color result.
3. `R0x55=0x09` correctly changes AVI metadata from YCbCr422 to RGB, but the
   AVI checksum at `R0x54` remained `0xAB`. For this byte change from `0x29` to
   `0x09`, the checksum must increase by `0x20`, to `0xCB`.

## Source corrections

- `adv7511_init_table.sv`
  - `init_index_i` widened from six bits to seven bits.
  - `R0x16` changed from `0x30` to `0x38`.
  - `R0x54` checksum changed from `0xAB` to `0xCB`.
  - Header revision updated to V1.1.
- `adv7511_iic_data_xfer.sv`
  - Reset/init `write_index` assignments updated to seven-bit width.
- `hdmi_colorbar_vtc_top.v`
  - The no-byte-swap assignment is retained.
  - Comments now document the coherent Style 3 RGB/CSC mode.

## Current key register intent

```text
R0x15 = 01  YCbCr422 input, separate syncs, 1x clock
R0x16 = 38  RGB444 output, 8-bit 422 input, unswapped Style 3
R0x48 = 08  right-justified bus
R0x54 = CB  AVI checksum updated for RGB metadata
R0x55 = 09  RGB metadata, preserving other AVI control bits
R0x18..R0x2F = full YCbCr-to-RGB CSC coefficients
```

## Verification status

The corrected sources compile in ModelSim compilation, but simulation did not
run because the host `vsim -c` loader again stopped at the known
`FileWatch(fileName)` error. GUI launch approval was not available, so this run
does not claim simulation PASS.

Run the following existing scripts in the ModelSim GUI after this fix:

```tcl
do E:/competition/4_metrics/logs/2026-09-06_adv7511_rgb_style3_fix_run01/run_config.do
do E:/competition/4_metrics/logs/2026-09-06_adv7511_rgb_style3_fix_run01/run_config_mismatch.do
do E:/competition/4_metrics/logs/2026-09-06_adv7511_rgb_style3_fix_run01/run_mode.do
```

Then rebuild and board-test. Required PASS:

```text
White / Black / Red / Blue / Green solid bars
no stripes, stable 640x480@60, both SW0 modes
```

## Source SHA-256 after correction

```text
1174F3162755C591AA4951135CF34319D2620883EC27AC41A6A1EA63F731B0F9  adv7511_init_table.sv
73475AED2DD36EA32B3A25AC6EE93B2AFB09E89D8C2BF843D4F5AB22C93647CC  adv7511_iic_data_xfer.sv
D07E4A14220BD0EBE8A505A70A2C501F5FDD638D4AF106CB16A47E874997E28E  hdmi_colorbar_vtc_top.v
BBA46541A34D5854BCDCBC9038C5C77EB29DF9372C6B35ADAB30641D43EAF9B8  hdmi_colorbar_vtc_top_mode_tb.sv
```
