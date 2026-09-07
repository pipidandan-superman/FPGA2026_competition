# ADV7511 configuration rewrite simulation report

Date: 2026-09-06  
Run: `2026-09-06_adv7511_config_rewrite_run01`  
Result: PASS (positive and negative self-checks)

## Configuration decision

The FPGA intentionally emits logical Style 3 `{Y, Cb/Cr}` and then swaps the
16-bit bus bytes. Therefore the physical ADV7511 input is `{Cb/Cr, Y}`. That is
exactly Hardware User's Guide Rev. D, Table 7, Style 1, right-justified mapping.

The ADI API maps datasheet Style 1 to register style field `0`. The rewritten
format byte is therefore:

- `R0x15 = 0x01`: YCbCr 4:2:2, 1x pixel clock, separate syncs.
- `R0x16 = 0x30`: RGB444 output (`bit7=0`, `bit0=0`), 8-bit 4:2:2 depth, register style 0.
- `R0x48 = 0x08`: right-justified input.
- `R0x18 = 0xC7`: CSC enabled, scaling factor 4, A1 high bits.
- `R0x18..R0x2F`: full limited-range BT.709 YCbCr-to-RGB matrix from the Linux
  ADV7511 driver.
- `R0xAF = 0x04`: ADI API recommended DVI-compatible mode for the first board test.

This configuration lets ADV7511 convert the incoming YCbCr422 bus to RGB444 and
avoids declaring HDMI YCbCr metadata while sending RGB to the monitor.

## Simulation evidence

Command-line ModelSim 10.1c compilation completed, but `vsim -c` failed at
design load with the host-specific Tcl error:

```text
Error: can't read "FileWatch(fileName)": no such element in array
```

A minimal Hello testbench reproduced the same failure, so the fallback path used
the installed ModelSim GUI. The final transcripts are retained.

Positive case:

```text
CFG_READBACK_SUCCESS_PASS: transactions=61 starts=67 stops=61 bitmap=111111 raw=04c708300110
```

Negative case, corrupting `R0x16[4]` from `30h` to `20h`:

```text
CFG_READBACK_MISMATCH_PASS: transactions=61 bitmap=111011 raw=04c708200110
```

`61` transactions are the 55 writes plus 6 readback checks. The negative case
proves that the masked checker detects a functional bit error and reports
`cfg_error`.

## Artifacts

- `modelsim_transcript_success.txt`
- `modelsim_transcript_mismatch.txt`
- `cfg_success_result.txt`
- `cfg_mismatch_result.txt`
- `success_lib02.wlf`
- `mismatch_corrected.wlf`
- `run_success_lib02.do`
- `run_mismatch.do`
- `ila_0_stub.sv`

## Frozen-source SHA-256

```text
FC8EF5F14DBC4F87CA09848476E5257A839770094EF1DC1460473C3F5361D7AD  adv7511_init_table_pkg.sv
15F8CB68C98868E0BEDA388D43BA18389DDFC9FC7674491A81FEF405A12D5DCA  hdmi_colorbar_vtc_top.v
8FA882D9C3F82400374D2F894EEBC5458205C62E90546C939B221FE4855D6AEE  adv7511_cfg_top_tb.sv
7CF2FA862A6FFCA7AEFD639058B5CA3345A063D87965F2B7AB18909295F83E95  modelsim_transcript_success.txt
472B9B3D9F8C89B2B25EE6FE337A87771FD56CED3BD4F6C0DA0CB8C1D61F28C3  modelsim_transcript_mismatch.txt
```

## Board result against V2.0 and V2.1 pivot

The V2.0 RGB/CSC build removed the old vertical chroma stripes, so the physical
Style 1 / right-justified mapping was correct. Archived photo:
`board_after_rgb_csw_style1.jpg`.

The display showed the first three expected source bars collapsed into one
large magenta region, followed by a pale bar and a saturated blue bar. This
means the byte-position issue is fixed, but the additional ADV7511 CSC path is
not the best architecture for this board/pattern. V2.1 therefore removes the
uncertain CSC stage:

```text
physical {Cb/Cr, Y} -> ADV7511 422-to-444 -> HDMI YCbCr422 -> monitor CSC
```

V2.1 key writes are `R0x16=0xB1`, `R0x44=0x10`, complete AVI YCbCr422
metadata, and `R0xAF=0x12`. The AVI declares VIC 1 (640x480p60).

## V2.1 simulation

Positive case:

```text
CFG_READBACK_SUCCESS_PASS: transactions=50 starts=56 stops=50 bitmap=111111
READBACK: 41=10 15=01 16=B1 48=08 AF=12 DE=10
```

Negative case, corrupting `R0x16[5]` inside the `0x30` depth/style mask:

```text
CFG_READBACK_MISMATCH_PASS: transactions=50 bitmap=111011
READBACK: 41=10 15=01 16=91 48=08 AF=12 DE=10
```

V2.1 frozen-source SHA-256:

```text
02C6DC9620215C2914251DDD6C3D2B8E7C1C79F7EC850A77E32B36E77538D48A  adv7511_init_table_pkg.sv
DB1C6664B01C8C928EBB9B90864CD78688AE1A46D7CB01BC80337BD5F45DBFFD  hdmi_colorbar_vtc_top.v
8887B57DCDDDB5630B81A2C84E5E0C48C3E28AD51BCF4804073C237D302584BE  adv7511_cfg_top_tb.sv
AFA81E5B29886048EF90E062543F30D1498FE2B27F5D2E250F21FACBF13E18F6  modelsim_transcript_success_yuv422.txt
5BA28EBC15B3A11ACE9B9155C3E64B0DE923F085042311E5098AFC2FE97A4F80  modelsim_transcript_mismatch_yuv422.txt
```
