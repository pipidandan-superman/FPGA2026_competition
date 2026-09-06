---
name: vita-vivado-batch-sim
description: Run reproducible ViTA Vivado 2020.2/XSim simulations in batch mode without GUI, including pure RTL, XCI/IP, BD, and official AXI DMA/Datamover flows. Use for launching, monitoring, validating, or regression-testing Vivado simulations with isolated artifacts, hashes, result markers, and process evidence.
---

# ViTA Vivado batch simulation

Use Vivado batch mode as the default for Xilinx IP and AXI DMA simulation. Keep
ModelSim for existing pure RTL boundaries; do not use the invalid shared
ModelSim vendor simlib as the official DMA path.

Before creating a regression, run a no-IP smoke through the same non-GUI
launcher and require a successful XSim `simulator` feature checkout. Treat
`Failed to load feature 'simulator'`, an empty launcher log, or exit code 1
before a Vivado/XSim banner as environment blockers, not as design failures.
Do not count compile/elaboration-only runs as simulation PASS.

Every run uses a new absolute directory under
`D:\VitA\5_verify\vivado_batch\runs\<run-id>`. Preserve TCL, wrapper log,
Vivado journal, simulation log, `result.json`, process status, and the
launcher-generated pre-launch `run_input_manifest.json` (absolute paths,
sizes, timestamps, SHA-256 hashes for all run-local inputs). Preserve any
additional source/vector hash manifest required by the test-specific Tcl.
Waveform databases are disabled and must not be retained; console/simulation
print output is the authoritative runtime evidence. Never reuse a prior run
directory.

When a working Vivado GUI process is available, use its runtime environment as
the default backend. This starts a new batch-only Vivado process; it does not
open another GUI and it preserves a complete run-local transcript:

```powershell
& C:\Users\Administrator\.codex\skills\vita-vivado-batch-sim\scripts\run_vivado_from_gui_env.ps1 `
  -GuiPid <working-vivado-gui-pid> `
  -TclFile D:\VitA\5_verify\vivado_batch\runs\<run-id>\run.tcl `
  -RunDirectory D:\VitA\5_verify\vivado_batch\runs\<run-id> `
  -TimeoutSeconds 300
```

The runner records the exact Vivado path, GUI parent PID, batch PID, exit code,
PASS marker, fatal/error detection, and complete raw output. Exit code zero
alone is not a functional PASS. Do not use `start /B` as the result gate: it
only proves that a child was requested, not that simulation completed.

TCL must use absolute paths, operate on a diagnostic/run-local project, register
all sources explicitly, generate IP simulation targets, update compile order,
launch behavioral simulation, run a bounded/self-terminating test, emit stage
markers, and close simulation/project under `catch`.

Testbenches must emit `VITA_VIVADO_STAGE <name>`,
`VITA_VIVADO_RESULT PASS/FAIL`, a run-local result file, a watchdog, X/Z
rejection, and protocol checks. Real DMA tests must instantiate the official
generated AXI DMA wrapper and observe 64-bit memory traffic plus 32-bit AXIS;
a simplified behavioral placeholder is not real-DMA evidence.

Regression runs are serial unless isolation and license parallelism are proven.
Every retry gets a new run ID. Missing markers, timeout, compiler/elaboration
error, X/Z, stale result, orphan process, or missing raw log invalidates the
run. On timeout, require the launcher to kill the batch tree, drain both output
streams, write `vivado_console.log`, and write `process_status.json` with
`timed_out: true` before returning failure. Preserve failures. If batch
environment failure repeats three times, an
explicitly authorized external Claude fallback may run Vivado, but its output
still passes this skill's result and hash checks.

The launcher rejects any Tcl that enables `xsim.simulate.log_all_signals 1`.
This prevents future runs from creating waveform databases; use the complete
console/simulation printout and machine-readable result files for analysis.

The GUI-environment backend was verified on 2026-08-22 with a new no-IP batch
process: compile, elaboration, `Loading simulator feature`, PASS marker, and
natural process exit. Use it for every subsequent Vivado/XSim run unless a
fresh standalone environment validation replaces it. If no verified GUI
environment exists, stop at preflight and report the blocker; do not fall back
to GUI interaction, `start /B`, direct partially-configured XSim executables,
or a behavioral DMA placeholder.
