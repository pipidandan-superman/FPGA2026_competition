---
name: vivado-bd-bitstream
description: General Vivado batch flow for taking a Zynq/AMD design from block-diagram integration (module reference, address map, clocks, synchronous resets) through synthesis, implementation, and bitstream generation, with idempotent Tcl, robust run-status verdicts, and archived utilization/timing evidence. Use when integrating RTL into a block design and generating a bitstream without hand-driving the GUI. Batch simulation belongs to a sim-specific skill instead.
---

# Vivado BD integration -> bitstream (batch, project-independent)

Every rule below was learned from a real bring-up (Zynq-7020, Vivado
2025.2, PS GP0 -> AXI Interconnect -> RTL module reference), including
the failures. Flow:

```
GUI Vivado process                  <- environment source for the batch runner
  └─ batch runner (or vivado -mode batch -source ...)
       ├─ stage 1  bd_integrate.tcl    (idempotent: BD cells/wiring/address)
       └─ stage 2  synth_bit.tcl       (synth -> impl -> write_bitstream + reports)
```

## 1. GUI process as the environment source

If the batch runner derives the Vivado environment from a live GUI
process (recommended: one canonical environment, no per-shell
settings drift):

- A dead GUI PID fails BEFORE anything runs (`OpenProcess failed`,
  exit 1, project untouched). Relaunch the GUI and retry the same Tcl.
- Vivado 2025.2 install layout gotchas:
  - `<root>\bin\vivado.exe` DOES NOT EXIST. The GUI entry is
    `<root>\bin\vivado.bat` (internally chains vvgl.exe). Launching
    the nonexistent exe pops a desktop error dialog.
  - `<root>\bin\unwrapped\win64.o\vivado.exe` is the BATCH executable;
    do not hand-launch it as a GUI (a shell-started process also lacks
    the settings environment).
  - Correct relaunch, so the GUI process environment carries the
    install vars the runner reads out of its PEB:

    ```
    cmd /c "call <root>\settings64.bat && start "" /D <root>\bin <root>\bin\vivado.bat <proj>.xpr"
    ```
- Poll up to ~3 min for a vivado process with a NON-EMPTY
  MainWindowTitle before taking the PID (windowless boot processes
  exist earlier). If the install root is unknown, read `vivado` from
  any prior run's `process_status.json`.

## 2. Stage 1 — BD integration Tcl (idempotent by construction)

A BD script is iterated against a SAVED design (every successful pass
persists), so idempotence is not optional:

- Guard every creation: `get_bd_cells -quiet <name>`, and pin wiring
  via helper procs (`get_bd_nets -quiet -of [get_bd_pins ..]`,
  `get_bd_intf_nets -quiet -of [get_bd_intf_pins ..]`).
- Rewiring = `delete_bd_objs [get_bd_nets -of [get_bd_pins <pin>]]`
  then connect again. Never assume a fresh BD.
- **Module reference**: `create_bd_cell -type module -reference <top>`
  requires a plain Verilog-2001 top (.v). SystemVerilog submodules and
  packages in the same fileset follow automatically via
  `update_compile_order`.
- **PS7**: enable `PCW_USE_M_AXI_GP0`, `PCW_EN_CLK0_PORT`,
  `PCW_EN_RST0_PORT`. `PCW_FCLK0_PERIPHERAL_FREQMHZ` is a DYNAMIC
  parameter (absent until enabled elsewhere) — probe with `catch`;
  PS7 default FCLK0 is 100 MHz.
- **axi_interconnect**: set NUM_SI/NUM_MI and wire ALL of ACLK,
  S00_ACLK, M00_ACLK (BD 41-758 per unwired clock), plus the PS-side
  `M_AXI_GP0_ACLK`.
- **Address map**: `assign_bd_address`, then set `range`/`offset` on
  the MASTER-side mirrored segment
  (`processing_system7_0/Data/SEG_<cell>_<block>`). The slave-side
  segment's offset/range is read-only ("Cannot change read-only
  property 'offset'").
- **Resets — never wire FCLK_RESET0_N directly to peripheral resets.**
  Direct wiring raises BD 41-1348 CRITICAL (asynchronous release =
  recovery risk). Canonical architecture, proc_sys_reset + xlconstant:
  - `FCLK_RESET0_N -> rst/ext_reset_in` only;
  - `C_EXT_RESET_HIGH` is READ-ONLY and auto-propagated from the
    connected pin's polarity (a manual set raises BD 41-737, benign —
    but VERIFY the resolved value in the cell XCI: look for
    `"C_EXT_RESET_HIGH": value 0, "value_src": "propagated"` with an
    active-low source);
  - `dcm_locked` MUST be tied to a constant 1 (xlconstant). Undriven,
    synthesis reads 0 and the board sits in PERMANENT RESET while the
    BD still validates and simulates fine — a silent killer;
  - `aux_reset_in` may stay unconnected (undriven 0 + default
    active-high = inactive);
  - `peripheral_aresetn -> every ARESETN/aresetn sink`;
  - `FCLK_CLK0 -> rst/slowest_sync_clk`.
