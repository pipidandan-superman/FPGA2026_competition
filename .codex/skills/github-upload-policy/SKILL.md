---
name: github-upload-policy
description: Reusable Git/GitHub upload, branch, recovery, and main-protection workflow for E:\competition. Apply whenever staging, committing, pushing, opening a PR, recovering a polluted local workspace, or changing branch policy in this repository.
---

# GitHub Upload Policy

## Scope And Status

- Repository: `pipidandan-superman/FPGA2026_competition`.
- Source root: `E:\competition`.
- Active skill: `.codex/skills/github-upload-policy/SKILL.md`.
- Reusable copy: `6_skill/github-upload-policy/SKILL.md`.
- Status: `ACTIVE_FOR_LOCAL_USE; MAIN_PROTECTION_USER_REPORTED; MEMBER_MAPPING_CONFIRMED`.
- Member mapping confirmed by the user on 2026-09-08: `pipidandan-superman = member-a`; `xiaokaiyuan = member-b`.
- This skill enforces safe local Git discipline immediately. GitHub-side protection becomes organizationally binding only after the repository owner enables branch protection and both members confirm the branch mapping.

This skill does not authorize edits to the frozen `2_fpga` baseline, creation of forbidden log roots, force pushes, history rewrites, or direct pushes to `main`.

## Non-Negotiable Rules

1. `main` is the protected integration branch. Never push to it directly.
2. Every change entering `main` requires a pull request and review by the other member.
3. Never use `git add .` or `git add -A` in this repository. Add named files only.
4. Never force-push, delete a shared remote branch, or rewrite pushed history.
5. Long-term member branches may be pushed by their owner without review, but merging them into `main` still requires a PR.
6. Engineering logs are written only to `7_logs/YYYY-MM-DD/`; raw run evidence is written only to `4_metrics/logs/<run-name>/`.
7. Do not upload Vivado/Vitis generated trees, caches, waveforms, scratch workspaces, or bulk logs by default. Evidence must be explicitly selected and declared in the PR.
8. Large binaries require a written reason, source, SHA-256, size, and evidence link before staging.
9. A build, simulation, visual observation, or board observation is not full acceptance unless the declared acceptance criterion has passed.
10. If local state is unclear, stop and audit before staging or switching branches.

## Branch Model

Use one long-term full development branch per member:

```text
codex/full/<member-slug>
```

The current known Git identity is `pipidandan-superman`; unless the team chooses another alias, use:

```text
codex/full/pipidandan-superman
```

Use a temporary branch only for a risky experiment:

```text
codex/tmp/YYYY-MM-DD-short-topic
```

Do not use personal paths such as `dev`, `my-branch`, `test`, or a teammate's long-term branch.

## Session Preflight

Run from the repository root before any upload decision:

```powershell
git status --short --branch
git branch --show-current
git remote -v
git fetch --prune origin
git rev-list --left-right --count HEAD...origin/main
git log --oneline --decorate --graph --all -20
```

Classify local state before acting:

- `0 4` means the local branch has no local commits and is four commits behind `origin/main`.
- `2 0` means the branch is ahead by two local commits.
- `2 4` means committed histories have diverged and a merge is required.
- Dirty lines in `git status` are uncommitted working-tree state, not commits.
- `??` files are untracked; Git has no history for them and they must not be bulk-added.

To determine whether a dirty tracked file already equals the remote version:

```powershell
git diff --quiet origin/main -- <path>
if ($LASTEXITCODE -eq 0) { 'SAME_AS_ORIGIN_MAIN' } else { 'DIFFERENT_FROM_ORIGIN_MAIN' }
```

If a file is already identical to `origin/main`, do not copy or commit the local snapshot again.

## Clean Local Workspace Flow

Use this flow only when `git status` is clean or contains only changes you intend to keep.

```powershell
$branch = 'codex/full/pipidandan-superman'

git switch main
git pull --ff-only

git show-ref --verify --quiet "refs/heads/$branch"
if ($LASTEXITCODE -eq 1) {
  git switch -c $branch origin/main
} elseif ($LASTEXITCODE -eq 0) {
  git switch $branch
  git pull --ff-only
  git merge origin/main
} else {
  throw "git show-ref failed with exit code $LASTEXITCODE"
}
```

Stage and commit by topic:

```powershell
git add -- path/one.md path/two.c
git diff --cached --name-status
git diff --cached --check
git diff --cached --stat
git commit -m "docs: add focused topic"
```

Push the personal branch:

```powershell
git push -u origin codex/full/pipidandan-superman
```

Open a PR from `codex/full/pipidandan-superman` to `main`. Do not merge without the other member's approval.

## Polluted Local Workspace Recovery

Use this flow when the workspace has many uncommitted changes, untracked build trees, or files that may already exist on `origin/main`.

### Step 1: Preserve Facts

Create one evidence run and save the complete audit, not conclusions:

```powershell
$run = 'E:\competition\4_metrics\logs\YYYY-MM-DD_git_local_audit_runNN'
New-Item -ItemType Directory -Force -Path $run | Out-Null

git status --short --branch           > "$run/git_status.txt"
git branch -avv                       > "$run/git_branches.txt"
git rev-list --left-right --count HEAD...origin/main > "$run/ahead_behind_count.txt"
git diff --name-status                > "$run/tracked_worktree_changes.txt"
git diff --cached --name-status       > "$run/staged_changes.txt"
git ls-files -o --exclude-standard    > "$run/untracked_paths.txt"
```

Never delete, overwrite, clean, reset, or stash the polluted workspace just to make the status look clean.

### Step 2: Create A Personal Branch Without Checking It Out

