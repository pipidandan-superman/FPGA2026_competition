# Copyright 2026 LSL
#
# Run this script from E:\competition after approving Git write access.
# It stages only the frozen HDMI fix, focused evidence, skills, and logs.

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$workspace = 'E:\competition'
Set-Location -LiteralPath $workspace

if (Test-Path -LiteralPath (Join-Path $workspace '.git\index.lock')) {
    throw '.git/index.lock exists. Close the other Git process before running.'
}

$paths = @(
    '.gitignore',
    'AGENTS.md',
    'HANDOFF.md',
    '1_docs/EES-331_HDMI*.md',
    '1_docs/ADV7511_Hardware_Users_Guide/README.md',
    '1_docs/ADV7511_Hardware_Users_Guide/REGISTER_NOTES.md',
    '1_docs/ADV7511_Hardware_Users_Guide/REGISTER_INIT_TABLE.csv',
    '2_fpga/0_diaplay_test/rtl/hdmi_new',
    '2_fpga/0_diaplay_test/rtl/iic/iic_protocal.v',
    '2_fpga/0_diaplay_test/sim',
    '6_skill/README.md',
    '6_skill/SKILL_REVIEW_PENDING.md',
    '6_skill/modelsim-local-sim',
    '6_skill/modelsim-gui-sim',
    '6_skill/vita-vivado-batch-sim',
    '4_metrics/scripts/upload_2026_09_06_hdmi_pass.ps1',
    '4_metrics/logs/2026-09-06_adv7511_physical_swap_board_pass_run01',
    '4_metrics/logs/2026-09-06_adv7511_csc601_rebuild_run01',
    '4_metrics/logs/2026-09-06_adv7511_rgb_style3_fix_run01',
    '4_metrics/logs/2026-09-06_adv7511_table_module_run01',
    '4_metrics/logs/2026-09-06_adv7511_config_rewrite_run01',
    '4_metrics/logs/2026-09-06_adv7511_pkg_external_ref_run01',
    '4_metrics/logs/2026-09-06_hdmi_ila_no_display_run01',
    '4_metrics/logs/2026-09-06_hdmi_style1_mode_tb_run01',
    '4_metrics/logs/2026-09-06_workspace_cleanup_run01/root_cleanup_manifest.md',
    '7_logs/README.md',
    '7_logs/2026-09-05',
    '7_logs/2026-09-06'
)

git add -- @paths
if ($LASTEXITCODE -ne 0) { throw "git add failed with exit code $LASTEXITCODE" }
git diff --cached --stat
if ($LASTEXITCODE -ne 0) { throw "git diff --cached --check failed with exit code $LASTEXITCODE" }
git diff --cached --stat
if ($LASTEXITCODE -ne 0) { throw "git diff --cached --stat failed with exit code $LASTEXITCODE" }
git diff --cached --check -- .gitignore AGENTS.md HANDOFF.md 1_docs 6_skill
if ($LASTEXITCODE -ne 0) { throw "git diff --cached --check failed with exit code $LASTEXITCODE" }
git commit -m 'fix: freeze EES-331 ADV7511 HDMI byte-swap path'
if ($LASTEXITCODE -ne 0) { throw "git commit failed with exit code $LASTEXITCODE" }
git push origin main
if ($LASTEXITCODE -ne 0) { throw "git push failed with exit code $LASTEXITCODE" }
