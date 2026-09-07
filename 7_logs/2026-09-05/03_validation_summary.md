# 2026-09-05 Validation Summary

## Latest result: run02 is diagnostic, not a board PASS

- Open-drain SDA RTL regression passes, but the actual board NACKs address72; no readback completes.
- Live trace at17:42: SDA follows SCL during released/high data bits instead of remaining independently high.
- Routed IOBUF input path, AB9/AB10 mapping and PULLUP have been verified; external SCL voltage itself was not sampled by the FPGA's output-side probe.
- Final run02 timing WNS/WHS=15.830/0.062 ns; TNS/THS=0; DRC has no errors but has warnings.
- Further progress requires a board photo and electrical verification of R110/R140 pull-up supply VADJ and SDA/SCL. No specific physical short or missing supply has yet been measured.
- Full analysis and raw evidence index: `4_metrics/logs/2026-09-05_hdmi_root_cause_run02/DIAGNOSIS.md`.

## Resumed investigation: first live ILA evidence

- Active project: `2_fpga/1_zynqtest_2025/project_1/project_1.xpr`, top `hdmi_colorbar_vtc_top`.
- The output-byte swap contradicts EES-331 printed p31 and ADV7511 Rev D Table 7 p24; removed in both HDMI output modules.
- Pin-level output assertion added to the SW0 test; both RGB-converted and direct YCbCr paths pass.
- Full-rate divider=252 configuration regression: 34 writes + 6 reads pass; deliberate readback mismatch is detected.
- Diagnostic run01 implemented with WNS=15.445 ns, WHS=0.057 ns, TNS/THS=0; DRC has no errors, but warnings remain.
- JTAG device `xc7z020_1` on target `1234-tulA` was programmed in volatile PL only; no flash writes.
- Live ILA run01: R41=1F, R15=01, R16=FF, R48=0F, RAF=1F, RDE=1F; match=1A, done=0, error=1 across 1024 samples.
- This disproves the earlier claim that the running board had verified R16=BD. LED6:0=7F is a failed readback, not a success bitmap.
- Run02 changes SDA from push-pull high to open-drain release and retries configuration after an error. Board validation is pending; do not call these changes a proven cure yet.
- Raw transcripts, failed diagnostic-build attempts, timing/DRC, bitstream and ILA CSV are retained under `4_metrics/logs/2026-09-05_hdmi_root_cause_run01` and `run02`.

## Previously reported evidence

- Pure-PL 480p color-bar design reportedly caused the monitor to lock and display an image.
- Earlier color was incorrect.
- Existing handoff reports a correction from an RGB/YCbCr444 declaration to YCbCr422 Style 1, but a clean rebuild and definitive board retest were not yet established.
- ModelSim checks passed for the local video conversion and I2C write sequence; these do not prove the physical ADV7511 accepted the writes or interpreted the bus identically.

## Verified configuration and build provenance

- `project_1.xpr` currently selects `hdmi_colorbar_vtc_top` as the synthesis top. The block design, `design_1_wrapper`, `hdmi_out_adv7511.v`, and the full RGB/VDMA path are auto-disabled for this run.
- The active isolation path is `100 MHz -> clk_wiz_0 25.000 MHz -> vtc_480p_1ppc -> direct YCbCr422 bars -> ADV7511`.
- The current Vivado bitstream is `project_1.runs/impl_1/hdmi_colorbar_vtc_top.bit`, timestamp `2026-09-05 11:06:06`; it is newer than the active initialization table/top source.
- Vitis still contains `design_1_wrapper.bit` files dated `2026-09-04`. A Vitis Run and a Vivado Program Device action therefore do not test the same hardware architecture.
- EES-331 connects FPGA `HDMI_D0..D15` to ADV7511 `D8..D23`. With right justification, Input ID 1, 8-bit components, and Style 3, `{Y[7:0], Cb/Cr[7:0]}` is the correct logical packing.
- Active format fields are consistent: `R0x15=0x01`, `R0x48=0x08`, and `R0x16=0xBD`. The earlier `R0x16=0xB9` selected Style 1 and did not match this PCB wiring.
- `R0xAF=0x12` is not evidence of DVI mode. ADI's API and bundled Linux driver use `R0xAF[1]` (`EXT_HDMI_MODE`) as the HDMI/DVI selection; bit 1 is set in `0x12`.
- AVI checksum `0xAB` is arithmetically valid. `R0x55=0x29` declares YCbCr422 and `R0x58=0x01` carries VIC 1. `R0x57=0x01` is PB3 scaling metadata, not the VIC field, and should be reviewed later but is not a primary black-screen cause.

