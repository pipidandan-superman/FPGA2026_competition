---
name: vita-vivado-batch-sim
description: Run reproducible EES-331 Vivado/XSim simulations in batch mode without GUI. Use for launching, monitoring, validating, or regression-testing this project's Vivado simulations with isolated artifacts, hashes, result markers, and process evidence. The retained skill name is historical; all writable paths and result markers are project-adapted.
---

# EES-331 Vivado batch simulation

## Project adaptation for E:\competition

- Workspace root: `E:\competition`.
- Target: EES-331, XC7Z020 CLG484-1, with the active EES-331 Vivado
  environment (currently Vivado 2025.2).
- Every run directory must be a new absolute directory under
  `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN`.
- Read frozen RTL under `E:\competition\2_fpga`; never write libraries,
  journals, logs, waveform databases, reports, or scratch files into it.
- Use the project-local launcher
  `E:\competition\4_metrics\scripts\run_vivado_batch_ees.ps1`; it derives the
  Vivado environment from a working GUI PID, validates the run directory, and
  requires `EES_VIVADO_RESULT PASS`.
- Use `EES_VIVADO_STAGE <name>` and `EES_VIVADO_RESULT PASS/FAIL` in testbenches
  and Tcl. The historical ViTA protocol names are not used for new runs.
- For the no-IP reference Tcl, set `EES_VIVADO_RUN_DIR` to the same approved run
  directory before launching; never let XSim create its project in the current
  working directory or repository root.

Use Vivado batch mode as the default for Xilinx IP and AXI DMA simulation. Keep
ModelSim for existing pure RTL boundaries; do not use the invalid shared
ModelSim vendor simlib as the official DMA path.

Before creating a regression, run a no-IP smoke through the same non-GUI
launcher and require a successful XSim `simulator` feature checkout. Treat
`Failed to load feature 'simulator'`, an empty launcher log, or exit code 1
before a Vivado/XSim banner as environment blockers, not as design failures.
Do not count compile/elaboration-only runs as simulation PASS.

Every run uses a new absolute directory under
`E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN`. Preserve TCL, wrapper log,
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
& E:\competition\4_metrics\scripts\run_vivado_batch_ees.ps1 `
  -GuiPid <working-vivado-gui-pid> `
  -TclFile E:\competition\4_metrics\logs\2026-09-06_<task>_runNN\run.tcl `
  -RunDirectory E:\competition\4_metrics\logs\2026-09-06_<task>_runNN `
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

Testbenches must emit `EES_VIVADO_STAGE <name>`,
`EES_VIVADO_RESULT PASS/FAIL`, a run-local result file, a watchdog, X/Z
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

The project launcher rejects any Tcl that enables
`xsim.simulate.log_all_signals 1`.
This prevents future runs from creating waveform databases; use the complete
console/simulation printout and machine-readable result files for analysis.

The historical GUI-environment method was verified in the source project with a
new no-IP batch process. Before first use after any Vivado version change, rerun
a no-IP smoke in this EES-331/Vivado 2025.2 environment. Use it for every
subsequent Vivado/XSim run unless a fresh standalone environment validation
replaces it. If no verified GUI
environment exists, stop at preflight and report the blocker; do not fall back
to GUI interaction, `start /B`, direct partially-configured XSim executables,
or a behavioral DMA placeholder.