This preserves the dirty workspace while placing the new branch at the latest shared baseline:

```powershell
git fetch --prune origin

$branch = 'codex/full/pipidandan-superman'
git show-ref --verify --quiet "refs/heads/$branch"
if ($LASTEXITCODE -eq 1) {
  git branch $branch origin/main
} elseif ($LASTEXITCODE -eq 0) {
  Write-Host "Branch already exists; merge origin/main later instead of resetting it."
} else {
  throw "git show-ref failed with exit code $LASTEXITCODE"
}
```

### Step 3: Use A Separate Clean Worktree

A worktree lets you edit from `origin/main` while leaving the polluted original workspace untouched:

```powershell
$branch = 'codex/full/pipidandan-superman'
$tree   = 'E:\competition_worktrees\FPGA2026_competition\pipidandan-superman'

git worktree add $tree $branch
cd $tree
git status --short --branch
```

This path is a working checkout, not a log or evidence root. Do not put waveforms, UART captures, Vivado outputs, or daily logs there.

### Step 4: Select Files Explicitly

For each candidate in the original dirty workspace, compare before copying:

```powershell
$old = 'E:\competition\1_docs\candidate.md'
$new = 'E:\competition_worktrees\FPGA2026_competition\pipidandan-superman\1_docs\candidate.md'
git diff --no-index -- $old $new
```

Only after review:

```powershell
Copy-Item -LiteralPath $old -Destination $new
git add -- 1_docs/candidate.md
```

For an untracked source directory, list and inspect its files first:

```powershell
git -C E:\competition ls-files -o --exclude-standard -- 2_fpga/0_diaplay_test/rtl/data_pre
```

Copy the reviewed source files one by one or with an explicit reviewed list. Do not mirror a directory into the clean worktree.

### Step 5: Keep The Baseline Intact

When `origin/main` already contains a teammate-verified file, start from that version. Do not replace it with an older local copy unless the PR states the reason and includes evidence.

Do not stage these by default:

- Vivado/Vitis `_ide`, `.cache`, `.gen`, `.runs`, `.sim`, `.hw`, `xsim.dir`, transient SDK/platform trees.
- Waveforms, journals, transcripts, libraries, temporary build workspaces.
- Entire `4_metrics/logs` run directories; select the report, raw terminal log, result marker, and declared screenshots needed by the PR.
- Raw screenshots or large binaries under `7_logs`; new evidence belongs under `4_metrics/logs`.
- The frozen `2_fpga` baseline unless the user explicitly authorized that exact change in the current instruction.

### Step 6: Commit, Sync, Push

```powershell
git diff --cached --name-status
git diff --cached --check
git diff --cached --stat
git commit -m "docs: add reviewed changes"

git fetch --prune origin
git merge origin/main

git push -u origin codex/full/pipidandan-superman
```

If the merge conflicts, keep both sides' facts, dates, hashes, result boundaries, and evidence links. Never resolve a conflict by silently deleting teammate evidence.

## Pull Request Requirements

A PR must declare:

1. Why the change is needed.
2. Exact scope and paths.
3. What was verified and what was not.
4. PASS/FAIL boundary, especially separating compile, simulation, implementation, board visual, UART, and full acceptance.
5. Evidence paths under `4_metrics/logs/...`.
6. Whether frozen BIT/XSA/ELF/source was touched.
7. Known limitations and rollback method.

Recommended title prefixes:

```text
feat: short capability
fix: short defect
docs: short documentation change
evidence: short evidence archive
freeze: short frozen-baseline change
```

Add `[FREEZE]` to the title when frozen artifacts or board-proven source are affected.

A reviewer must reject a PR that:

- lacks the other member's approval;
- contains unexpected generated files;
- writes logs to `2_log`, `log`, `logs`, or another forbidden root;
- claims PASS without raw evidence;
- overwrites frozen artifacts without explicit authorization and hashes;
- rewrites history or bypasses protection;
- deletes teammate evidence or known limitations;
- cannot explain its own scope.

## Main Branch Protection

The repository owner should enable this in GitHub:

1. Open the repository page.
2. Select **Settings**.
3. Select **Rules** and then **Rulesets**, or use the older **Branches -> Branch protection rules** UI.
4. Create or edit a branch ruleset for `main`.
5. Set enforcement to active.
6. Require a pull request before merging.
7. Require at least one approval from another member.
8. Dismiss stale approvals when new commits are pushed.
9. Require conversation resolution before merge.
10. Require status checks only after real checks exist; do not block on a nonexistent check name.
11. Block force pushes.
12. Block branch deletion.
13. Include administrators so protection cannot be bypassed casually.
14. Save and test by attempting a direct `main` push; it must fail.

If no CI exists yet, rely on the reviewer and the local staged-file audit. Add required status checks later after a real workflow has produced a stable check name.

## Divergence And Emergency Handling

If a member's branch is behind:

```powershell
git switch codex/full/pipidandan-superman
git pull --ff-only
git merge origin/main
```

If histories diverged, merge. Do not reset or force-push.

If sensitive material, an oversized artifact, or a wrong commit was pushed to a personal branch, stop and coordinate before changing history. If it reached `main`, treat it as an incident: preserve the commit hash, remove the material in a new reviewed PR if license permits, rotate exposed credentials, and record the incident in the daily log.

## Validation Before Ending

Record and retain:

```powershell
git status --short --branch
git diff --cached --name-status
git log -1 --oneline --decorate
```

A successful upload means the personal branch exists remotely, the PR targets `main`, the reviewer can see the declared scope, and raw evidence is linked. A pushed branch alone is not `main` acceptance.
