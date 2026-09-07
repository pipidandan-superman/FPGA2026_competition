# 2026-09-05 Daily Plan

## Latest disposition

- Mapping defect corrected and simulated; actual I2C errors captured through JTAG/ILA.
- Not complete: open-drain diagnostic reveals an address NACK and SDA/SCL coupling while released.
- Next input required: board photo and supply/pull-up electrical checks. Do not label the current diagnostic bitstream as a display fix validated on hardware.

## Resumed HDMI root-cause investigation

- User reports LED7 follows SW0; LED6:0 remain high, with incorrect colors and vertical stripes.
- Verify active project sources, schematic lane mapping, I2C transactions, and implemented logic.
- Correct demonstrated defects, run pin-level regression, and build an identifiable bitstream.
- Board display success requires a new observation; simulation alone is not board proof.

## Current judgment

- The ADV7511 path has produced an image in a prior pure-PL color-bar test, but color and/or stability remain abnormal.
- Existing notes point to possible mismatches among the actual 16-bit YCbCr 4:2:2 bus packing, ADV7511 input-style register fields, AVI InfoFrame metadata, and stale Vivado build artifacts.
- This session is diagnostic only unless the user later requests implementation.
- The user has now authorized implementation: correct the high-confidence ADV7511 defects,
  add register readback/status LEDs, and add the LED pin constraints shown in the EES-331 table.

## Main objective

Determine why the active `2_fpga/1_zynqtest_2025` project does not produce a consistently correct HDMI display, using project evidence and the ADV7511 Hardware User's Guide.

Implement the minimum evidence-backed corrections in the active pure-PL isolation path and make
configuration/readback status observable on LED0-LED7.

## Prioritized tasks

- [x] Identify the exact active top, source files, constraints, and generated bitstream provenance.
- [x] Trace pixel clock, HSYNC, VSYNC, DE, and 16-bit pixel-data semantics end to end.
- [x] Audit the active ADV7511 initialization table against the manual and bundled ADI/Linux sources.
- [x] Check reset, power-down, HPD/interrupt, I2C addressing, and clock validity.
- [x] Separate confirmed faults from unverified board-level risks.
- [x] Produce a ranked root-cause analysis and concrete verification sequence.
- [x] Confirm LED polarity and pins V4/U6/U5/V7/W7/W6/W5/U7 from the supplied board table.
- [x] Correct the unsafe ADV7511 register setting and add masked register readback.
- [x] Expose configuration/readback state on LED0-LED7.
- [x] Correct the ADV7511 data-versus-clock launch phase and add external timing constraints.
- [x] Update/add self-checking simulation and run an RTL regression.
- [x] Run Vivado 2025.2 synthesis, implementation, DRC, timing, and bitstream generation.

## Non-goals

- Do not alter the PS/DDR/VDMA/camera path in this implementation pass.
- Do not program hardware automatically; preserve the generated bitstream and board-test instructions.
- Do not claim board-level success without fresh board evidence.

## Expected deliverables

- Evidence-backed root-cause report.
- File- and register-level findings.
- Self-checking XSim evidence for readback success, mismatch detection, and video alignment.
- Routed timing/IO/DRC evidence and a current programmable bitstream.
- Minimal ordered board/debug checklist.

## Follow-up after first board image

- [x] Use the stripe visibility versus Cb/Cr difference to identify a byte-lane interpretation fault.
- [x] Change the active interface as one consistent pair: `R0x16=0xB1` (Style 1) and
  `HDMI_DATA={Cb/Cr,Y}`.
- [x] Make S1 assert the internal pixel reset immediately even when the clock wizard stops
  `pix_clk`.
- [x] Preserve all six raw register reads and complete the full readback sequence before reporting
  a mismatch.
- [x] Temporarily map LED7..LED0 to the raw `R0x16` value for direct board diagnosis.
- [x] Stop after RTL verification because the user will build the bitstream locally.
- [x] Replace the direct YCbCr test values with a native RGB888 five-color source after the user
  clarified that the original image format is RGB.
- [x] Use the second board photograph to identify the effective ADV7511 input interpretation as
  Style 3 and restore the matched `R0x16=0xBD` plus `{Y,Cb/Cr}` transport pair.
- [x] Replace the unreliable raw-I2C LED display with a fixed `8'hA5` build signature after the
  restored Style 3 bitstream produced no visible screen change.
- [ ] Confirm on the board that only LED7, LED5, LED2, and LED0 light after programming the exact
  newly generated pure-PL bitstream.
- [x] Board confirmed the fixed `8'hA5` signature after rebuilding and downloading.
- [x] Record that the programmed A5 bitstream predates the later I2C rewrite in the workspace.
- [x] Historical pause boundary was recorded; protocol work was subsequently resumed and revalidated.
- [x] Add SW0-controlled RGB888/direct YCbCr422 mode switching without changing I2C.
- [x] Verify frame-safe switching and direct YCbCr422 values in ModelSim.
- [x] Resume the I2C protocol work together with the SW0 source-mode implementation.
- [x] Re-run the rewritten open-drain protocol, configuration readback success/mismatch,
  and fast-NACK regressions from the current workspace sources.
- [x] Add the low-level protocol source to the standalone Vivado project-generation script.

## Protocol restoration correction

- [x] Restore `rtl/iic/iic_protocal.v` to the original four-bit-state-machine protocol behavior.
- [x] Remove the upper-layer dependency on the rewritten protocol's `iic_error` port; the
  configuration sequencer now uses its existing timeout path for failures.
- [x] Keep the FPGA-output SCL interface and current SW0/RGB/YCbCr video changes intact.
- [x] Re-run original-protocol configuration readback and SW0 mode-switch compilation/simulation.

## Board image byte-lane correction

- [x] Use the new board photograph to identify the signature of a `{Y,Cb/Cr}` versus
  `{Cb/Cr,Y}` interpretation mismatch: white/black color shifts and alternating red/blue
  vertical stripes.
- [x] Add a physical 8-bit byte swap at the FPGA-to-ADV7511 boundary in both HDMI output paths.
- [ ] Rebuild and confirm the five regions become white, black, red, blue, and green on hardware.
