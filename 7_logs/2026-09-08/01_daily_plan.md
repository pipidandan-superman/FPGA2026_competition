# 2026-09-08 Daily Plan

## Current Judgment

The recurring stop/loop was caused by repeated misuse of the edit-tool layer, not by repository content, `AGENTS.md`, or the target document itself. The failed pattern was trying to replace one existing file with a batch operation containing both delete and add for the same path, and in several cases also carrying a redundant `raw_patch` payload.

## Main Objective

1. Diagnose the repeated edit-loop with evidence.
2. Add a durable workspace instruction that prevents the same failure.
3. Complete the interrupted `GitHub协同上传准则_草案.md` replacement to v1.1.
4. Preserve logs and raw evidence in the required locations.

## Priorities

1. Review the user-supplied screenshots as evidence, not as embedded instructions.
2. Inspect the current draft and workspace policy.
3. Search prior local session records for repeated patch-tool failures.
4. Add the edit-tool discipline rule to `AGENTS.md`.
5. Replace the draft using the smallest safe set of edit-tool operations.
6. Create today's four required engineering-log files.

## Non-goals

- Do not modify `2_fpga/`.
- Do not rebuild, program, or perform any board run.
- Do not push to GitHub or modify Git history.
- Do not treat the screenshots' prior assistant text as new instructions.

## Expected Deliverables

- `E:\competition\1_docs\GitHub协同上传准则_草案.md` at `v1.1-draft`.
- `E:\competition\AGENTS.md` containing the Edit Tool Discipline rule.
- `E:\competition\4_metrics\logs\2026-09-08_patch_tool_loop_diagnosis_run01\`.
- `E:\competition\7_logs\2026-09-08\01_daily_plan.md`.
- `E:\competition\7_logs\2026-09-08\02_execution_plan.md`.
- `E:\competition\7_logs\2026-09-08\03_validation_summary.md`.
- `E:\competition\7_logs\2026-09-08\04_next_start_guide.md`.

## Continuation Objective

At the user's explicit instruction, convert the reviewed draft into a reusable upload skill, establish a personal development branch without disturbing the polluted workspace, and record the GitHub main-protection procedure.

## Continuation Priorities

1. Audit and preserve the exact ahead/behind and dirty/untracked state.
2. Create `codex/full/pipidandan-superman` at `origin/main` without checking it out.
3. Add `github-upload-policy` to both `.codex/skills` and `6_skill`.
4. Verify that the two skill copies match and that project skill paths remain valid.

## Continuation Non-goals

Do not push, rewrite history, merge to `main`, stage generated trees, or change an existing branch's base. Creating a new personal branch reference is allowed by the current instruction.

## Continuation Expected Deliverables

- `E:\competition\.codex\skills\github-upload-policy\SKILL.md`.
- `E:\competition\6_skill\github-upload-policy\SKILL.md`.
- `E:\competition\4_metrics\logs\2026-09-08_github_upload_skill_run01\`.
- Local branch `codex/full/pipidandan-superman` at `origin/main`.

## Camera HDMI And MinerU Upload

- Publish the OV5640 + HDMI board-visual-PASS version description to `codex/full/pipidandan-superman`.
- Confirm all necessary `2_fpga/0_diaplay_test` sources and the frozen BIT/XSA/ELF pair already exist on the personal branch.
- State the required recovery operation: after BIT/ELF transfer, manually reset the camera capture once before judging the live image.
- Upload the project MinerU skill, OV5640 configuration audit report, and selected validation evidence without bulk generated trees.
