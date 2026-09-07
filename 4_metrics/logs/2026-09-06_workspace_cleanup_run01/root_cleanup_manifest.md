# 2026-09-06 workspace cleanup manifest

## Scope and protection

This cleanup moved only transient files and generated libraries from
`E:\competition` into `root_quarantine/`. `E:\competition\2_fpga` was not
moved, rewritten, renamed, or deleted.

The first move batch stopped safely because its protective prefix check also
matched `2_fpga (2).zip`; no protected directory was selected. A second exact
path batch moved both archive ZIP files.

## Moved items

- Generated ModelSim libraries: `.hbs`, `adv_fix_sim_lib`,
  `adv_input_style_sim_lib`, `cfg_rewrite_lib02`, `cfg_yuv422_lib`,
  `mode_style1_lib`, `rgb_style3_lib`, `rgb_style3_mismatch_lib`,
  `rgb_style3_mode_lib`, `table_module_lib`, `table_module_lib_mismatch`,
  `table_module_mode_lib`.
- Temporary diagnostics: `.Xil`, `tmp`.
- Root snapshots/backups: `2_fpga.zip`, `2_fpga (2).zip`.
- Root transient evidence/notes: `clockInfo.txt`, `dfx_runtime.txt`,
  `ees_bus_zoom.png`, `ees_bus_zoom_400.png`, `ees_p31.png`, `ees_p32.png`,
  `ees_p33.png`, `transcript`, `vsim.wlf`.

## Skill reference copies

Copied unchanged from `C:/Users/Administrator/.codex/skills` to `6_skill/`:

- `modelsim-local-sim/`
- `modelsim-gui-sim/`
- `vita-vivado-batch-sim/`

The Vivado skill remains a ViTA-specific reference and requires project
adaptation before direct use.
