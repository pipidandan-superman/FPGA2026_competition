# HDMI no-display provenance check

## User evidence

- The user re-sent the yesterday display photo. It is byte-identical to the archived `2026-09-05_hdmi_board_result_run01/board_result_2026-09-05_run02.jpg`.
- SHA-256: `E3D91414AB79266C725F0A276155BC2F8B87EC19A3AD8058ABB52B36F7A3A75E`.
- Archived copy: `yesterday_display_reference.jpg`.
- Interpretation: HDMI timing/link was locked yesterday, but colors were wrong. It does not prove that the later open-drain diagnostic build displayed.

## Today's bitstream

- File: `E:/competition/2_fpga/1_zynqtest_2025/project_1/project_1.runs/impl_1/hdmi_colorbar_vtc_top.bit`
- Generated: 2026-09-06 09:52:01.
- SHA-256: `600463B72A6F264A2EDC5EB98F1128A99D6BD67B672162BA44F0741D22B67418`.
- Paired LTX: `debug_nets.ltx` / `hdmi_colorbar_vtc_top.ltx`.
- Routed timing: WNS +15.757 ns, WHS +0.081 ns, TNS/THS zero; all constraints met.
- DRC: zero errors.

## Source-state finding

- Current `rtl/iic/iic_protocal.v` contains the open-drain SDA diagnostic expression:

```verilog
assign sda = (sda_en && !sda_out) ? 1'b0 : 1'bz;
```

- It also contains the one-second ERROR retry and the new 11-probe ILA instance.
- The yesterday 16:43 display record predates the late 2026-09-05 open-drain I2C diagnostic runs. Therefore today's image is not established to differ from the known-display image by ILA insertion alone.

## Live ILA capture attempt

- Vivado 2020.1 detected target `1234-tulA` and device `xc7z020_1`.
- It could not recognize the Vivado 2025.2 debug core and reported: "The debug hub core was not detected."
- This is expected tool-version incompatibility for the capture attempt, not proof that the device is unconfigured.
- Matching 2025.2 batch capture is blocked by an empty/corrupt user Tcl Store initializer. Raw logs are retained in this folder.

## Next single-variable test

Program `E:/competition/4_metrics/logs/2026-09-05_hdmi_root_cause_run01/hdmi_diagnostic.bit` with `hdmi_diagnostic.ltx`. This retains an ILA but uses the earlier push-pull SDA behavior. Record whether the yesterday-style image returns.

## Board result (confirmed)

- The user confirmed that the 2026-09-05 17:08 `hdmi_diagnostic.bit` successfully displays.
- Paired probes file: `hdmi_diagnostic.ltx`.
- SHA-256: `21036F69A4B43D6618F43DD601B5C3826FBC2DF742C5C78B7A8CD358BAF0DEFC`.
- This is a decisive single-variable comparison: run01 = push-pull SDA + ILA + display; today's build = open-drain SDA + ILA + no display.
- Root cause of the observed regression is therefore not the ILA. It is the later open-drain SDA change causing ADV7511 initialization to fail on this board.
- Screenshot evidence: `run01_bit_display_confirmed.png`, SHA-256 `1BEE4E38DD8D1E7C98E3ECDB6530C4A51FEE91C747109CCD5B57AA60B9DFAED1`.

## Run01 readback clarification

- The user's second ILA screenshot shows readback bytes `1F 01 FF 0F 1F 1F` for read addresses `41 15 16 48 AF DE`.
- This matches archived `board_readback.csv` and `board_readback.summary.json` exactly: aggregate `1f1f0fff011f`, `match=1A`, `done=0`, `error=1`.
- The expected/masked sequence is `10 01 BD 08 12 10`; therefore readback is not correct even though the display works.
- `NO_ACK` is expected at the end of an I2C read because the master must NACK the final data byte before STOP/IDLE.
- Screenshot evidence: `run01_ila_readback_values.png`, SHA-256 `4735678F3FA8573FC2E6A2767C75EBC6AE6674674B5DE958BBA23C04FF0E03D2`.

## Read-timing interpretation

- The visual placement of SDA transitions near SCL edges is not sufficient to prove an I2C timing violation.
- The valid rule is: SDA may change while SCL is low, including immediately after the falling edge; SDA must remain stable while SCL is high, except for START/STOP.
- The RTL samples `sda_in` during `RD_DATA` at `cnt_scl == IIC_SPPED_DIV2-1`, which is inside the generated SCL-high interval.
- The ILA is clocked at the system clock, so a transition and edge can appear simultaneous unless the waveform is sufficiently zoomed or exported as CSV.
- Additional screenshots: `run01_ila_read_timing_zoom.png` and `run01_ila_read_data_states.png`.