## Ranked root-cause findings

### P0/P1: unsafe `R0xDE=0x55`

- The active table writes `0xDE=0x55` and earlier notes incorrectly call it TMDS clock inversion.
- ADI field definitions show `R0xDE[3]` is `TMDS_CLOCK_INVERSION`, but bit 3 of `0x55` is zero.
- `R0xDE[0]` is `VCTRL_PWRDWN`; `0x55` sets this power-down bit.
- `0x55` also writes serializer/TMDS-driver test fields. The bundled ADI cold-start table and register defaults both use `R0xDE=0x10`.
- This is the strongest register-level defect and can directly leave the video-control/TMDS path in an unintended state.

### P1: ADV7511 input setup/hold is neither designed nor constrained

- The manual requires at least 1.0 ns input setup and 0.7 ns input hold around the rising sampling edge.
- RTL updates `HDMI_DATA`, `DE`, `HSYNC`, and `VSYNC` on the same `pix_clk` rising edge used by the ODDR forwarded `HDMI_CLK`.
- The XDC contains pin and `LVCMOS33` assignments only; it has no generated/forwarded-clock model and no `set_output_delay` constraints.
- Vivado reports all 21 HDMI outputs with no output delay (`HIGH`). The reported WNS therefore proves only internal FPGA timing, not timing at the ADV7511 pins.
- Routed output registers are ordinary SLICE FFs rather than IOB FFs. Unconstrained routing creates data/clock skew and bit-to-bit skew. The separate unconstrained min/max paths already show clock and data pin delays close enough that the required 0.7 ns hold margin is not guaranteed.
- A robust interface should change data on the opposite edge from the ADV7511 sampling edge (or forward a phase-shifted/180-degree clock), place output registers in IOBs, and constrain setup/hold relative to the forwarded clock.

### P1: physical I2C success is unobservable

- `cfg_done_o` and `cfg_error_o` are left unconnected in the active top, and `HDMI_INT` is unused.
- The table is write-only; no register readback confirms that the ADV7511 accepted or retained `0x41`, `0x15`, `0x16`, `0x48`, `0xAF`, or `0xDE`.
- The reused low-level engine does detect ACK failure internally, but it remains in its own error delay and does not expose an immediate error to the table sequencer; the outer sequencer only reports a later timeout.
- SDA and SCL are actively driven high instead of being strictly open-drain. This often works with a single non-stretching slave but is electrically/protocol-wise fragile.
- ModelSim ACKs are supplied by the testbench and cannot prove the board device ACKed.

### P1/P2: unsupported analog/test/HPD register overrides

- `R0xD0=0x03` replaces the default `0x30`, clearing the default DDR-delay field and changing timing/Rx-sense controls.
- `R0xD2=0xFF` replaces the default `0x80` and forces Channel 2 output-level/test/partial-serializer fields high.
- `R0xD6=0xC0` overrides HPD behavior. It may be intentional for isolation, but it bypasses normal HPD-controlled operation and must be treated as a test override.
- The table omits several values present in ADI's initialization sequence, notably `0xBA` clock delay, `0xBB`, `0xE4`, and `0xF9`. They should be introduced selectively, not copied blindly; `0xBA` is especially relevant to the current sampling-margin problem.

