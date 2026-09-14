---
name: mineru-doc-reader
description: Mandatory MinerU-based content parsing for PDFs, scanned document images, DOCX, PPTX, XLSX, and similar reference files in E:\competition. Use before summarization, QA, extraction, comparison, or technical interpretation of document contents; reuse only a complete MinerU result with a matching input SHA-256.
---

# E:\competition MinerU Document Reader

Use the local MinerU pipeline whenever document contents must be read or interpreted in this workspace. This project-specific skill overrides generic document-reading shortcuts.

## Mandatory Trigger

Invoke this skill before content-level work on:

- PDF manuals, datasheets, papers, reports, specifications, and scanned PDFs.
- Images whose primary purpose is to carry document text, tables, schematics, or scanned pages.
- DOCX, PPTX, XLSX, XLS, and other office/reference documents supported by MinerU.
- Batch document extraction, summarization, QA, comparison, evidence collection, or register-table interpretation.

Do not require MinerU for metadata-only work such as listing files, calculating hashes, renaming, or copying without reading content. If the user explicitly forbids MinerU, state that this conflicts with the project default and follow the current user instruction.

Before launching or reusing MinerU, tell the user briefly that MinerU is being used and where its evidence will be stored.

## Project Paths

- Workspace: `E:\competition`
- Active skill: `E:\competition\.codex\skills\mineru-doc-reader`
- Reusable copy: `E:\competition\6_skill\mineru-doc-reader`
- Raw output: `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN`
- Daily record: `E:\competition\7_logs\YYYY-MM-DD\03_validation_summary.md`
- Frozen FPGA baseline: `E:\competition\2_fpga` (read-only unless the current user explicitly authorizes a change)

Never put MinerU output, API files, working copies, extracted images, layout PDFs, or temporary files in `2_fpga`, the repository root, `1_docs`, or a generic log directory. Final authored documents may be delivered to `1_docs`; raw parsing evidence remains under `4_metrics/logs`.

## Local Runtime

- MinerU: `D:\work\conda\miniconda3\envs\mineru\Scripts\mineru.exe`
- MinerU API: `D:\work\conda\miniconda3\envs\mineru\Scripts\mineru-api.exe`
- Backend: `pipeline`
- Model source: `local`
- Config: `C:\Users\Administrator\mineru.json`

Do not use `hybrid-engine` by default. This host previously reported `Can not find $env:CUDA_PATH`; hybrid execution is a separate setup task.

## Evidence Reuse

A prior result may be reused only when all conditions are true:

1. The input SHA-256 matches the hash recorded in the prior run.
2. Markdown and `*_content_list.json` both exist.
3. The prior marker is `MINERU_PARSE_PASS`.
4. The requested pages or content are present and readable.
5. The reuse is disclosed to the user and linked from the current validation summary.

Otherwise create a new run directory and invoke MinerU. Never reuse results based only on filename.

## Required Workflow

1. Apply `project-workspace-policy` and `daily-engineering-log`.
2. Resolve the exact input files and compute SHA-256 hashes.
3. Select a fresh run path matching `YYYY-MM-DD_<task>_runNN`.
4. Announce MinerU invocation and the evidence path.
5. Run the project-local wrapper.
6. Validate the result marker, Markdown, content JSON, image count, and console/API logs.
7. For Chinese content, inspect the quality-check result and use `content_list.json` when it is preferred.
8. Use the extracted Markdown/JSON as the primary semantic source. Inspect layout/span PDFs or page images when tables, formulas, figures, or OCR order matter.
9. Report input hashes, success/failure, preferred source, output paths, and any fallback.
10. Link the run directory from the current daily validation summary.

## Commands

Single file:

```powershell
powershell -ExecutionPolicy Bypass -File E:\competition\.codex\skills\mineru-doc-reader\scripts\run_mineru_pipeline.ps1 `
  -InputPath "E:\competition\1_docs\example.pdf" `
  -OutputDir "E:\competition\4_metrics\logs\YYYY-MM-DD_example_mineru_run01"
```

Batch:

```powershell
powershell -ExecutionPolicy Bypass -File E:\competition\.codex\skills\mineru-doc-reader\scripts\run_mineru_pipeline.ps1 `
  -InputDir "E:\competition\1_docs" `
  -Patterns "01*.pdf,02*.pdf,*.docx" `
  -OutputDir "E:\competition\4_metrics\logs\YYYY-MM-DD_document_batch_run01"
```

Use broad numeric patterns such as `02*.pdf` rather than assuming an underscore separator.

## Validation Contract

A clean parse requires:

- `mineru_result_marker.txt` contains `MINERU_PARSE_PASS`.
- `input_manifest.json` records every input path and SHA-256.
- `mineru_results.json` records exit code, output paths, fallback, image count, and quality status.
- Markdown and `*_content_list.json` exist for every input.
- `mineru_runner_console.txt`, `mineru_api_stdout.txt`, and `mineru_api_stderr.txt` are retained.
- Extracted content begins plausibly and relevant tables/figures are not silently omitted.

For Chinese content, run the bundled checker. A `review` result is not a clean text-quality PASS; disclose the issue and manually inspect the relevant Markdown, JSON, and rendered evidence.

## Failure Handling

- `502 Bad Gateway`: the wrapper clears proxy variables and uses `NO_PROXY=127.0.0.1,localhost`.
- `CUDA_PATH` failure: remain on `pipeline`; do not silently switch to hybrid.
- Long-name `_origin.pdf` failure: the wrapper retries through a short working copy inside the same evidence run and records `Fallback=true`.
- Port or API startup failure: keep API logs, write `MINERU_PARSE_FAIL`, and select a fresh run or explicit alternate port for a retry.
- One failed batch item does not erase successful outputs, but the overall marker remains FAIL until every requested input satisfies the contract.

Do not silently replace MinerU with ad hoc PDF text extraction. If MinerU cannot complete, report the failure and evidence boundary; any emergency secondary extraction must be explicitly labeled as a fallback and must not be presented as a MinerU result.

## Session Close

Run:

```powershell
powershell -ExecutionPolicy Bypass -File E:\competition\4_metrics\scripts\audit_project_skill_paths.ps1
```

The task is incomplete if raw MinerU artifacts are outside `4_metrics/logs`, the daily validation summary lacks the evidence link, or a semantic document conclusion was made without invoking or validly reusing MinerU.