## Address/data pairing conclusion

- The user's annotated ILA screenshot confirms protocol pairing:
  - `0x41 -> 0x1F`
  - `0x15 -> 0x01`
  - `0x16 -> 0xFF`
  - `0x48 -> 0x0F`
  - `0xAF -> 0x1F`
  - `0xDE -> 0x1F`
- This means each read-data byte is being associated with the preceding register-address transaction, so the read/capture flow works.
- Protocol pairing is not the same as register-value matching. Under the configured masks, `0x15`, `0x48`, and `0xAF` pass; `0x41`, `0x16`, and `0xDE` fail. The aggregate match remains `0x1A` and `cfg_error` remains 1.
- Screenshot evidence: `run01_ila_address_data_pairs.png`, SHA-256 `3627DBD5293ECFC749110A1E242D3C9D6476F466979534854743F8C93A85361A`.

## Readback mismatch interpretation

- Display success and coherent address/data pairing establish that the transaction-level read flow is functional. They do not imply every raw register byte must equal the initialization-table byte.
- The mismatch pattern is coherent, not random:
  - `0x41`: wrote `10`, read `1F` — intended bit4 survives; lower bits read high.
  - `0x16`: wrote `BD`, read `FF` — the expected-1 bits survive; bit6/bit1 read high and require field-level interpretation.
  - `0x48`: wrote `08`, read `0F` — the critical `[4:3]=01` field survives; lower bits read high.
  - `0xAF`: wrote `12`, read `1F` — the intended bits4/bit1 survive; other low bits read high.
  - `0xDE`: wrote `10`, read `1F` — intended bit4 survives; lower bits read high.
- Therefore the primary checker issue is overstrict full-byte/field masking, not a proven broad configuration-write failure. The current table masks for `0x41`, `0x16`, and `0xDE` are too strict for board readback.
- Suggested nonblocking field checks are: `41: (value & 0x70) == 0x10`; `15: (value & 0x0F) == 0x01`; `16: (value & 0x3C) == 0x3C`, with `[7:6]` and `[1]` tracked separately; `48: (value & 0x18) == 0x08`; `AF: (value & 0x12) == 0x12`; `DE: (value & 0x10) == 0x10` or treat `DE` as informational.

## Wrong-color diagnosis

- User board evidence: both SW0 paths display the same wrong image. This does not implicate the RGB-to-YCbCr converter alone; the direct path was deliberately assigned the same BT.709 limited-range samples as the converter, so both paths emit equivalent `{Y, Cb/Cr}` words.
- The observed image matches a reversed 16-bit byte interpretation:
  - White `{Y=EB,C=80}` interpreted as `{Y=80,C=EB}` becomes yellow/green.
  - Black `{Y=10,C=80}` interpreted as `{Y=80,C=10}` becomes red-dominant.
  - Red alternates `{Y=3E,Cb=66}` and `{Y=3E,Cr=EF}`. After byte swap, the C bytes become alternating luma (`66`/`EF`), explaining the orange vertical-stripe bar.
  - Blue becomes red-dominant.
  - Green remains green.
- Therefore the next isolated board experiment is to reverse only the 16-bit data word before the output pins: `physical_data = {selected_data[7:0], selected_data[15:8]};`. Keep Style 3 and all ADV7511 configuration unchanged for the first test.

## Byte-swap test result

- The user applied the proposed byte swap and obtained the 2026-09-05 archived image byte-for-byte (`E3D91414AB79266C725F0A276155BC2F8B87EC19A3AD8058ABB52B36F7A3A75E`). The corresponding current bitstream hash is `66B82B598DA5FBF4DA4FE094B93CF5C4D1C73ACC71F0EC5A7190D9242F016A69`.
- This is a useful diagnostic but not a display PASS.
- The user's observation is exact: White and Black have no vertical stripes because their Cb and Cr are both `0x80`; Red, Blue, and Green do have stripes because their Cb and Cr differ. With Style 3 plus the applied byte swap, those unequal chroma bytes become the alternating luma input.
- Next single-variable test: restore `physical_data = selected_data;`, keeping Style 3 (`0x16=0xBD` intent), right-justification (`0x48=0x08`), push-pull SDA, and the current ILA unchanged. Rebuild and compare this against the swapped build under the same monitor/power state.