### P2: run-entry ambiguity

- Programming `hdmi_colorbar_vtc_top.bit` tests only the PL color-bar/ADV7511 boundary.
- Running the Vitis application downloads an older `design_1_wrapper.bit`, reintroducing PS, DDR, VDMA, camera, and software dependencies.
- Board observations are invalid unless the exact absolute bitstream path and timestamp are recorded.

### P2/P3: compatibility issues

- The generated pixel clock is exactly 25.000 MHz, so 800x525 timing produces about 59.52 Hz rather than the nominal 25.175 MHz/59.94 Hz. Most sinks accept this, but it reduces compatibility margin.
- The transmitter is forced to YCbCr422 without reading EDID. HDMI televisions are usually tolerant; DVI-oriented monitors/adapters may only be reliable with RGB.
- The direct bars use BT.709 metadata/values for a 480p VIC. BT.601/SMPTE-170M is conventional for 480p; this can shift colors but does not explain loss of sync.

## Excluded as primary causes for the current isolation top

- FPGA-to-ADV7511 byte order is correct for EES-331 Style 3/right-justified wiring.
- `R0x16=0xBD` correctly combines YCbCr422, 8-bit depth, Style 3, and YCbCr input; Linux sets the same relevant bit fields using masks `0x81` and `0x7E`.
- `R0xAF=0x12` has the external HDMI-mode bit set.
- The 640x480 totals and negative sync polarity are structurally correct.
- VDMA, DDR, camera input, and RGB-to-YCbCr conversion are bypassed by the active pure-PL top and cannot explain a failure observed with the current isolation bitstream.

## Pass/fail criteria

- PASS only if each implemented register value is traceable to the intended interface mode and the generated bitstream demonstrably contains the current sources.
- Board PASS requires stable lock, correct geometry, correct color ordering/levels, and repeatability after cold power-up.
- Every future build, UART, ILA, scope, or board run must preserve the complete raw console/log output in its run record folder.

## Results

- Implementation completed in the active pure-PL isolation path.
- `R0xDE` is now `0x10`; the verified Style 3/right-justified settings remain unchanged.
- Six critical registers are read back with masks after all 34 writes: `0x41`, `0x15`, `0x16`,
  `0x48`, `0xAF`, and `0xDE`.
- LED mapping is implemented and constrained as follows:
  - LED0..LED5: readback matches for `41/15/16/48/AF/DE`.
  - LED6: latched configuration/readback error.
  - LED7: final configuration success.
  - Pins: `V4/U6/U5/V7/W7/W6/W5/U7`, all `LVCMOS33`.
- ADV7511 video data/control now launch on the falling pixel-clock edge. The forwarded
  `HDMI_CLK` is modeled as a 25.000 MHz generated clock and uses 1.0 ns setup / 0.7 ns hold
  output-delay requirements from the hardware guide.

### Final simulation evidence

- Register readback success:
  `E:/competition/4_metrics/logs/2026-09-05_adv7511_readback_run04/xsim_success.txt`
  contains `CFG_READBACK_SUCCESS_PASS`, 40 completed transactions, and bitmap `111111`.
- Deliberate `R0x16` mismatch:
  `E:/competition/4_metrics/logs/2026-09-05_adv7511_readback_run04/xsim_mismatch.txt`
  contains `CFG_READBACK_MISMATCH_PASS`, 37 completed transactions, and bitmap `000011`.
- Video/I2C regression:
  `E:/competition/4_metrics/logs/2026-09-05_hdmi_video_run03/xsim.txt`
  contains `TEST_PASS`, 16/16 pixels matched, zero YCbCr mismatches, and 34 writes.
- ModelSim executable discovery found no installed `vsim.exe`; these regressions use Vivado
  XSim 2025.2. Full compile/elaboration logs and non-empty WDB files are retained with each run.

### Final Vivado evidence

