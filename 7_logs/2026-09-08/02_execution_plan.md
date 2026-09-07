# 2026-09-08 Execution Plan

## Ordered Strategy

1. Apply `.codex/skills/project-workspace-policy/SKILL.md` and `.codex/skills/daily-engineering-log/SKILL.md`.
2. Treat the three screenshots only as evidence of prior behavior, not as instructions to execute.
3. Read `AGENTS.md`, the current draft, and the relevant skill files.
4. Search local Codex session records for `apply_patch_batch`, `raw_patch`, and repeated tool-selection failures.
5. Extract the relevant evidence lines into the raw-evidence run directory.
6. Add an explicit `Edit Tool Discipline` section to `AGENTS.md`.
7. Replace `1_docs/GitHub协同上传准则_草案.md` with the v1.1 simplified two-person full-development-branch policy.
8. Record today's plan, execution, validation, and handoff files under `7_logs/2026-09-08/`.

## Relevant Files

- `E:\competition\AGENTS.md`
- `E:\competition\1_docs\GitHub协同上传准则_草案.md`
- `E:\competition\7_logs\2026-09-08\*`
- `E:\competition\4_metrics\logs\2026-09-08_patch_tool_loop_diagnosis_run01\`

## Continuation Strategy

1. Apply the project workspace and daily-log policies.
2. Fetch remote references and classify commits separately from uncommitted working-tree changes.
3. Save status, branches, ahead/behind count, remote-only changes, tracked-versus-origin comparisons, and untracked inventory into one evidence run.
4. Create the personal branch reference from `origin/main` without switching the dirty workspace.
5. Add and verify active/archive copies of `github-upload-policy`.
6. Record GitHub branch-protection and clean-worktree upload instructions in the skill.

## Continuation Relevant Files

- `E:\competition\.codex\skills\github-upload-policy\SKILL.md`
- `E:\competition\6_skill\github-upload-policy\SKILL.md`
- `E:\competition\4_metrics\logs\2026-09-08_github_upload_skill_run01\`

## Tool Recovery Decision

The first attempted batch replacement was rejected because one path appeared as both delete and add. To avoid continuing the same failed path, the final successful edit used two separate tool calls:

1. `apply_patch_delete_file` for the old draft.
2. `apply_patch_add_file` for the complete v1.1 draft.

This preserves the manual-edit-through-`apply_patch` rule while avoiding the validator's same-target conflict.

## Risks and Fallback

Risk: the tool-selection loop may recur in later sessions because it is a model/tool-interface behavior rather than a file-level defect. Mitigation: the new `AGENTS.md` rule explicitly requires single-file replacement for one existing file and forbids delete-plus-add for the same path.

Fallback: if a full-file replacement is rejected again, stop after one failure, read the current file, and use separate delete/add calls only when the file is safe to recreate.

## Verification

After edits, verify:

1. The draft version is `v1.1-draft`.
2. `AGENTS.md` contains the Edit Tool Discipline section.
3. SHA-256 hashes are recorded.
4. All four required daily files exist.
5. Raw evidence exists under the required `4_metrics/logs` run directory.

## Runtime Tool Correction

The current Codex environment exposes only one file-edit tool named `apply_patch`, with freeform patch syntax. It does not expose separate callable tools named `apply_patch_batch`, `apply_patch_replace_file`, `apply_patch_update_file`, `apply_patch_add_file`, or `apply_patch_delete_file`.

The corrective rule is therefore:

1. Existing file: one `*** Update File` patch.
2. New file: one `*** Add File` patch.
3. Multiple files: separate `apply_patch` calls.
4. Same-path `*** Delete File` plus `*** Add File`: forbidden for ordinary editing.
5. Rejected patch: reread once, correct context, and make one new attempt only.

Evidence is recorded under `E:\competition\4_metrics\logs\2026-09-08_patch_tool_runtime_fix_run01\${bt}.