- End the script with `validate_bd_design` -> `save_bd_design` ->
  `set_property top <bd>_wrapper [get_filesets sources_1]` ->
  `update_compile_order` -> `close_project`, then print the final PASS
  marker your runner requires. A clean run without the marker is
  recorded as FAIL by any marker-based runner.

**Verify the saved BD without another Vivado cycle**: `.bd` files are
readable JSON — grep `nets` / `interface_nets` / `addressing` for the
intended topology; resolved cell parameters live in the XCI under the
BD's `ip/` directory (`"value_src": "propagated"` vs `"user"`).

## 3. Stage 2 — synth / impl / bitstream Tcl

- Guard `make_wrapper -files [get_files <bd>.bd] -top -import` with
  `get_files -quiet <bd>_wrapper.v`; `generate_target all` is quick
  when current. Reassert `top`, `update_compile_order`.
- Launch: `reset_run` ONLY what is stale, then
  `launch_runs impl_1 -to_step write_bitstream -jobs 8`.
- **Run-state verdict — the field trap (cost one false FAIL):**
  after completion, `STATUS` is e.g. `write_bitstream Complete!` while
  `PROGRESS` is `100%`. "Complete" is NOT in PROGRESS. Accept success
  only as: STATUS matches `*omplete*` AND PROGRESS == `100%`. Treat
  STATUS matching error/aborted as failure.
- **wait_on_run can return against a stale terminal state** (reported
  "finished" ~3 s after launch while the real run had not started).
  Do not trust a single wait_on_run verdict: poll in a bounded loop
  (`after 10000`, check PROGRESS transitions / NEEDS_REFRESH), and
  cross-check artifacts on disk (`<runs>/synth_1/__synthesis_is_complete__`,
  `<runs>/impl_1/*.dcp`, the `.bit`) before declaring PASS.
- **Detached child jobs survive the parent's exit.** If the parent
  script exits early (buggy verdict, timeout kill), the already-spawned
  synth jobs keep running and can COMPLETE after the failure. Before
  relaunching, check run dirs for fresh artifacts and reuse them
  (skip `reset_run synth_1` when `__synthesis_is_complete__` and the
  dcp are newer than the last BD edit) — a blind full reset throws
  away finished work.
- Reports: `open_run impl_1` -> `report_utilization`,
  `report_timing_summary` `-file` into the EVIDENCE directory (not the
  project tree); print WNS/WHS into the console log. Bitstream lands
  at `<proj>.runs/impl_1/<top>.bit`.
- Sizing: PS7 + interconnect + one CSR module ~10-20 min wall clock
  with 8 jobs. The batch parent spawning several extra vivado
  processes is normal (the parallel jobs), not a runaway.

## 4. Evidence discipline

- A runner that rewrites `vivado_console.log` / `result.json` /
  `process_status.json` per invocation requires SNAPSHOT COPIES before
  each rerun in the same run directory
  (`vivado_console_<phase>_runN.log` etc.), or earlier rounds' evidence
  is destroyed.
- Typical marker-based verdicts: exit 0 AND a `RESULT PASS` marker AND
  no line matching `Fatal:` / `RESULT FAIL` / `\bERROR:`. Benign
  CRITICAL WARNINGs usually do NOT fail such runners — but any
  `ERROR:` token anywhere in echoed output does. Keep success-path
  `puts` free of that word.
- **Never write the failure-marker literal in Tcl source.** Batch
  vivado ECHOES every script line (comments included) into the console
  log, so an unexecuted `puts "... RESULT FAIL"` branch still matches
  the runner's FAIL regex and converts a genuinely successful run into
  a recorded FAIL (cost one false FAIL on a completed bitstream). Emit
  failure markers through a proc that builds the string in pieces:
  `set m "... FA"; append m "IL"` — the full token then exists only in
  runtime output.
- **Stale XDC noise**: old projects accumulate constraint files from
  earlier tops (LED/UART pin XDCs etc.). Against a new top every
  `get_ports` is empty, constraints are inert, but each raises
  `'set_property' expects at least one object` CRITICAL — tens of
  criticals that are all harmless for THIS top. Confirm inertness
  (0 errors, only empty-object criticals), document it, and scope or
  retire the stale XDCs when convenient; do not panic-redesign.

## 5. After the bit

1. Verify the bit is non-empty, reports archived, WNS/WHS >= 0.
2. Board download follows the board's established overlay workflow.
3. Level-1 smoke: from Linux on the PS, `/dev/mem` read of the mapped
   base must return the design's ID magic — before any driver work.