- Evidence directory:
  `E:/competition/4_metrics/logs/2026-09-05_adv7511_vivado_build_run03`
- `build_result.txt`: synthesis complete, implementation/bitstream complete.
- Routed design: fully routed, DRC related violations `<none>`.
- Generated `adv7511_pixel_clk`: 40.000 ns period, divide-by-1 from the ODDR clock input.
- HDMI external path group: setup slack `18.401 ns`, hold slack `18.914 ns`, zero failing
  endpoints across 18 dynamic data/control outputs.
- All 18 dynamic HDMI data/control registers are packed into OLOGIC/IOB. `HDMI_DATA[0]` is
  constant zero in the current fixed color-bar values and is optimized without a register.
- Timing reports still classify one constant output as lacking an output delay; the other nine
  non-clock outputs in that check are intentionally false-pathed LEDs/I2C SCL, while HDMI_CLK
  carries the generated clock. This is not a failing dynamic HDMI path.
- Final bitstream:
  `E:/competition/2_fpga/1_zynqtest_2025/project_1/project_1.runs/impl_1/hdmi_colorbar_vtc_top.bit`
  - Timestamp: `2026-09-05 12:07:43`
  - Size: `4,045,697` bytes
  - SHA-256: `0CFEED8D490986896AA1A5A12B310C19B06D0AA1B48D3672D68D49B479E3511D`

### Remaining validation boundary

- No FPGA board was programmed in this session. Stable monitor lock, color correctness, and
  cold-power-up repeatability remain board-level acceptance tests.

### Board observation reported on 2026-09-05

- The programmed board shows only LED6 on: `LED[7:0] = 8'b0100_0000`.
- This proves the controller reached and latched `cfg_error_o`; configuration success was not
  reached and none of the six ordered readback checks was marked as passed.
- Because readback stops on the first mismatch, the current bitmap cannot by itself distinguish
  a write/read I2C timeout from a mismatch of the first checked register (`R0x41`).
- Diagnostic discriminator for the current RTL:
  - LED6 at roughly 3.1 seconds after reset release indicates an I2C transaction did not complete,
    most commonly an ADV7511 NACK or an SCL/SDA/power/reset/address problem.
  - LED6 at roughly 0.13 seconds after reset release indicates all writes likely completed and the
    first `R0x41` read returned a value that failed the current masked comparison.

## Follow-up board evidence and RTL correction

### New observations

- HDMI geometry and monitor lock are stable, but the displayed bars contain dense one-pixel
  vertical stripes.
- Bars using equal or nearby Cb/Cr values are nearly uniform; bars using widely separated Cb/Cr
  values have the strongest stripes. This strongly identifies the alternating chroma byte as the
  byte currently being interpreted as Y.
- While S1 is held, the old LED6 error indication remains on; after release it briefly clears and
  returns. The old reset shift register could not assert because S1 simultaneously stopped its
  `pix_clk` source.

### Implemented changes

- Changed the ADV7511 input style from Style 3 to Style 1: `R0x16 0xBD -> 0xB1`.
- Changed both video generators to Style 1 packing:
  `HDMI_DATA[15:8]=Cb/Cr`, `HDMI_DATA[7:0]=Y`.
- Changed blanking data from `{Y=0x10,C=0x80}` to the matching bus order `{C=0x80,Y=0x10}`.
- Changed pixel reset to assert immediately from external `reset_n`, even if `pix_clk` has stopped,
  while retaining synchronous delayed release.
- Added a 48-bit raw readback vector for `0x41/0x15/0x16/0x48/0xAF/0xDE`.
- Changed readback behavior to finish all six reads before reporting any comparison error.
- Temporarily mapped LED7..LED0 directly to raw `R0x16`; expected value is `0xB1`.

### ModelSim evidence

