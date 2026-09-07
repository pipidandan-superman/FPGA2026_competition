# 2026-09-05 Execution Plan

## Resumed evidence-led correction

1. Active XPR references shared RTL under 0_diaplay_test; keep the user's original runs intact.
2. EES-331 manual printed p31 connects board D0..15 to ADV7511 D8..23 in order.
3. ADV7511 Hardware User's Guide Rev D p24 Table 7 specifies Style 3 / 16-bit / right-justified as D23:16=Y, D15:8=C.
4. Remove the unjustified output byte swap; check physical output pins in both SW0 modes.
5. Build an isolated ILA image to inspect all six actual readback bytes, match flags, done/error.
6. Do not declare the LED report to be a full-byte FF read without capturing the missing MSB.

1. Inventory `project_1` and resolve the active top/source/constraint set from Vivado metadata.
2. Inspect active HDMI RTL and trace its signal encoding and timing.
3. Extract and visually inspect the relevant ADV7511 manual pages.
4. Compare the implemented register table with the required mode, including input ID/style, DDR/SDR, synchronization, color-space conversion, output format, and AVI InfoFrame.
5. Inspect synthesis/implementation logs, generated-file timestamps, and prior board-test records for stale-artifact or run-validity problems.
6. Rank causes as confirmed, highly likely, plausible, or excluded.
7. Define measurements that distinguish the remaining hypotheses.

## Authorized implementation extension

1. Verify LED active polarity and ensure the requested FPGA pins are not already assigned.
2. Refactor the ADV7511 transfer sequencer into a write phase followed by masked readback of
   critical registers, with explicit pass/fail and failing-register index outputs.
3. Correct `R0xDE` to the ADI recommended value while keeping already-verified Style 3 bus mapping.
4. Register video data/control on the edge opposite the ADV7511 sampling edge and constrain the
   source-synchronous interface relative to the forwarded clock.
5. Map eight debug meanings to LED0-LED7 and add their package/I/O-standard constraints.
6. Extend testbenches for write/readback success and deliberate mismatch/error cases.
7. Preserve complete ModelSim/Vivado output in a new `4_metrics/logs/2026-09-05_*` run directory.

## Key paths

- `E:/competition/2_fpga/1_zynqtest_2025/project_1`
- `E:/competition/2_fpga/0_diaplay_test/rtl/hdmi_new`
- `E:/competition/1_docs/ADV7511_Hardware_Users_Guide/ADV7511_Hardware_Users_Guide.pdf`
- `E:/competition/4_metrics/logs`

## Risks and fallback

- Vivado generated metadata may reference copied sources outside `project_1`; resolve absolute source paths before drawing conclusions.
- If the PDF text layer is incomplete, render the relevant pages and inspect tables visually.
- If board observations are ambiguous, give register readback/scope/ILA discriminators rather than guessing.

## Execution result

- The active pure-PL top was modified without touching the PS/DDR/VDMA/camera path.
- The original package-scoped struct-array lookup was replaced in active logic by case-based
  accessors after XSim demonstrated dynamic member aliasing.
- ModelSim was searched first but no installed `vsim.exe` was available; the complete regression
  was therefore executed with Vivado XSim 2025.2.
- Final RTL simulation, synthesis, implementation, routed timing, DRC, and bitstream generation
  all passed. Exact evidence is recorded in `03_validation_summary.md`.

## Board-feedback correction pass

1. The photograph showed uniform regions when Cb and Cr were equal or close, but one-pixel
   vertical stripes where Cb and Cr differed strongly. This is the expected visual signature when
   the alternating chroma byte is interpreted as luma.
2. The interface was changed from Style 3 `{Y,C}` to the internally consistent Style 1 `{C,Y}`
   pair by setting `R0x16=0xB1` and updating both the direct color-bar path and RGB conversion path.
3. Raw readback storage was added for all six critical registers. A mismatch no longer terminates
   the sequence before later registers can be observed.
4. LED7..LED0 now show raw `R0x16`; expected hardware result is `8'b1011_0001`.
5. The reset synchronizer now has immediate external-reset assertion and synchronous release.
6. ModelSim regressions were run; Vivado implementation was intentionally not run at the user's
   request.

## RGB source correction

- The ADV7511 cannot use ordinary 24-bit RGB SDR on this PCB because only `D8..D23` are wired.
- The ADV7511 Input ID 5 narrow-bus RGB DDR mappings use the upper `D24..D35` or lower `D0..D11`
  pin regions, neither of which matches the board's middle 16-bit connection.
