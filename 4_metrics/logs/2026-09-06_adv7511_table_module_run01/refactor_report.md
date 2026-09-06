# ADV7511 init-table explicit-instantiation refactor

Date: 2026-09-06 13:22  
Result: PASS

## Structural change

The old package source
`adv7511_init_table_pkg.sv`
was removed. Its V2.1 values were moved unchanged into a real, synthesizable
module:

```text
E:\competition\2_fpga\0_diaplay_test\rtl\hdmi_new\adv7511_init_table.sv
```

`adv7511_iic_data_xfer` now explicitly instantiates:

```systemverilog
adv7511_init_table u_adv7511_init_table
```

Therefore Vivado's hierarchy can show the table under
`u_adv7511_iic_data_xfer`. This changes the coding format and hierarchy; it does
not change the V2.1 register values or I2C sequence.

The project reference was changed from the deleted package path to the new
module path. The entry resolves to the active source and is not AutoDisabled.

## Simulation evidence

Command-line ModelSim again reached design load and stopped with the known host
error:

```text
Error: can't read "FileWatch(fileName)": no such element in array
```

The approved ModelSim GUI fallback ran all three checks from this run folder.

Positive configuration check:

```text
CFG_READBACK_SUCCESS_PASS: transactions=50 starts=56 stops=50 bitmap=111111
```

Negative masked-readback check, with `R0x16[5]` corrupted:

```text
CFG_READBACK_MISMATCH_PASS: transactions=50 bitmap=111011
```

Top-level video/mode check:

```text
MODE_SWITCH_PASS: RGB888 and direct YCbCr422, frame-safe SW0 switch
```

## Source SHA-256

```text
0BF76164019161351E06A40A856FE7007C017270DB607233AD044C06DB299C26  adv7511_init_table.sv
03CD54F41ECD80C41681CB40E20A590C77B09CA5D599C8D39782851315F62762  adv7511_iic_data_xfer.sv
348C505EAC82F2F7F9B131A5B231C7EF02A601B8E8859235273EA30FB187702D  adv7511_i2c_init.sv
C432E578A5DC60AC3591B8748A44881CBDEA4782B0F85412919B90E99775F0EE  adv7511_cfg_top_tb.sv
1D2C3543B2AEA5A8656853F598D85D54B5AE2B56A95F61BABF984C226976CAD4  hdmi_out_adv7511_tb.sv
```

## Boundary

The simulations prove RTL equivalence of the write/readback flow and video mode
path. A fresh Vivado elaboration/synthesis is still needed to show the new
hierarchy in the GUI and produce a bitstream. Board display quality is not
claimed by this report.
