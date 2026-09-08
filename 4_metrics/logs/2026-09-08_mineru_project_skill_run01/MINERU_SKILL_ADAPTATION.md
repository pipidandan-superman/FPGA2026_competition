# MinerU Project Skill Adaptation Evidence

Date: 2026-09-08

## Objective

Copy the global `mineru-doc-reader` skill into `E:\competition`, adapt it to the project path and evidence policy, and make MinerU mandatory for content-level parsing of PDFs, scanned document images, and supported Office reference files.

## Source And Destinations

- Global source: `C:\Users\Administrator\.codex\skills\mineru-doc-reader`
- Active project skill: `E:\competition\.codex\skills\mineru-doc-reader`
- Reusable project copy: `E:\competition\6_skill\mineru-doc-reader`
- Raw MinerU evidence root: `E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN`
- Engineering log root: `E:\competition\7_logs\YYYY-MM-DD`
- Frozen FPGA project: `E:\competition\2_fpga` (read-only for this task)

The source `__pycache__` directory was not copied. No `__pycache__` directory remains in either project copy.

## Project Adaptations

1. `AGENTS.md` now requires MinerU before semantic reading, extraction, summarization, comparison, QA, or technical interpretation of PDFs, scanned document images, DOCX, PPTX, XLSX, XLS, and similar reference files.
2. Metadata-only operations such as listing, hashing, renaming, and copying remain exempt because they do not interpret document contents.
3. Every launch or valid reuse must be disclosed to the user with the evidence directory.
4. Reuse requires a matching input SHA-256, `MINERU_PARSE_PASS`, Markdown, and `*_content_list.json`.
5. The project wrapper forces the `pipeline` backend and local model source, keeps working/API output inside the evidence run, clears proxy variables for localhost, and records the input manifest, result JSON, runner log, API logs, command logs, and PASS/FAIL marker.
6. The wrapper rejects outputs outside `E:\competition\4_metrics\logs` and rejects run names that do not match `YYYY-MM-DD_<task>_runNN`.
7. Long-path fallback copies only into the current evidence run and restricts fallback cleanup to that run.
8. Final authored reports may be delivered to `1_docs`; raw MinerU products may not be written there or into `2_fpga`.

## Skill Validation

- MinerU version: `3.4.4`
- Validation Python: `D:\work\conda\miniconda3\envs\mineru\python.exe`
- PyYAML version in validation environment: `6.0.3`
- Active `quick_validate.py`: PASS
- Reusable-copy `quick_validate.py`: PASS
- PowerShell parser errors for `run_mineru_pipeline.ps1`: `0`
- Python checker compilation: PASS
- Project skill path audit: PASS (`pass=true`, `failures=[]`, `skill_count=12`)

## Active And Reusable Copy Hashes

Each listed hash is identical between the active and reusable project copies.

| File | SHA-256 | Bytes |
|---|---|---:|
| `SKILL.md` | `4DB705286EA134415B30E4636209F885A5C6B91274972D79BB6D81BB4048C591` | 6482 |
| `agents/openai.yaml` | `2EE1B1903BBD7D483576DDDF1066979BB3BA998F53EE383C20DB5095EFA8F50F` | 265 |
| `scripts/check_mineru_chinese_quality.py` | `79F6D0AFC9404775AFD99100185A4C7D03C5458B7FAE014444C28CB4C714B8EC` | 5155 |
| `scripts/run_mineru_pipeline.ps1` | `8CC90F8D18B8E814766D2224C4547C757044FD62549CAB7AA1540995D3D04003` | 14865 |

## Real MinerU Smoke Test

- Evidence: `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01`
- Input: `E:\competition\1_docs\ADV7511_Hardware_Users_Guide\ADV7511_Datasheet_analog.com.pdf`
- Input size: `89974` bytes
- Input SHA-256: `61567DD86F99BC996FBF981BAD4540782643021F0720079D5793948C2F71D6D9`
- Backend: `pipeline`
- Model source: `local`
- Result marker: `MINERU_PARSE_PASS`
- Exit code: `0`
- Runtime: `25.2` seconds
- Markdown: present
- Content JSON: present
- Extracted images: `1`
- Long-path fallback: not used
- Preferred source: Markdown
- Chinese quality result: `review` with `low_chinese_ratio,short_text`; this is expected for the short English smoke-test PDF and is not represented as a Chinese OCR quality PASS.

Key generated files:

- `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01\mineru_result_marker.txt`
- `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01\input_manifest.json`
- `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01\mineru_results.json`
- `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01\mineru_runner_console.txt`
- `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01\mineru_api_stdout.txt`
- `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01\mineru_api_stderr.txt`
- `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01\ADV7511_Datasheet_analog.com\auto\ADV7511_Datasheet_analog.com.md`
- `E:\competition\4_metrics\logs\2026-09-08_mineru_project_skill_smoke_run01\ADV7511_Datasheet_analog.com\auto\ADV7511_Datasheet_analog.com_content_list.json`

## Evidence Boundary

The real smoke test proves the project wrapper can launch the local MinerU API, parse one PDF, retain the required artifacts, and satisfy the project evidence contract. It does not prove parsing quality for every PDF, scanned image, DOCX, PPTX, XLSX, or XLS file. Each future content-level document task must invoke MinerU or validly reuse a hash-matched PASS run and must report any quality warning or fallback.

No file under `E:\competition\2_fpga` was intentionally modified by this task. Existing unrelated dirty or untracked files in the workspace were not changed.

## Result

`MINERU_PROJECT_SKILL_ADAPTATION_PASS`