- Normal register readback:
  `4_metrics/logs/2026-09-05_adv7511_style1_readback_run01/modelsim_success.txt`
  reports `CFG_READBACK_SUCCESS_PASS`, 40 transactions, bitmap `111111`, and raw `R0x16=B1`.
- Deliberate `R0x16=B0` mismatch:
  `4_metrics/logs/2026-09-05_adv7511_style1_readback_run01/modelsim_mismatch.txt`
  reports `CFG_READBACK_MISMATCH_PASS`, still completes 40 transactions, and bitmap `111011`.
- Style 1 video packing:
  `4_metrics/logs/2026-09-05_adv7511_style1_video_run01/modelsim_transcript.txt`
  reports `TEST_PASS`, 16 checked pixels, zero mismatches, and all 34 writes.
- S1 reset behavior:
  `4_metrics/logs/2026-09-05_adv7511_reset_run01/modelsim_transcript.txt`
  reports `TOP_RESET_PASS` for immediate assertion and delayed synchronous release.
- Every run retained a non-empty WLF waveform.

### Current validation boundary

- No new Vivado synthesis, implementation, or bitstream was generated in this correction pass,
  because the user requested source completion only and will compile locally.
- The stripe correction remains a board-level hypothesis until the new Style 1 image is compiled,
  programmed, and observed.

## RGB-source clarification and second board observation

- The user rebuilt the prior Style 1 image. The bitstream timestamp is later than the modified
  sources, and synthesis logs confirm that Vivado read the external top source at
  `2_fpga/0_diaplay_test/rtl/hdmi_new/hdmi_colorbar_vtc_top.v`.
- LED0..LED7 all on means the raw LED debug bus displayed `R0x16=0xFF`. This is not the expected
  `0xB1` and indicates that the physical register-read data is not trustworthy yet.
- The display did not visibly change because that revision changed the FPGA byte order and the
  ADV7511 input Style together; those two semantic changes compensate when both take effect.
- The user clarified that the original image is RGB. The top now generates RGB888 directly:
  white `0xFFFFFF`, black `0x000000`, red `0xFF0000`, blue `0x0000FF`, and green `0x00FF00`.
- Hardware constraints prevent direct 24-bit RGB SDR input to the ADV7511 on this PCB. The RGB
  source is therefore converted inside the FPGA to the 16-bit YCbCr422 transport used by the
  wired `D8..D23` interface.
- Updated ModelSim top-level test reports `TOP_COLORBAR_RESET_PASS`; it checks all five RGB source
  values and immediate S1 reset assertion.
- No bitstream was generated for the RGB-source update.

## RGB board photograph: effective Style 3 proven

- Expected bars were white, black, red, blue, and green.
- Observed bars were bright green, dark red, strongly striped red/orange, strongly striped
  red/orange, and green.
- With the previous Style 1 bus, the transmitted white word was `{C=0x80,Y=0xEB}`. A Style 3
  receiver interprets this as `Y=0x80,C=0xEB`, which produces the observed bright green rather
  than white.
- Red and blue have widely different Cb/Cr values. Under the same wrong interpretation, those
  alternating chroma bytes become alternating Y values, exactly producing the observed dense
  vertical stripes.
- Green has comparatively close Cb/Cr values, so the same fault creates much weaker striping,
  also matching the photograph.
- This is direct board evidence that the currently effective ADV7511 input mapping is Style 3.

### Applied correction

- `R0x16` restored from `0xB1` to Style 3 value `0xBD`.
- `rgb2ycbcr422.data_o` restored from `{Cb/Cr,Y}` to `{Y,Cb/Cr}`.
- RGB source values remain `FFFFFF/000000/FF0000/0000FF/00FF00`.

### Regression evidence

- `4_metrics/logs/2026-09-05_adv7511_style3_rgb_run01/modelsim_video.txt`:
  `TEST_PASS`, 16/16 converted pixels, zero mismatches.
- `4_metrics/logs/2026-09-05_adv7511_style3_rgb_run01/modelsim_colorbar.txt`:
  `TOP_COLORBAR_RESET_PASS`, all five RGB source regions and S1 reset verified.
