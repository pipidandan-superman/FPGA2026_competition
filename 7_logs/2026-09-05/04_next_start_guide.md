# 2026-09-05 Next Start Guide

## Current handoff after live pin trace

- Do not rerun RTL guesses: obtain a clear board/connector/jumper photo and confirm whether a meter or scope is available.
- Check the VADJ pull-up node shared by R110/R140 and actual SCL/SDA waveforms. The observed coupling is not yet a voltage measurement or proof of a particular hardware defect.
- Current PL runs the run02 open-drain diagnostic image and automatically retries after errors; initialization has not passed on hardware.
- Keep `hdmi_diagnostic.bit` paired with its same-directory `.ltx`; use the retained capture script after external conditions are corrected.
- Read `DIAGNOSIS.md` before altering any register table, input style, byte ordering or I2C driver.

## Resumed investigation takes precedence over historical pause

- Read the root-cause run01 live ILA CSV and the newest run02 build/capture records first.
- Board was temporarily programmed through JTAG; the original project's bitstream has not been overwritten.
- Do not restore the unjustified byte swap or equate LED6:0 all-high with successful initialization.
- Next action: capture run02 actual readback and, if errors persist, trigger the retained I2C state/SDA/SCL probes during a read.
- Screen correctness still needs a fresh board photograph; do not substitute RTL simulation PASS for display validation.

## Read first

- This day's `03_validation_summary.md` after it is updated.
- `E:/competition/HANDOFF.md`
- The active HDMI initialization table and top-level RTL identified during this session.

## First concrete action next time

The fixed `8'hA5` signature was observed on the board for the earlier isolation image, proving
that image was programmed successfully. That image predates the current protocol rewrite and SW0
mode switch, so the next board image must be rebuilt from the current source set.

1. Rebuild the current pure-PL source set, including the rewritten I2C protocol and SW0 input.
2. Program the new bitstream and record the reset signature, post-reset LED pattern, and HDMI
   result before making another RTL change.
3. If video diagnosis is still needed, use a direct 16-bit HDMI bus pattern test using constant
   words such as `0000`, `FFFF`, `FF00`, `00FF`, and `AA55`, without changing ADV7511 registers.
4. Use the screen response to determine whether the upper byte, lower byte, or alternating bits are
   being sampled differently from the schematic/constraint assumption.
5. Restore the five-color RGB source only after the physical bus interpretation is established.

## Do not do immediately

- Do not use the older Vitis `design_1_wrapper.bit`; it is a different hardware architecture.
- Do not reuse an old `.bit` merely because its timestamp is recent.
- Do not change several register fields and RTL packing rules in one board test.
- Do not mix Style 1 and Style 3 settings. The current diagnostic source uses the board-proven
  matched pair `R0x16=0xBD` plus `{Y,Cb/Cr}`.
- Do not debug VDMA/camera while the pure-PL isolation bitstream is under test.

## Success criterion

The next board diagnostic bitstream must use the explicitly identified rewritten I2C version and
produce distinct screen regions for the five fixed 16-bit words. The raw register readback issue
remains a separate test and must not be inferred from the A5 result.

## Current implementation handoff

- The next compile must include the new top-level `SW0` port and the `AB6` constraint.
- Program the pure-PL bitstream with `SW0=0` first; LED7 should be off and the RGB-conversion
  bars should appear.
- Move SW0 to `1`; after at most one frame LED7 should turn on and the direct YCbCr422 bars should
  appear without changing geometry.
- Do not change the ADV7511 register table or I2C protocol while comparing the two modes.

## Protocol-restored next run

- Rebuild the current pure-PL source set so the downloaded image contains SW0 mode switching and
  the restored original `iic_protocal.v`.
- Do not expect the removed rewritten-protocol `iic_error` signal; configuration failures are
  reported through the existing timeout/error path.
- Before board testing, check LED7 for the latched SW0 mode and LED6:LED0 for the selected
  low-seven-bit readback indication. The reset signature remains `8'hA5` only while reset is active.
- If HDMI remains unchanged, first record the LED pattern and the six raw readback bytes; do not
  infer protocol success from the presence of a clock or a partially visible image.

## Physical byte-swap board test

- Rebuild from the current sources, including the new `physical_data` byte swap.
- Program the pure-PL bitstream with `SW0=0`, then verify the five regions in order: white, black,
  red, blue, green.
- Toggle `SW0=1` and verify the same region order; only the source-generation path should change.
- Record LED7 and LED6:LED0. LED6:LED0 should contain the low seven bits of the read-back `R0x16`
  value (`0xBD` gives `7'b0111101`).
- If stripes persist, capture the actual `R0x16` value and do not change the color-conversion
  coefficients until the register and physical byte order are confirmed.

## 2026-09-05 板级结果归档后的暂停边界

- 最新板级照片已经归档；当前结论是“HDMI 可显示，但颜色/色块仍错误且有明显竖条纹”。
- 用户已要求当前只保存记录，不再继续修改。因此下一次启动前不要自动修改 RTL、I²C 协议、ADV7511 寄存器、物理字节交换、XDC 或测试台。
- 若用户后续重新开始调试，第一步应先读取本日 `03_validation_summary.md`、
  `E:/competition/HANDOFF.md` 和
  `4_metrics/logs/2026-09-05_hdmi_board_result_run01/board_result.md`，再由用户指定新的单变量实验。
- 当前照片对应的原始证据副本为
  `4_metrics/logs/2026-09-05_hdmi_board_result_run01/board_result_2026-09-05_run02.jpg`。
