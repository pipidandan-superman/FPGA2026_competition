# ADV7511KSTZ register evidence and 480p60 configuration

## Part number

`ADV7511KSTZ` is the ADV7511 HDMI transmitter in the LQFP package and commercial temperature grade. It uses the same register map as the generic ADV7511 documentation. The suffix does not add a video test-pattern generator.

## Current board configuration

The FPGA accesses the ADV7511 main register map at 7-bit I2C address `0x39`; the conventional 8-bit write byte is `0x72`.

The active project uses a 34-entry initialization table at:

`E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_init_table_pkg.sv`

| Register | Value | Purpose |
|---:|---:|---|
| `0x98` | `0x03` | ADI fixed/recommended configuration |
| `0x9A` | `0xE0` | ADI fixed/recommended configuration |
| `0x9C` | `0x30` | ADI fixed/recommended configuration |
| `0x9D` | `0x61` | ADI fixed/recommended configuration |
| `0xA2` | `0xA4` | ADI fixed/recommended configuration |
| `0xA3` | `0xA4` | ADI fixed/recommended configuration |
| `0xD0` | `0x03` | Timing/sync configuration |
| `0xD1` | `0xFF` | Timing/sync configuration |
| `0xD2` | `0xFF` | Timing/sync configuration |
| `0xD6` | `0xC0` | HPD control |
| `0xDE` | `0x55` | TMDS clock inversion |
| `0x41` | `0x10` | Power up; interrupt polarity |
| `0x4A` | `0x40` | InfoFrame update control |
| `0x52` | `0x02` | AVI InfoFrame version |
| `0x53` | `0x0D` | AVI InfoFrame length: 13 bytes |
| `0x54` | `0xAB` | AVI InfoFrame checksum |
| `0x55` | `0x29` | AVI PB1: YCbCr 4:2:2 indication |
| `0x56` | `0x99` | AVI PB2 |
| `0x57` | `0x01` | AVI PB3/VIC: 640x480p60 |
| `0x58` | `0x01` | AVI PB4 |
| `0x59`..`0x5E` | `0x00` | Remaining AVI payload |
| `0x4A` | `0x00` | Finish InfoFrame update |
| `0x44` | `0x10` | HDMI packet control |
| `0x48` | `0x08` | 16-bit bus right justification: `R0x48[4:3]=01` |
| `0xE0` | `0xD0` | ADI fixed/recommended configuration |
| `0x15` | `0x01` | Input ID 1: YCbCr 4:2:2, 1x pixel clock, separate syncs |
| `0x16` | `0xBD` | 8-bit YCbCr 4:2:2, Style 3 |
| `0x18` | `0x46` | CSC/recommended configuration |
| `0xAF` | `0x12` | HDMI mode |

## Critical input-format fields

The Hardware User's Guide, Rev. D, pages 22-25, defines the exact mapping:

- `R0x15[3:0] = 0x1`: YCbCr 4:2:2, 1x pixel clock, separate HSYNC/VSYNC/DE.
- `R0x16[5:4] = 0b11`: 8 bits per color component.
- `R0x16[3:2] = 0b11`: Style 3.
- `R0x48[4:3] = 0b01`: right-justified input bus.

For Style 3, right-justified, 16-bit mode, each two-pixel bus sequence is:

1. First pixel: `D[15:8] = Y[7:0]`, `D[7:0] = Cb[7:0]`
2. Second pixel: `D[15:8] = Y[7:0]`, `D[7:0] = Cr[7:0]`

This exactly matches the FPGA packing assignment:

```systemverilog
data_o = {y_value_s3, chroma_is_cb_s3 ? cb_value_s3 : cr_value_s3};
```

`0xBD = 1011_1101` combines the YCbCr 4:2:2 output-selection bits (`bit7=1`, `bit0=1`) with 8-bit depth (`[5:4]=11`) and Style 3 (`[3:2]=11`). Linux driver lines 252-291 independently set `0x16` with mask `0x81` for 4:2:2/YCbCr and mask `0x7E` for depth/style; its Style mapping also maps user Style 3 to register value 3.

## No built-in video test pattern

The Rev. D Hardware User's Guide has no test-pattern-generator, test-pattern, or colorbar register. The official ADI API package and Linux driver also contain no video pattern generator for ADV7511.

The only “test” registers found in the ADI API are unrelated to video bars:

- Audio FIFO test: register `0x41`, field `AUDIOFIFO_TESTEN`
- HDCP/loopback test: registers `0xA5`-`0xA9`
- Packet RAM test: register `0xF9`

Register `0x55` in the Linux driver header is explicitly `ADV7511_REG_AVI_INFOFRAME(0)`, not a test-pattern control. Therefore, an HDMI colorbar must be supplied by the FPGA into the ADV7511 input bus.

## Direct FPGA isolation test

To bypass every image-generation and color-conversion module, the current top-level generates hard-coded YCbCr values directly and only instantiates VTC, ADV7511 I2C configuration, and HDMI clock ODDR:

`E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\hdmi_colorbar_vtc_top.v`

The direct bars use limited-range BT.709 values:

| Bar | Y | Cb/Cr pair | Expected screen color |
|---:|---:|---|---|
| 0 | `0xEB` | `0x80`, `0x80` | White |
| 1 | `0xDB` | `0x10`, `0x8A` | Yellow |
| 2 | `0xBC` | `0x9A`, `0x10` | Cyan |
| 3 | `0xAD` | `0x2A`, `0x1A` | Green |
| 4 | `0x4E` | `0xD6`, `0xE6` | Magenta |

If this direct bitstream still shows the unchanged image, the downloaded bit file is not the newly generated one, or the FPGA-to-ADV7511 timing/pin constraints are wrong. The ADV7511 does not have a chip-internal colorbar that can bypass the input bus.