- The isolation top therefore now generates native RGB888 bars and uses the existing FPGA
  `rgb2ycbcr422` block only as the physical 16-bit transmitter-interface conversion.
- RGB bar order is white, black, red, blue, green; each region is 128 pixels wide.

## Style 3 correction from RGB board image

- The second board image is numerically consistent with Style 3 decoding of a Style 1 bus:
  white becomes green, black becomes dark red, red/blue show one-pixel luma stripes, and green
  remains relatively uniform because its two chroma values are close.
- Keep the RGB888 source unchanged.
- Restore only the transmitter-interface interpretation to the matched Style 3 pair:
  `R0x16=0xBD` and `HDMI_DATA={Y,Cb/Cr}`.
- Preserve the falling-edge FPGA launch and rising-edge ADV7511 sample relationship.

## Bitstream provenance discriminator

1. Stop changing RGB-to-YCbCr equations or ADV7511 input-style fields until the loaded image is
   proven current.
2. Drive `LED[7:0]` with fixed signature `8'hA5`, independent of reset, pixel clock, and I2C.
3. Rebuild and program only
   `project_1.runs/impl_1/hdmi_colorbar_vtc_top.bit`.
4. Treat LED7/LED5/LED2/LED0 on and the other LEDs off as proof that the new top-level netlist is
   active. Any other pattern proves a build/programming provenance problem before HDMI analysis.

## Paused-state boundary after A5 board result (historical)

- The programmed bitstream timestamp is `2026-09-05 13:11:49.160`.
- The current `hdmi_colorbar_vtc_top.v` and rewritten `iic_protocal.v` timestamps are
  `2026-09-05 13:41:22.578` and `2026-09-05 13:41:20.608`, respectively.
- Therefore the reported A5 result validates the earlier build-signature image only; it does not
  test the rewritten I2C engine currently present in the workspace.
- This was the prior paused-state instruction. It is superseded by the protocol-inclusive
  revalidation recorded below; the current source set is now intended for the next rebuild.

## SW0 mode-switch implementation

- Use EES-331 SW0 at `AB6`; S2 remains the PS reset key and is not connected to PL logic.
- Synchronize SW0 to `pix_clk`, then latch the mode at `(pixel_x,pixel_y)=(0,0)`.
- Keep RGB888 conversion and direct YCbCr422 paths aligned to the same three-cycle latency.
- Use Style 3 packing `{Y,Cb/Cr}` with BT.709 limited-range constants for white, black, red, blue,
  and green.
- Report the latched direct-mode state on LED7 while preserving LED6:LED0 readback visibility.
- Validate with the dedicated mode-switch testbench and retain complete ModelSim artifacts.

## Protocol resumed with SW0 implementation (historical; superseded by restoration below)

- Keep the ADV7511 register table unchanged; both SW0 video modes use the same final
  Style-3 `{Y,Cb/Cr}` transport, so no mode-dependent I2C programming is required.
- Use the rewritten `iic_protocal.v` as the single-register open-drain master. It supports
  write, random read with repeated START, ACK/NACK handling, one-byte master NACK,
  legal STOP/error STOP, and SCL clock stretching.
- Verify the protocol in isolation, then verify the 34-write/6-read configuration flow,
  intentional readback mismatch detection, and immediate NACK error handling.
- Ensure `build_hdmi_colorbar_vtc.tcl` includes `../iic/iic_protocal.v` so a fresh standalone
  Vivado project does not omit the low-level protocol dependency.

## Current correction: restore original protocol

1. Replace the rewritten low-level I2C state machine with the repository's original
   `iic_protocal.v` behavior and interface (`iic_done`, FPGA-output `scl`, open-drain `sda`).
2. Remove `iic_error` wiring from `adv7511_iic_data_xfer.sv`; retain timeout-based failure
   handling and the six-register readback outputs.
3. Compile the configuration sequencer and top-level SW0 testbench against the restored
   protocol.
4. Preserve all raw ModelSim transcripts and WLF files under the dedicated original-protocol
   evidence directory.

## Current correction: physical byte-lane order

1. Keep the verified ADV7511 `R0x16=0xBD` Style-3 setting and logical converter output
   `{Y,Cb/Cr}`.
2. Swap the two bytes only at the physical FPGA output boundary, producing board data
   `{Cb/Cr,Y}` for the observed EES-331 lane order.
3. Apply the same boundary correction to `hdmi_colorbar_vtc_top.v` and `hdmi_out_adv7511.v`.
4. Run the existing output-pixel self-check with the swapped expected words, then rebuild the
   bitstream and compare the five hardware color regions.
