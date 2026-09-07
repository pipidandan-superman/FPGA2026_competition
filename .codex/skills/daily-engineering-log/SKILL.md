---
name: daily-engineering-log
description: Project-enforced engineering log workflow for E:\competition. Use at the start and continuation of every engineering, FPGA, hardware, research, or project session. The only valid log root is E:\competition\7_logs.
---

# Project Daily Engineering Log

## Mandatory Root

For this project, the only valid engineering-log root is:

```text
E:\competition\7_logs
```

The daily record path must be exactly:

```text
E:\competition\7_logs\YYYY-MM-DD
```

`2_log`, `log`, `logs`, and any other log root are forbidden for new records. Do not create them. If a session discovers records in `2_log`, treat that path as retired, migrate the dated folders into `7_logs`, preserve all existing content, verify the destination, and remove only the now-empty retired root.

Do not use the global default `2_log` rule for this workspace. This project override takes precedence.

## Required Files

Every daily folder must contain exactly these four working files:

```text
01_daily_plan.md
02_execution_plan.md
03_validation_summary.md
04_next_start_guide.md
```

If the folder or files already exist, read them first and update them without deleting useful content. Use dated run folders under `4_metrics/logs` or another project-approved evidence root for raw build, simulation, board, UART, ILA, scope, and screenshot artifacts. Summarize and link those artifacts from `03_validation_summary.md`; do not replace raw evidence with only a conclusion.

## Required Content

`01_daily_plan.md` must record current judgment, main objective, prioritized tasks, explicit non-goals, and expected deliverables.

`02_execution_plan.md` must record the ordered execution strategy, relevant modules or tools, likely files, risks, and fallback.

`03_validation_summary.md` must record already verified facts, current verification targets, exact PASS/FAIL criteria, commands, board runs, captured evidence, and final results. Preserve complete raw terminal, Vivado, simulation, ILA, UART, and screenshot evidence in a dedicated run folder.

`04_next_start_guide.md` must record the first file or action for the next session, forbidden immediate actions, success criteria, and any blocker plus its smallest useful next step.

## Workflow

1. Resolve the workspace root as `E:\competition`.
2. Resolve the destination as `E:\competition\7_logs\YYYY-MM-DD` before writing.
3. If the destination is not exactly that path, stop and correct it.
4. Read `7_logs\README.md`, the latest existing dated folder, and the current dated files when present.
5. Create or update the four required files.
6. Keep current facts separate from recommendations and mark assumptions explicitly.
7. When continuing the same day, append or revise the files and keep the next-session handoff current.

## Validation

Before ending a session that uses this skill, verify:

```powershell
Test-Path 'E:\competition\7_logs\YYYY-MM-DD\01_daily_plan.md'
Test-Path 'E:\competition\7_logs\YYYY-MM-DD\02_execution_plan.md'
Test-Path 'E:\competition\7_logs\YYYY-MM-DD\03_validation_summary.md'
Test-Path 'E:\competition\7_logs\YYYY-MM-DD\04_next_start_guide.md'
```

All four results must be `True`. The session handoff is incomplete if any file is missing or still points new work to a forbidden log root.
