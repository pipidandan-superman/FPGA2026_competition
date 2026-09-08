# Project Instructions

Engineering logs in this repository must be written only to `7_logs/YYYY-MM-DD/`. Do not create or update `2_log/`, `log/`, or generic `logs/` for engineering-session records. The project-local override at `.codex/skills/daily-engineering-log/SKILL.md` is mandatory whenever this skill is used.

Raw evidence remains under `4_metrics/logs/<run-name>/` and must be linked from `7_logs/YYYY-MM-DD/03_validation_summary.md`.

For every engineering, FPGA, simulation, organization, or documentation skill in this workspace, `.codex/skills/project-workspace-policy/SKILL.md` is mandatory. Treat `2_fpga/` as the frozen board-proven project unless the current user instruction explicitly authorizes a change.

## Mandatory MinerU Document Parsing

For content-level reading, extraction, summarization, comparison, QA, or technical interpretation of PDFs, scanned document images, DOCX, PPTX, XLSX, XLS, and similar reference files, invoke `.codex/skills/mineru-doc-reader/SKILL.md` and use the local MinerU `pipeline` backend before drawing semantic conclusions.

Before launching MinerU, tell the user that MinerU is being used and identify the `4_metrics/logs/YYYY-MM-DD_<task>_runNN` evidence directory. After parsing, report the result marker, input SHA-256, Markdown/content-JSON paths, and any quality warning or fallback.

A previous MinerU result may be reused only when its input SHA-256 matches, its result marker is `MINERU_PARSE_PASS`, and its required Markdown and content JSON are complete. Disclose reuse to the user and link the evidence from `7_logs/YYYY-MM-DD/03_validation_summary.md`.

Do not use ad hoc PDF text extraction as the primary parser, do not infer document content from filenames or code comments, and do not silently substitute another parser after a MinerU failure. Metadata-only operations such as listing, hashing, renaming, or copying files do not require MinerU because they do not interpret document content. A current explicit user instruction not to use MinerU overrides this project default.

## Edit Tool Discipline

This workspace currently exposes one file-edit tool: `apply_patch`. It accepts a freeform patch; there are no separate callable tools named `apply_patch_batch`, `apply_patch_replace_file`, `apply_patch_update_file`, `apply_patch_add_file`, or `apply_patch_delete_file`.

For an existing file, use an in-place `*** Update File` hunk. For a new file, use one `*** Add File` operation. Do not use `*** Delete File` followed by `*** Add File` for the same path to simulate editing or replacement.

Use one file target per `apply_patch` call. If multiple files need changes, issue separate calls. Never pass JSON, an `operations` wrapper, or a redundant `raw_patch` field to the freeform tool.

If a patch is rejected, read the current file once, correct the hunk context, and issue one new `*** Update File` or `*** Add File` call. Do not repeat the rejected patch shape or enter a retry loop.
