param(
    [Parameter(Mandatory=$true)][ValidateSet('smoke','sim','build')][string]$Mode,
    [Parameter(Mandatory=$true)][int]$GuiPid,
    [ValidateSet('gui','standalone')][string]$Backend = 'gui',
    [Parameter(Mandatory=$true)][string]$RunDirectory
)
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
$run = [IO.Path]::GetFullPath($RunDirectory)
if (-not $run.StartsWith('E:\competition\4_metrics\logs\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Evidence directory must be under E:\competition\4_metrics\logs'
}
if (Test-Path -LiteralPath $run) { throw "Run already exists: $run" }
New-Item -ItemType Directory -Path $run | Out-Null
Copy-Item -LiteralPath $sourceRoot -Destination (Join-Path $run 'source') -Recurse
$baselinePaths = @(
    'E:\competition\2_fpga\0_diaplay_test\pynq\overlay.bit',
    'E:\competition\2_fpga\0_diaplay_test\pynq\overlay.hwh'
)
$baselinePaths | ForEach-Object {
    [pscustomobject]@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'baseline_hashes.json') -Encoding UTF8
$unixRun = $run.Replace('\','/')
$entry = if ($Mode -eq 'build') {'build.tcl'} else {'simulate.tcl'}
@(
    "set run_dir {$unixRun}",
    "set source_dir {$unixRun/source}",
    "set run_mode {$Mode}",
    "source {$unixRun/source/proj/$entry}"
) | Set-Content -LiteralPath (Join-Path $run 'run.tcl') -Encoding ASCII
$timeout = if ($Mode -eq 'build') {1800} else {600}
if ($Mode -eq 'build') {
    $boardBd = 'E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.srcs\sources_1\bd\display_test\display_test.bd'
    Copy-Item -LiteralPath $boardBd -Destination (Join-Path $run 'baseline.bd')
    & python (Join-Path $run 'source\proj\export_ps_config.py') (Join-Path $run 'baseline.bd') (Join-Path $run 'ps_config.tcl')
    if ($LASTEXITCODE -ne 0) { throw 'PS config export failed' }
}
if ($Backend -eq 'gui') {
    & 'E:\competition\4_metrics\scripts\run_vivado_batch_ees.ps1' -GuiPid $GuiPid -TclFile (Join-Path $run 'run.tcl') -RunDirectory $run -TimeoutSeconds $timeout
} else {
    & 'E:\competition\4_metrics\scripts\run_vivado_standalone_ees.ps1' -VivadoBat 'F:\vivado2025\2025.2\Vivado\bin\vivado.bat' -TclFile (Join-Path $run 'run.tcl') -RunDirectory $run -TimeoutSeconds $timeout
}
$status = Get-Content -LiteralPath (Join-Path $run 'process_status.json') -Raw | ConvertFrom-Json
# XSim creates a small WDB even with signal logging disabled; retain console
# evidence only. Delete only generated WDB files resolved inside this run.
Get-ChildItem -LiteralPath (Join-Path $run 'vivado') -Filter '*.wdb' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $wavePath = [IO.Path]::GetFullPath($_.FullName)
    if (-not $wavePath.StartsWith($run + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid WDB path' }
    Remove-Item -LiteralPath $wavePath
}
if ($status.state -ne 'PASS') { throw "Vivado $Mode failed. Preserve $run." }
if ($Mode -eq 'build') {
    & python -B (Join-Path $run 'source\proj\verify_release.py') $run
    if ($LASTEXITCODE -ne 0) { throw 'Release identity audit failed' }
}
