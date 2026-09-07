---
name: modelsim-local-sim
description: Run small RTL/SystemVerilog simulations reliably on this Windows host using local ModelSim SE-64 command-line or GUI execution. Prefer background `vsim -c` runs and use the GUI only after an evidenced command-line failure. Use when a local ModelSim test needs self-checking testbenches, `.do` scripts, wave/transcript evidence, or license-aware recovery.
---

# Local ModelSim simulation

Use this workflow for local RTL operator tests. Prefer non-interactive, run-local command-line execution; keep the GUI only as a recovery path.

## Project adaptation for E:\competition

This section is mandatory and overrides the historical ViTA text below.

- Workspace root: `E:\competition`.
- Create one new evidence directory per run at
  `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN\`.
- Put `.do`, transcript, WLF, result file, raw console output, and report in
  that run directory. Never create them at the repository root.
- Treat `E:\competition\2_fpga` as frozen: read sources by absolute path, but do
  not write libraries, logs, waveforms, or generated files into it.
- Use absolute `E:/competition/...` paths in every `.do` command.
- Have the testbench emit a stable `EES_MODELSIM_RESULT PASS` or
  `EES_MODELSIM_RESULT FAIL` marker and a run-local result file.

## Default: command-line background run

- Treat background `vsim -c` as the mandatory first execution path for every new run. When command-line simulation has already been demonstrated to work for the active workspace, do not choose the GUI merely because it is open or because waveform viewing is convenient.
- The historical ViTA launcher rule belongs to `D:\VitA` and is not executable
  here. In `E:\competition`, first run the generated `.do` script with the local
  `vsim -c` in a background or bounded shell process.
- Direct the transcript, WLF, temporary library and all raw artifacts to the run-local directory.
- Use a unique library and absolute source paths. Do not remap `work`, delete shared libraries or change the user's project directory.
- Read the complete transcript from disk only after the terminal process exits
  and require the testbench's stable `PASS` marker. A launcher status file alone
  is not proof that the process flushed the ModelSim transcript/WLF. If ModelSim
  omits a final `$display` from `-l`, require an explicit run-local testbench
  result file with the same PASS/FAIL marker and have the launcher verify it.
- A run that exceeds its bounded timeout is failed evidence. Terminate only the
  process tree created for that exact run before returning the timeout error, so
  no orphaned simulator process can contaminate a later run. Do not invoke the
  GUI to recover a timed-out run unless the failed command-line run has a
  retained transcript that identifies the terminal/environment failure.
- Record the exact command and any command-line license failure in the run record.
- If the command-line run passes, archive its non-empty waveform and comparison
  artifacts under the `E:\competition\4_metrics\logs` run directory and do not
  repeat it in GUI.

Generic example invocation:

```powershell
& 'D:\work\modelsim\win64\vsim.exe' -c -do 'do E:/competition/4_metrics/logs/2026-09-06_<task>_runNN/run_modelsim.do'
```

## GUI fallback only

- Use the existing `ModelSim SE-64 10.1c` GUI only if the same run's approved
  command-line attempt has failed because of terminal-specific environment
  issues. The failed transcript must show that failure first; a bare PowerShell
  license failure without a retained run transcript is not enough, and a prior
  GUI success, an already-open GUI, or a desire to inspect waves is not a
  fallback reason.
- Save the failed command-line transcript, then submit the same run-local `do D:/absolute/path/to/run_modelsim.do` in the GUI Transcript.
- Do not repeatedly retry `vsim -c` after the same shell license failure; the GUI may have a valid license context.
- Do not use `quit` or `quit -sim` in reusable `.do` scripts. Testbench `$finish` ends only the current simulation.
- If `$finish` leaves the GUI paused before VCD data is committed, execute `vcd flush` and verify that the run-local VCD is non-empty before accepting waveform evidence.

## Build a non-disruptive run

Create one evidence directory per run at
`E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN\`, containing the `.do`
file, complete Transcript, raw output, comparison JSON and report.

- Use absolute paths for all sources, `$readmemh`/`$readmemb` images and transcript files. The GUI can inherit another project's working directory.
- Use a uniquely named temporary library; do not remap `work`, do not delete libraries and do not change the user's project directory. `vmap work ...` or `cd ...` can prompt to close the current project.
- Compile only the operator and self-checking testbench needed for the current stage; do not add PS, AXI, DMA or full-system logic prematurely.
- Have the testbench reject unknown values before comparing, print a stable `PASS`/`FAIL` marker, and print expected/actual values plus relevant accumulator, overflow and saturation counters.

Minimal `.do` pattern (replace paths and names):

```tcl
transcript file E:/competition/4_metrics/logs/2026-09-06_<task>_runNN/modelsim_transcript.txt
if {![file exists stage_lib]} { vlib stage_lib }
vlog -work stage_lib -sv E:/competition/2_fpga/<frozen-source-path>/rom.sv
vlog -work stage_lib -sv E:/competition/2_fpga/<frozen-source-path>/operator.sv
vlog -work stage_lib -sv E:/competition/4_metrics/logs/2026-09-06_<task>_runNN/tb_operator.sv
vsim -voptargs=+acc stage_lib.tb_operator
log -r /*
add wave -position insertpoint sim:/tb_operator/*
run -all
```

## Validate and record

1. Read the transcript from disk; do not rely only on the GUI display.
2. Treat missing memory-image warnings or `x/x` comparisons as invalid runs, never as PASS.
3. Save raw simulated output and compare it element-wise to frozen golden data. Record input/parameter hashes, mismatch count, first mismatch, saturation count and overflow count.
4. If a WLF is required, issue `log -r /*` before `run -all`; `-wlf` by itself may not record any signals. If `vsim.wlf` is locked, record the alternate WLF location or rerun with a run-local waveform path; do not claim a waveform artifact that was not saved.
5. State the exact coverage boundary. A one-output-channel PASS is not a full layer, Encoder, synthesis or board PASS.

## Recovery

- **Headless license failure:** retain the complete failure and use the GUI only
  after the approved command-line route has failed.
- **Relative memory file failure:** convert all testbench memory paths to absolute paths, reject unknown values, then rerun.
- **Close-project prompt:** select No, remove `cd` and `vmap work` from the `.do`, and use an independent library name.
- **Finish-Vsim prompt:** do not close the reusable GUI; end only the previous simulation if a rerun is intentional, then submit the corrected `.do`.