- `4_metrics/logs/2026-09-05_adv7511_style3_readback_run01/modelsim_success.txt`:
  `CFG_READBACK_SUCCESS_PASS`, expected `R0x16=0xBD`.
- Deliberate `R0x16=0xBC` mismatch still completes all six reads and reports bitmap `111011`.
- No bitstream was generated for this correction pass.

## No-change board result and build-signature test (historical before protocol resume)

- Board feedback after the Style 3 restoration was: the displayed image did not change at all.
- This result is inconsistent with a successfully loaded FPGA bus-packing change while the
  ADV7511 remains in the board-observed Style 3 interpretation. The leading unresolved cause is
  therefore stale/wrong bitstream selection or an unsuccessful FPGA programming operation.
- `LED[7:0]` is now temporarily a constant `8'hA5`; this path has no dependency on the ADV7511,
  I2C ACK/readback, pixel clock lock, or HDMI sink.
- Expected board indication after loading the newly rebuilt isolation bitstream:
  LED7, LED5, LED2, and LED0 on; LED6, LED4, LED3, and LED1 off.
- No bitstream was generated in this source-only pass. Board result remains pending.
- ModelSim source compilation passed for the active ADV7511/VTC/RGB/top-level source set.
- The self-checking signature simulation passed with reset both asserted and released:
  `BUILD_SIGNATURE_PASS LED=a5` at 101 ns.
- Evidence directory:
  `E:/competition/4_metrics/logs/2026-09-05_adv7511_build_signature_run01`.
- `modelsim.wlf` is non-empty at 81,920 bytes; the accepted raw transcript and prior command-line
  recovery attempts are retained in the same directory.
- The existing bitstream is conclusively stale for this new diagnostic:
  - current top source: `2026-09-05 13:03:41.221`, SHA-256
    `F5686C6C36D670CD0C6CA91369AB314AAB2E4D173ECD73AF20CBD549B5219371`
  - existing bitstream: `2026-09-05 12:59:34.874`, SHA-256
    `0401AC4E88DCC0905C0AC68B26B7A5340D9B8050F6E3F5C0AC2CCEFBD93E614C`
  - therefore the existing bitstream cannot contain the `8'hA5` signature and must be regenerated.

### Board result for the build signature

- The user rebuilt and downloaded the diagnostic image and reported
  `LED0..LED7 = 8'b1010_0101` on September 5, 2026.
- Because this pattern is exactly the fixed `8'hA5` top-level constant, the active FPGA image now
  demonstrably contains the current `hdmi_colorbar_vtc_top` source.
- Stale bitstream selection, use of the old Vitis wrapper bitstream, and failed FPGA configuration
  are therefore excluded for this run.
- The A5 revision deliberately changed only the LED output and did not alter the HDMI pixel stream,
  so no screen change between the immediately preceding Style 3 build and the A5 build is expected.
- The screen remaining incorrect with the proven-current Style 3 build moves the unresolved fault
  to the ADV7511 configuration/readback path or the effective 16-bit data-lane interpretation.
- The programmed A5 bitstream is timestamped `2026-09-05 13:11:49.160`, SHA-256
  `5A2DB66B3506DC05FF72D9D75B66FC18E4BB58164F7603473C23D249366DFC62`.
- The current top and rewritten I2C source files were modified later, at approximately `13:41`.
  Consequently, the A5 board observation does not contain or validate the rewritten protocol.
- At that earlier point, the user had paused further I2C protocol work and board testing. The
  rewritten source remained in the workspace; the protocol-inclusive revalidation is recorded
  in the section below.

## SW0 RGB/YCbCr mode-switch implementation

