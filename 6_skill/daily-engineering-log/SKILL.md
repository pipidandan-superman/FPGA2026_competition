---
name: daily-engineering-log
description: Create and maintain a dated daily engineering log folder under this project's canonical 7_logs directory for coding, hardware, research, or project work. Use at the start of every engineering/project session, when continuing a workspace, when the user asks for today's plan, execution plan, validation summary, next-start guide, daily log, development log, or asks to organize work under 7_logs/YYYY-MM-DD with plan, execution, verification, and handoff files.
---

# Daily Engineering Log

> This is a project-local copy. Edit this file for competition-specific prompts and paths; do not modify the global Skill installation.

## Core Rule

At the start of each engineering project session, create or update a daily folder under this project's canonical `7_logs` directory:

```text
<workspace>/7_logs/YYYY-MM-DD/
```

Do not create or update `<workspace>/log/`. If a legacy `log/`, `1_log/`, or `2_log/` directory exists, read it, merge its records into the matching `7_logs/YYYY-MM-DD/` folders with explicit source attribution, verify the imported content, then retire the legacy directory only after the merge is complete.

### Path Enforcement

For this competition workspace, the only valid engineering-log root is `C:\Users\Administrator\Desktop\competition\7_logs`. Treat `1_log/`, `2_log/`, and `log/` as retired legacy locations: never create them, never place new records there, and never use them as a fallback. Before writing a daily record, resolve the destination and require that it is exactly `<workspace>/7_logs/YYYY-MM-DD/`; if it is not, stop and correct the path before creating any file.

## Merged ViTA log-management rules

The following project rules are merged from `D:\VitA\12_skills\log-management\SKILL.md` and adapted for this workspace:

- This Skill owns only dated `7_logs/YYYY-MM-DD/` plans, execution records, validation summaries, evidence indexes, and next-start guidance. It does not update a long-term progress board or an external handoff file, and it does not trigger global synchronization.
- Complete build, simulation, synthesis, board, UART, and console output belongs in `4_metrics/logs/` (or a dedicated run directory referenced from there). The dated log stores the run ID, summary, result boundary, and evidence path rather than copying large raw output.
- Every validation result is `pending` unless the raw evidence and coverage boundary are present. Exit code zero alone is not a functional PASS.
- Existing dated folders are updated incrementally. Historical records are preserved and are not rewritten merely to cosmetically change old paths.

Keep four Markdown files in that folder:

```text
01_daily_plan.md
02_execution_plan.md
03_validation_summary.md
04_next_start_guide.md
```

If the folder or files already exist, read them first and update them instead of replacing useful content. Preserve merged legacy records in clearly labelled archival files or sections; do not present historical instructions as current execution instructions.

## Workflow

1. Identify the workspace root from the current working directory or project context.
2. Create `<workspace>/7_logs/YYYY-MM-DD/` using the current local date.
3. Read existing project context before writing:
   - top-level README or project notes, if present
   - existing task checklist, if present
   - previous `7_logs/` project log or latest dated log folder, if present
   - yesterday's or latest dated log folder, if present
4. Create or update the four daily files.
5. Keep the content practical and specific to the current project state.
6. In the final response, link to the daily folder and summarize the immediate next action.

## File Contents

### `01_daily_plan.md`

Include:

- Current project judgment.
- Today's main objective.
- Prioritized task list.
- Explicit non-goals for today.
- Expected deliverables.

### `02_execution_plan.md`

Include:

- Step-by-step execution strategy.
- Responsibility split between modules, tools, or subsystems.
- Recommended order of implementation.
- Key files likely to be edited or inspected.
- Risk points and fallback path.

### `03_validation_summary.md`

Include:

- What has already been verified before today.
- What needs verification today.
- Exact pass/fail criteria.
- Commands, board runs, simulations, screenshots, UART logs, CSVs, or other evidence to capture.
- Requirement that every validation run preserve the complete raw terminal, UART, build, simulation, or console printout in that run's record folder.
- A placeholder for final results if validation has not run yet.

### `04_next_start_guide.md`

Include:

- Files to read first next time.
- The first concrete action to take next time.
- What not to do immediately.
- Success criteria for the next session.
- If there is a blocker, state the blocker and the smallest useful next step.

## Updating Existing Logs

When continuing work during the same day:

- Append or revise the daily files to reflect new facts.
- Keep completed verification evidence in `03_validation_summary.md`.
- For each compile, simulation, board run, or hardware validation, save the full raw printout to a dedicated artifact such as `uart_terminal.txt`, `console_output.txt`, or `build_log.txt`; summaries may quote key lines, but must not replace the complete raw log.
- Keep the next-session handoff current in `04_next_start_guide.md`.
- Do not duplicate stale plans if the project direction changed.

When a user asks for a daily plan but a dated folder already exists:

- Prefer updating that folder.
- Mention that the existing folder was reused.

## Style

- Be concrete rather than motivational.
- Separate current facts from recommendations.
- Mark assumptions clearly.
- Keep the plan scoped to what can be acted on in the current project.
- Prefer checklists and short sections.
