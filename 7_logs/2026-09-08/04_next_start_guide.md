# 2026-09-08 Next Start Guide

## First Action

Read the new `## Edit Tool Discipline` section in `E:\competition\AGENTS.md` before performing another manual file edit.

## Durable Edit Rule

1. For one existing file whose whole content changes, use the dedicated single-file replacement tool exactly once.
2. Do not use a batch operation that contains delete and add for the same path.
3. Do not pass a redundant `raw_patch` field.
4. Use targeted structured updates for partial edits.
5. Use batch operations only for independent paths.
6. If an edit tool rejects an operation, stop and choose a distinct recovery path; do not repeat the failed call.

## Current Next Step

The draft `E:\competition\1_docs\GitHub协同上传准则_草案.md` is ready for human review at `v1.1-draft`. The user should answer the ten review questions at the end of the document before the policy becomes executable.

## Forbidden Immediate Actions

- Do not push to GitHub.
- Do not modify `2_fpga/`.
- Do not create branch protection or the upload-policy skill until both members approve the draft.
- Do not convert this documentation PASS into a board or build PASS.
- Do not repeat a failed batch edit on the same target path.

## Success Criteria for Follow-up

After review approval, create the upload-policy skill, branch-protection instructions, and the upload-discipline audit script only in separate controlled steps with their own evidence and validation.

## Patch Tool Loop Follow-up

First read `E:\competition\4_metrics\logs\2026-09-08_patch_tool_runtime_fix_run01\TOOL_RUNTIME_FIX_EVIDENCE.md`. The current environment exposes one freeform file-edit tool named `apply_patch`; the other apply-patch tool names in older notes are not callable tools.

For an existing file, use one `*** Update File` patch. For a new file, use one `*** Add File` patch. Use separate `apply_patch` calls for separate files. Do not use same-path `*** Delete File` plus `*** Add File` for ordinary editing. If a patch is rejected, reread the file once, correct the context, and make one new attempt only.

## 2026-09-08 Continuation Boundary

The local branch and skill-copy checks are complete. The next action requiring user or environment support is a fresh remote audit: resolve the `.git/FETCH_HEAD` permission failure, then run `git fetch --prune origin` and compare the branch again. Do not infer remote freshness from the local `c6ddb70` observation.

## Updated Next Action After Successful Fetch

Remote freshness and the clean worktree are now confirmed. Continue only inside `E:\competition_worktrees\FPGA2026_competition\pipidandan-superman`. Select one coherent upload topic, compare each source file against the clean worktree, and copy only explicitly reviewed files. Do not use `git add .` or mirror the polluted workspace.

## Camera HDMI Release Start Procedure

Use the frozen files recorded in `2_fpga/0_diaplay_test/doc/camera_hdmi_correct_version_2026-09-08.md`. Program the frozen BIT, load the paired ELF, then manually reset the camera capture once. Judge the live camera image only after this reset.

Do not rebuild or mix BIT/XSA/ELF files when reproducing the existing `BOARD_VISUAL_PASS`. A new build or changed source requires a separate evidence run and cannot inherit the frozen board result.