- `hdmi_colorbar_vtc_top.v` now has a top-level `SW0` input and two synchronized mode registers.
- `hdmi_colorbar_vtc_top.xdc` assigns `SW0` to `AB6/LVCMOS33`.
- RGB mode retains the existing RGB888 source and `rgb2ycbcr422` path.
- Direct mode outputs `EB/80/80`, `10/80/80`, `3E/66/EF`, `1F/EF/75`, and `AC/29/1A`
  for white, black, red, blue, and green, with alternating Cb/Cr bytes.
- `4_metrics/logs/2026-09-05_hdmi_mode_switch_run01/mode_result.txt` reports
  `MODE_SWITCH_PASS`.
- The same run contains a non-empty `mode_switch.wlf`, reset regression artifacts, and the full
  ModelSim transcript. No Vivado bitstream was generated.

## I2C protocol resumed and revalidated with SW0 source modes

历史记录（已被本文末尾“原始 I2C 协议恢复结果”替代）：协议重写版本曾是活动实现。
The video source switch
does not alter the ADV7511 I2C table: both paths emit the same 16-bit Style-3 YCbCr422 bus.

Current protocol RTL:

- `2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v`: FPGA-output SCL with open-drain bidirectional
  SDA, single-register write, random read with repeated START, ACK/NACK checking, single-byte
  master NACK, legal STOP and error STOP, fixed SCL timing, and explicit `iic_error`/
  `iic_rd_data_valid` status.
- `2_fpga/0_diaplay_test/rtl/hdmi_new/adv7511_iic_data_xfer.sv`: 34 initialization writes,
  six critical-register reads, masked matching, raw readback capture, and protocol error handling.
- `2_fpga/0_diaplay_test/rtl/hdmi_new/build_hdmi_colorbar_vtc.tcl`: now includes the low-level
  `../iic/iic_protocal.v` source.

Fresh ModelSim evidence was generated from the current sources under
`4_metrics/logs/2026-09-05_hdmi_protocol_sw0_run01`:

- `iic_protocol_result.txt`: `IIC_PROTOCOL_ALL_PASS`, starts=9, stops=8; this covers write,
  random read/repeated START, clock stretching, and four NACK stages.
- `cfg_success_result.txt`: `CFG_READBACK_SUCCESS_PASS`, 40 transactions, bitmap `111111`,
  raw readback `101208bd0110`.
- `cfg_mismatch_result.txt`: `CFG_READBACK_MISMATCH_PASS`, 40 transactions, bitmap `111011`,
  raw readback `101208bc0110`; the injected mismatch is detected without aborting the remaining reads.
- `cfg_nack_result.txt`: `CFG_NACK_FAST_ERROR_PASS`; a slave NACK reaches the error path quickly.

All three WLF files are non-empty and the corresponding complete ModelSim compile/run transcripts
are retained in the same evidence directory. This is RTL/protocol evidence only; no new bitstream
was generated and no board-level protocol result is claimed.

## HDMI 黑屏后续修正

用户反馈协议版本下载后 HDMI 完全无显示。按 ADV7511 手册重新检查后，优先修正初始化条件：

- ADV7511 上电后按手册等待 200 ms 再开始 I2C，工程中的配置延时由 120 ms 改为 200 ms；
- 按板级接口定义，协议改为 FPGA 单向输出 SCL、SDA 保持双向开漏；HDMI XDC 仅对 SDA
  增加 FPGA 弱上拉，外部电阻仍作为主要上拉来源。

修改后 SW0 模式切换仿真仍为 `MODE_SWITCH_PASS`。本轮未生成 bitstream，板级确认需要用户
重新综合、实现并下载当前工程。

## 2026-09-05 原始 I2C 协议恢复结果

用户随后明确要求“改回原来的协议”。当前源代码状态已调整为：

- `rtl/iic/iic_protocal.v` 恢复仓库原始状态机和时序接口；不再包含重写版专有的
  `iic_error` 端口。SCL 仍是 FPGA 单向输出，SDA 仍为双向开漏连接。
