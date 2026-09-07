---
name: modelsim-gui-sim
description: Run and validate ModelSim simulations through the already-open ModelSim GUI Transcript. Use when Codex needs ModelSim/Questa simulation, waveform evidence, or `.do` execution and direct headless `vsim -c` is unavailable, fails license checkout, or the user asks to send commands into the ModelSim command window.
---

# ModelSim GUI Simulation

Use this workflow when ModelSim GUI can simulate but Codex shell cannot run `vsim -c` because of license environment differences.

## Project adaptation for E:\competition

- Workspace root: `E:\competition`.
- Run directory: `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN`.
- Read frozen RTL under `E:\competition\2_fpga` by absolute path, but never write
  `.do`, libraries, transcripts, WLF files, screenshots, or reports there.
- Use absolute `E:/competition/...` paths in ModelSim Tcl.
- Require a run-local stable `EES_MODELSIM_RESULT PASS` marker and a complete
  transcript before recording PASS.

## Core Rule

Prefer executing a generated `.do` file in the existing ModelSim GUI Transcript instead of launching `vsim.exe` from shell.

Do not conclude ModelSim is unusable merely because `vsim -c` fails. Treat that as a headless-shell issue if the GUI is already open and able to run simulations.

## Required Artifacts

For each simulation target, create or verify:

- RTL/SystemVerilog source files.
- A self-checking testbench that prints clear PASS/FAIL lines.
- A ModelSim `.do` script with absolute paths.
- A transcript output path under
  `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN`.
- A short simulation report summarizing key transcript lines and numeric checks.

For nonlinear operator work, the first simulation stage must target the operator itself only. Do not include PS control, AXI-Lite registers, DMA shell, or extra system integration until the operator-only datapath has passed.

## Recommended `.do` Pattern

Use a dedicated work library for the target rather than deleting the GUI's current `work` library.

```tcl
transcript file E:/competition/4_metrics/logs/2026-09-06_<task>_runNN/modelsim_transcript.txt
if {![file exists ees_<run_name>_work]} {
  vlib ees_<run_name>_work
}
set ees_run_lib ees_<run_name>_work
vlog -work $ees_run_lib -sv E:/competition/2_fpga/<frozen-source-path>/source1.sv
vlog -work $ees_run_lib -sv E:/competition/2_fpga/<frozen-source-path>/source2.sv
vlog -work $ees_run_lib -sv E:/competition/4_metrics/logs/2026-09-06_<task>_runNN/testbench.sv
vsim -voptargs=+acc $ees_run_lib.<testbench_top>
add wave -position insertpoint sim:<testbench_path>
run -all
```

Notes:

- Do not put `quit` or `quit -sim` in a reusable project `.do`; end only the
  previous simulation intentionally after asking the user or confirming the GUI
  state.
- Do not use `vdel -lib work -all` in a shared GUI project; it can conflict with the user's current ModelSim project.
- Do not remap the GUI's shared `work` library; compile and simulate with a
  unique run-local library.
- Use absolute `E:/competition/...` style paths in `.do` files.
- Ensure the testbench prints a stable pass marker such as `PASS: ... simulation completed`.

## GUI Execution Workflow

1. Prepare the `.do` file and self-checking testbench.
2. If useful, run `vlog` from shell for compile-only syntax checking; this may work even when `vsim -c` does not.
3. Prefer launching ModelSim GUI with its own `-do` argument only when that launcher is known to share the working GUI/license environment:

```powershell
& 'D:\work\modelsim\win64\modelsim.exe' -do 'do E:/competition/4_metrics/logs/2026-09-06_<task>_runNN/run_target.do'
```

This keeps the GUI/license path while avoiding unreliable text injection into old ModelSim Transcript widgets.

4. If the launcher path opens a "Fatal License Error" dialog, do not retry it. This means the shell-launched ModelSim process is using a different license environment than the user's already-working GUI. Close the dialog and use the already-open working GUI Transcript path instead.
5. If the launcher path does not run the script, use the `computer-use` skill to control Windows.
6. Find the open ModelSim window, usually app id similar to `process:D:\work\modelsim\win64\vish.exe`.
7. Activate the ModelSim window.
8. Click the Transcript prompt area.
9. Type:

```tcl
do E:/competition/4_metrics/logs/2026-09-06_<task>_runNN/run_target.do
```

10. Press Return.
11. Wait for the simulation to finish.
12. Read the transcript file from disk and summarize PASS/FAIL, not only the screenshot.

If a "Finish Vsim" confirmation dialog appears:

- If re-running intentionally, click Yes to end the previous sim.
- Then add or keep `catch {quit -sim}` near the top of future `.do` files.

## Evidence Policy

Always preserve:

- The `.do` file used.
- The full transcript text.
- The exact PASS/FAIL line.
- Any numeric summary printed by the testbench.
- A Markdown report under the same
  `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN` directory.

For hardware operator validation, include:

- operator name;
- shape;
- numeric format;
- vector source;
- total cases/elements;
- mismatch count;
- max raw error if applicable;
- Python golden error metrics if available;
- functional correctness result;
- broad test case categories and coverage counts;
- per-test-case latency/cycle analysis;
- summary tables, preferably CSV plus Markdown;
- remaining unverified items.

## Failure Handling

If GUI automation cannot target ModelSim:

- Report that GUI command injection is unavailable.
- Provide the exact `do ...` command for the user to paste into Transcript.
- Use xsim or another available simulator for command-line regression if project policy allows.

If ModelSim GUI reports compile or simulation errors:

- Save the transcript.
- Fix RTL/testbench issues.
- Re-run through the same `.do` flow.

If shell `vsim -c` fails with license checkout but GUI works:

- Do not keep retrying headless `vsim`.
- Continue through GUI Transcript execution.

## Windows Automation Safety

Use Computer Use APIs for GUI interaction. Do not automate terminals through Windows UI. Do not use Windows Run dialog. Avoid changing ModelSim installation, license settings, or system environment variables unless the user explicitly requests that configuration work.
