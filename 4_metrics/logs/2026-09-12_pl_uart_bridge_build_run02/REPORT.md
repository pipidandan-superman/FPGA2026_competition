# PL USB-UART bridge: simulation / build pass, board pending

## Scope and results

- New independent `ble_uart_debug_top`, no automatic AT and no ILA.
- XSim runtime: `BLE_UART_BRIDGE_SIM_PASS host=18 module=13` at 31.408 ms.
- Covered startup/reset, ASCII request/reply, 00/FF/AA/55, concurrent full duplex,
  post-reset A5/5A, unexpected bytes, X/Z and framing errors.
- Simulated `654321` is test fixture data, **not the module PIN**.
- Vivado 2025.2 synthesis, route and bit generation: PASS, process exit 0.
- Setup slack 5.872 ns; hold slack 0.160 ns. See timing_summary.rpt.
- DRC: no errors; ZPS7-1 warning remains because this diagnostic is PL-only, with no PS7.
- CDC report: 2 safe crossings, 0 unsafe, 39 unknown asynchronous-reset endpoints.
  This report is not CDC/reset-release signoff; raw SYS_RST_N drives asynchronous resets.
  A production integration should add synchronized reset deassertion and rerun CDC.
  The current artifact is for controlled bench debugging, not robotic-arm control.
- Hardware project references exactly one design RTL and one XDC, without imported copies.
- Original five source files and original AT/ILA bit hashes unchanged; see JSON manifests.
- Skill path audit PASS. Existing unrelated dirty workspace changes preserved; no Git publish.

## Output

`E:/competition/2_fpga/1_ble_test/proj/ble_uart_debug_vivado_2025_2/ble_uart_debug_vivado_2025_2.runs/impl_1/ble_uart_debug_top.bit`

SHA-256: 1B3CE99F0AE7A3CC312A7F8A0E76311158C02FAED8EFF7BF4F9F453DD27D373D.

No LTX is required for this variant. Do not load the old AT/ILA LTX with this bit.

## Reproduction / evidence

Launcher: `4_metrics/scripts/run_vivado_standalone_ees.ps1`, parameters:
TclFile=this directory/run.tcl; RunDirectory=this directory;
VivadoBat=F:/vivado2025/2025.2/Vivado/bin/vivado.bat; TimeoutSeconds=600.
See run_input_manifest.json, source_hashes.json, process_status.json, vivado_console.log,
sim_project/bridge_sim.sim/sim_1/behav/xsim/simulate.log and tb_result.txt.

GUI-environment extraction failed before launch in build_run01. Fresh standalone env_run02
loaded the simulator feature and completed runtime smoke. env_run01 ran but the old wrapper
misclassified echoed failure-handler source; wrapper now anchors actual diagnostic lines.
No manual RDI variables were supplied. The simulator generated small WDB containers despite
disabled signal logging; the three exact generated WDB files (env_run01/env_run02/build_run02)
were removed after completion as required by the simulation skill. Runtime text is retained;
those disposable containers can be regenerated, but were not moved to Recycle Bin.

## Next gate

User downloads the new bit, disconnects BLE, waits at least 1.1 seconds, then COM4 at
9600/8N1/no flow control. Real AT/OK is the first physical bridge acceptance gate.
Actual firmware version, PIN query syntax, PIN value and wireless return path remain unknown.
No COM4 AT query, PIN modification, or hardware programming was performed by this build run.