- `rtl/hdmi_new/adv7511_iic_data_xfer.sv` 删除 `iic_error` 连接和即时错误分支，保留原有
  超时错误路径、34 笔初始化写入、6 笔关键寄存器回读和位图/原始值输出。
- SW0 RGB888/直出 YCbCr422 视频路径没有回退，顶层 `HDMI_SCL` 仍为输出端口。

原始协议回归证据位于
`E:/competition/4_metrics/logs/2026-09-05_adv7511_i2c_original_run01`：

- `cfg_success_result.txt`：`CFG_READBACK_SUCCESS_PASS`，40 笔事务，回读位图
  `111111`，原始回读 `101208bd0110`。
- `cfg_mismatch_result.txt`：`CFG_READBACK_MISMATCH_PASS`，40 笔事务，注入错误后位图
  `111011`，原始回读 `101208bc0110`，说明回读流程仍能完整跑完并定位错误。
- `mode_switch_original.wlf` 非空；当前顶层重新编译后 `mode_result.txt` 保持
  `MODE_SWITCH_PASS`。
- 低层独立旧版测试台的 NACK/时序断言不再作为验收依据，因为该测试台原本针对重写协议
  的即时错误/合法错误 STOP 行为；配置级原始协议回归已通过。

本轮没有生成或下载 bitstream；下一步由用户用当前源代码重新综合、实现、生成并下载。

## 2026-09-05 板级竖条现象与物理字节交换

用户上传的板级图像表现为：左侧白色区域偏绿色、黑色区域偏红，中间红/蓝区域出现逐像素
竖条，绿色区域相对正常。这个组合不是 RGB 转换系数误差，而是 YCbCr422 两个 8 位字节被
ADV7511 按相反顺序解释的特征：当前逻辑 `{Y,Cb/Cr}` 被实际链路当成 `{Cb/Cr,Y}`。

手册 Table 7 对 `R0x16=0xBD` 的 Style 3 定义仍保持不变，因此没有修改初始化寄存器；
只在 FPGA 物理输出边界增加：

```text
physical_data = {logical_data[7:0], logical_data[15:8]}
```

已修改：

- `rtl/hdmi_new/hdmi_colorbar_vtc_top.v`
- `rtl/hdmi_new/hdmi_out_adv7511.v`
- `sim/hdmi_out_adv7511_tb.sv` 的硬件字节顺序期望值

验证记录：

- `4_metrics/logs/2026-09-05_hdmi_physical_byte_swap_run01/hdmi_video_result.txt`：
  `HDMI_VIDEO_PASS: pixels=16 mismatches=0`。
- 原始协议配置回读和 SW0 帧边界切换仍保持之前的 PASS 结果。

尚未生成或下载新的 bitstream。下一次上板应确认五个区域依次显示白、黑、红、蓝、绿；若
仍出现同样的条纹，应优先读取 LED6:LED0 对应的 `R0x16` 回读值，确认板上实际为 `0xBD`，
不要先修改 RGB 转换公式。

## 2026-09-05 最新板级结果归档（run02）

- 用户上传的新照片已原样归档至
  `4_metrics/logs/2026-09-05_hdmi_board_result_run01/board_result_2026-09-05_run02.jpg`。
- 观察结果：HDMI 仍能稳定显示；画面颜色和五色顺序仍不正确，并存在明显密集竖状条纹。
- 本照片只作为板级现象证据，不能证明 ADV7511 配置、寄存器回读、YCbCr 字节顺序或颜色映射已经正确。
- 本次没有重新综合、实现、生成 bitstream、下载 FPGA，也没有修改 RTL、I²C 协议、ADV7511 寄存器表、XDC 或测试平台。
- 原图 SHA-256：`E3D91414AB79266C725F0A276155BC2F8B87EC19A3AD8058ABB52B36F7A3A75E`。
- 详细记录见：`4_metrics/logs/2026-09-05_hdmi_board_result_run01/board_result.md`。
