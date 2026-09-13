param(
    [Parameter(Mandatory=$true)][string]$RunDirectory,
    [string]$SimulationRun = 'E:\competition\4_metrics\logs\2026-09-12_axilt_reg_sim_run02'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$projectDir=[IO.Path]::GetFullPath($PSScriptRoot)
$expected='E:\competition\2_fpga\2_axi_lite_test\proj'
if($projectDir -ne $expected){throw 'Unexpected project directory'}
$xpr=Join-Path $projectDir 'AXI_LITE_test.xpr'
if(Test-Path -LiteralPath $xpr){throw 'Project already exists. Preserve it; use a reviewed rebuild procedure.'}
$run=[IO.Path]::GetFullPath($RunDirectory)
if(-not $run.StartsWith('E:\competition\4_metrics\logs\',[StringComparison]::OrdinalIgnoreCase)){
    throw 'Invalid evidence directory'
}
if(Test-Path -LiteralPath $run){throw 'Evidence run already exists'}
$simStatus=Get-Content -LiteralPath (Join-Path $SimulationRun 'process_status.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($simStatus.state -ne 'PASS'){throw 'Simulation gate not passed'}
$simLog=Get-Content -LiteralPath (Join-Path $SimulationRun 'vivado_console.log') -Raw -Encoding UTF8
if($simLog -notmatch '(?m)^AXILT_REG_SIM_PASS ' -or $simLog -notmatch '(?m)^AXILT_DELAYED_BACKEND_PASS'){
    throw 'Required simulation markers absent'
}
$rtlHashes=@(Get-ChildItem -LiteralPath (Join-Path $root 'rtl') -Filter '*.v' | ForEach-Object {
    $hash=(Get-FileHash -LiteralPath $_.FullName).Hash
    $passed=Join-Path $SimulationRun ('source\rtl\'+$_.Name)
    if($hash -ne (Get-FileHash -LiteralPath $passed).Hash){throw "RTL differs from simulated source: $($_.Name)"}
    [pscustomobject]@{path=$_.FullName;sha256=$hash}
})
New-Item -ItemType Directory -Path $run | Out-Null
$sourceSnapshot=Join-Path $run 'source'
New-Item -ItemType Directory -Path $sourceSnapshot | Out-Null
foreach($folder in @('rtl','sim','pynq','doc')){
    Copy-Item -LiteralPath (Join-Path $root $folder) -Destination (Join-Path $sourceSnapshot $folder) -Recurse
}
New-Item -ItemType Directory -Path (Join-Path $sourceSnapshot 'proj') | Out-Null
Get-ChildItem -LiteralPath $projectDir -File | Where-Object Extension -in @('.tcl','.ps1','.py','.md') |
    Copy-Item -Destination (Join-Path $sourceSnapshot 'proj')
$rtlHashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'rtl_simulation_gate.json') -Encoding UTF8
$boardBd='E:\competition\2_fpga\0_diaplay_test\proj\display_test_zynq7020_school\display_test_zynq7020_school.srcs\sources_1\bd\display_test\display_test.bd'
Copy-Item -LiteralPath $boardBd -Destination (Join-Path $run 'baseline.bd')
@($boardBd,'E:\competition\2_fpga\0_diaplay_test\pynq\overlay.bit',
  'E:\competition\2_fpga\0_diaplay_test\pynq\overlay.hwh') | ForEach-Object {
    [pscustomobject]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'baseline_hashes.json') -Encoding UTF8
& python -B (Join-Path $sourceSnapshot 'proj\export_ps_config.py') (Join-Path $run 'baseline.bd') (Join-Path $run 'ps_config.tcl')
if($LASTEXITCODE -ne 0){throw 'PS config export failed'}
$unixRun=$run.Replace('\','/')
$unixRoot=$root.Replace('\','/')
$unixProj=$projectDir.Replace('\','/')
@(
    "set run_dir {$unixRun}",
    "set source_dir {$unixRun/source}",
    "set project_name {AXI_LITE_test}",
    "set design_name {AXI_LITE_test}",
    "set artifact_stem {AXI_LITE_test}",
    "set project_dir {$unixProj}",
    "set rtl_source_dir {$unixRoot/rtl}",
    "set sim_source_dir {$unixRoot/sim}",
    "source {$unixRun/source/proj/build.tcl}"
) | Set-Content -LiteralPath (Join-Path $run 'run.tcl') -Encoding ASCII
& 'E:\competition\4_metrics\scripts\run_vivado_standalone_ees.ps1' -VivadoBat 'F:\vivado2025\2025.2\Vivado\bin\vivado.bat' -TclFile (Join-Path $run 'run.tcl') -RunDirectory $run -TimeoutSeconds 1800
$logArchive=Join-Path $run 'project_run_logs'
New-Item -ItemType Directory -Path $logArchive | Out-Null
$runsRoot=Join-Path $projectDir 'AXI_LITE_test.runs'
if(Test-Path -LiteralPath $runsRoot){
    Get-ChildItem -LiteralPath $runsRoot -Directory | ForEach-Object {
        $dest=Join-Path $logArchive $_.Name
        New-Item -ItemType Directory -Path $dest | Out-Null
        Get-ChildItem -LiteralPath $_.FullName -File | Where-Object Extension -in @('.log','.rpt','.tcl','.sh','.bat') |
            Copy-Item -Destination $dest
    }
}
$status=Get-Content -LiteralPath (Join-Path $run 'process_status.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($status.state -ne 'PASS'){throw "Build failed; preserve $run and $xpr"}
& python -B (Join-Path $sourceSnapshot 'proj\verify_release.py') $run --artifact-stem AXI_LITE_test --design-name AXI_LITE_test
if($LASTEXITCODE -ne 0){throw 'Release audit failed'}
foreach($item in $rtlHashes){
    if($item.sha256 -ne (Get-FileHash -LiteralPath $item.path).Hash){throw 'RTL changed during build'}
}
$publish=Join-Path $projectDir 'release'
if(Test-Path -LiteralPath $publish){throw 'Release already exists; do not overwrite'}
Copy-Item -LiteralPath (Join-Path $run 'release') -Destination $publish -Recurse
[pscustomobject]@{marker='AXI_LITE_TEST_LOCAL_PROJECT_PASS';project=$xpr;
    bd=(Join-Path $projectDir 'AXI_LITE_test.srcs\sources_1\bd\AXI_LITE_test\AXI_LITE_test.bd');
    evidence=$run;release=$publish;board_tested=$false} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'local_project_receipt.json') -Encoding UTF8

