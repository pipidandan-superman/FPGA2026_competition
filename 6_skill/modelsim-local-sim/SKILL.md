---
name: modelsim-local-sim
description: Run small RTL/SystemVerilog simulations reliably on this Windows host using local ModelSim SE-64 command-line or GUI execution. Prefer background `vsim -c` runs and use the GUI only after an evidenced command-line failure. Use when a local ModelSim test needs self-checking testbenches, `.do` scripts, wave/transcript evidence, or license-aware recovery.
---

# Local ModelSim simulation

Use this workflow for local RTL operator tests. Prefer non-interactive, run-local command-line execution; keep the GUI only as a recovery path.

## Default: command-line background run

- Treat background `vsim -c` as the mandatory first execution path for every new run. When command-line simulation has already been demonstrated to work for the active workspace, do not choose the GUI merely because it is open or because waveform viewing is convenient.
- For the ViTA workspace (`D:\VitA`), the project `12_skills/modelsim_simulation/SKILL.md` overrides this generic workflow: invoke only its `scripts/run_modelsim_backend.ps1` launcher. Do not run a bare `vsim.exe -c` from PowerShell, Codex PTY, redirected Bash, or an ad-hoc script; that bypasses the required real Mintty/Git Bash terminal and its controlled license context.
- Outside ViTA, first run the generated `.do` script with the local `vsim -c` in a background or bounded shell process.
- Direct the transcript, WLF, temporary library and all raw artifacts to the run-local directory.
- Use a unique library and absolute source paths. Do not remap `work`, delete shared libraries or change the user's project directory.
- Read the complete transcript from disk only after the terminal process exits and require the testbench's stable `PASS` marker. In ViTA, `process_status.txt` alone is not proof that Mintty has flushed the ModelSim transcript/WLF; the project launcher must wait for Mintty exit before assessing the run. If ModelSim omits a final `$display` from `-l`, require an explicit run-local testbench result file with the same PASS/FAIL marker and have the ViTA launcher verify it.
- In ViTA, a run that exceeds its launcher timeout is failed evidence. The launcher must terminate only the Mintty process tree rooted at the PID it created before returning the timeout error, so no orphaned Bash or `vsim` process can contaminate a later run. Do not invoke the GUI to recover a timed-out run unless the project launcher has produced a retained `CHANNEL_ERROR` report for that exact run.
- Record the exact command and any command-line license failure in the run record.
- If the command-line run passes, archive its non-empty waveform and comparison artifacts and do not repeat it in GUI.

Generic example invocation (do not use this form in ViTA):

```powershell
& 'D:\work\modelsim\win64\vsim.exe' -c -do 'do D:/project/5_verify/release/runs/run-id/run_modelsim.do'
```

## GUI fallback only

- Use the existing `ModelSim SE-64 10.1c` GUI only if the same run's approved command-line attempt has failed because of terminal-specific environment issues. For ViTA, this means the project launcher must have retained a `CHANNEL_ERROR` report for that same run first; a bare PowerShell license failure is an invalid invocation, not a GUI-fallback reason. A prior GUI success, an already-open GUI, or a desire to inspect waves is not a fallback reason.
- Save the failed command-line transcript, then submit the same run-local `do D:/absolute/path/to/run_modelsim.do` in the GUI Transcript.
- Do not repeatedly retry `vsim -c` after the same shell license failure; the GUI may have a valid license context.
- Do not use `quit` or `quit -sim` in reusable `.do` scripts. Testbench `$finish` ends only the current simulation.
- If `$finish` leaves the GUI paused before VCD data is committed, execute `vcd flush` and verify that the run-local VCD is non-empty before accepting waveform evidence.

## Build a non-disruptive run

Create one evidence directory per run, for example `5_verify/<release>/runs/<run-id>/`, containing the `.do` file, complete Transcript, raw output, comparison JSON and report.

- Use absolute paths for all sources, `$readmemh`/`$readmemb` images and transcript files. The GUI can inherit another project's working directory.
- Use a uniquely named temporary library; do not remap `work`, do not delete libraries and do not change the user's project directory. `vmap work ...` or `cd ...` can prompt to close the current project.
- Compile only the operator and self-checking testbench needed for the current stage; do not add PS, AXI, DMA or full-system logic prematurely.
- Have the testbench reject unknown values before comparing, print a stable `PASS`/`FAIL` marker, and print expected/actual values plus relevant accumulator, overflow and saturation counters.

Minimal `.do` pattern (replace paths and names):

```tcl
transcript file D:/project/5_verify/release/runs/run-id/modelsim_transcript.txt
if {![file exists stage_lib]} { vlib stage_lib }
vlog -work stage_lib -sv D:/project/rtl/rom.sv
vlog -work stage_lib -sv D:/project/rtl/operator.sv
vlog -work stage_lib -sv D:/project/rtl/tb_operator.sv
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

- **Headless license failure:** in ViTA, treat a bare-shell license error as an invalid entry channel and use the project launcher instead; elsewhere retain the failure and use the GUI only after the approved command-line route has failed.
- **Relative memory file failure:** convert all testbench memory paths to absolute paths, reject unknown values, then rerun.
- **Close-project prompt:** select No, remove `cd` and `vmap work` from the `.do`, and use an independent library name.
- **Finish-Vsim prompt:** do not close the reusable GUI; end only the previous simulation if a rerun is intentional, then submit the corrected `.do`.
