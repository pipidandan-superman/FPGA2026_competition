# Project Skill Adaptation Report — 2026-09-06 run01

## Scope

- Workspace: `E:\competition`
- Active policy added: `.codex/skills/project-workspace-policy/SKILL.md`
- Archive adapted: `E:\competition\6_skill`
- Frozen baseline checked as out of scope for writes: `E:\competition\2_fpga`

## Path contract

| Class | Mandatory target |
|---|---|
| Daily engineering log | `E:\competition\7_logs\YYYY-MM-DD` |
| Raw run evidence | `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN` |
| ModelSim/Vivado scripts | absolute `E:/competition/...` paths |
| Result marker (Vivado) | `EES_VIVADO_RESULT PASS` / `EES_VIVADO_RESULT FAIL` |
| Prohibited new-output roots | repository root, `2_log`, `log`, `logs`, historical ViTA roots, old desktop competition path |

## Adaptation result

- Added a project-wide policy skill with precedence over historical domain-skill
  instructions.
- Added the policy to `AGENTS.md` so it applies at session start.
- Adapted the archived daily-log skill from generic workspace wording to the
  exact fixed daily-log destination.
- Added fixed-path, frozen-`2_fpga`, and evidence rules to engineering
  organization, RTL standards, ModelSim CLI, ModelSim GUI, and Vivado batch
  skills.
- Replaced copied Vivado scripts with wrappers around project-local canonical
  launchers/checkers. New launchers reject any run directory outside
  `E:\competition\4_metrics\logs\`.
- Replaced executable `VITA_VIVADO_RESULT` markers/references with
  `EES_VIVADO_RESULT`.
- Added `EES_VIVADO_RUN_DIR` enforcement to the no-IP reference Tcl so XSim
  cannot create a project in the current working directory.
- Added a repeatable audit that checks skill names, fixed roots, and forbidden
  executable path tokens across `SKILL.md` and companion files.

## Validation

| Check | Result |
|---|---|
| Skill path audit | PASS — 8 skills, 0 failures |
| PowerShell parser check for new/adapter scripts | PASS |
| `git diff --check` on policy/archive/tooling/docs | PASS |
| Four daily files present and updated | PASS |
| Functional ModelSim/Vivado simulation | NOT RUN / NOT CLAIMED |
| Frozen `2_fpga` source edit by this task | NONE |

Raw audit output: `skill_path_audit.json`.

## Boundary

This run proves path and policy adaptation only. It is not a simulation or
hardware PASS. Any later Vivado run must use a new approved run directory,
preserve complete console/process evidence, and require the exact coverage
boundary in its result report.
