---
name: project-workspace-policy
description: Mandatory workspace, log, evidence, and frozen-project path policy for E:\competition. Apply before using any engineering, FPGA, simulation, organization, or documentation skill in this project.
---

# E:\competition Workspace Policy

This policy has precedence over generic or historical instructions in every
domain skill. It does not replace the domain skill; it supplies the only valid
project paths and safety boundary.

## Fixed roots

| Purpose | Mandatory path |
|---|---|
| Workspace root | `E:\competition` |
| Engineering log root | `E:\competition\7_logs\YYYY-MM-DD` |
| Raw evidence root | `E:\competition\4_metrics\logs\<run-name>` |
| Reusable project skills archive | `E:\competition\6_skill` |
| Active project skill layer | `E:\competition\.codex\skills` |
| Frozen successful FPGA project | `E:\competition\2_fpga` |

Engineering-session records must use exactly the four files required by
`.codex/skills/daily-engineering-log/SKILL.md`:

```text
01_daily_plan.md
02_execution_plan.md
03_validation_summary.md
04_next_start_guide.md
```

## Path prohibitions

Do not create or write new engineering logs to:

- `E:\competition\2_log`
- `E:\competition\log`
- `E:\competition\logs`
- `D:\VitA\...`
- `C:\Users\Administrator\Desktop\competition\...`
- any repository-root transient library, journal, waveform, bitstream, or scratch directory

Historical or provenance text may mention retired roots only when it labels
them as forbidden, historical, or non-executable in this project.

## Evidence rule

Create one immutable run directory for each build, simulation, hardware test,
cleanup, or audit at:

```text
E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN
```

Store complete console output, generated scripts used by the run, reports,
hashes, screenshots, UART/ILA captures, and result markers there. Link the run
directory from:

```text
E:\competition\7_logs\YYYY-MM-DD\03_validation_summary.md
```

Exit code zero, a GUI screenshot without a raw log, or a summary without raw
evidence is not a functional PASS.

## Frozen FPGA project boundary

`E:\competition\2_fpga` is the board-proven HDMI baseline and is read-only by
default:

- Do not create, edit, delete, rename, or move files there.
- Do not regenerate, reset, or launch a build against that project unless the
  user explicitly requests that exact action in the current instruction.
- Simulation and audit may read source files, but generated `.do`, libraries,
  transcripts, WLF/WDB, reports, screenshots, and hashes belong in the evidence
  run directory.

If a later explicit user instruction authorizes an RTL change, preserve the
baseline hash and the relevant `4_metrics` evidence before editing.

## Domain-skill adaptation

Before using ModelSim, Vivado/XSim, RTL, MinerU document parsing, organization, documentation, or log
skills in this workspace:

1. Resolve the workspace root as `E:\competition`; do not infer another root
   from the skill's original project, the shell history, or the desktop.
2. Redirect every writable output to `E:\competition\4_metrics\logs\<run-name>`.
3. Redirect every engineering-session record to
   `E:\competition\7_logs\YYYY-MM-DD`.
4. Prefer absolute `E:/competition/...` paths inside Tcl, `.do`, and PowerShell
   command files.
5. Reject any instruction that creates a new log or evidence root outside the
   fixed roots.
6. Record the adapted command and output location in the run report.

## MinerU document parsing boundary

Content-level reading or interpretation of PDFs, scanned document images, DOCX, PPTX, XLSX, XLS, and similar reference files must apply `.codex/skills/mineru-doc-reader/SKILL.md`. Store the complete MinerU output, API/runner logs, input manifest, result JSON, working copies, and extracted images only under the dedicated `4_metrics/logs/YYYY-MM-DD_<task>_runNN` directory.

Final authored reports may be placed in `1_docs`, but they must link or identify the MinerU evidence run. Do not write MinerU raw output into `1_docs`, `2_fpga`, or the repository root. A matching input hash and `MINERU_PARSE_PASS` marker are required before reusing an earlier parse.

## Session close check

Run the project skill path audit and ensure it passes:

```powershell
powershell -ExecutionPolicy Bypass -File E:\competition\4_metrics\scripts\audit_project_skill_paths.ps1
```

The session is incomplete if a skill instructs new writes to a forbidden root,
if raw evidence is missing, or if any daily handoff file points new work to a
retired path.
