param(
    [string]$VivadoBin = 'F:\vivado2025\2025.2\Vivado\bin',
    [string]$RunTag = 'ble_fsm_refactor_xsim'
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rtlRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..\rtl'))
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..\..\..'))
$dateStamp = Get-Date -Format 'yyyy-MM-dd'
$evidenceRoot = Join-Path $projectRoot '4_metrics\logs'
$runNumber = 1
do {
    $runName = '{0}_{1}_run{2:D2}' -f $dateStamp, $RunTag, $runNumber
    $workDir = Join-Path $evidenceRoot $runName
    $runNumber = $runNumber + 1
} while (Test-Path -LiteralPath $workDir)

New-Item -ItemType Directory -Path $workDir | Out-Null

$rtlFiles = @(
    (Join-Path $rtlRoot 'uart_tx.v'),
    (Join-Path $rtlRoot 'uart_rx.v'),
    (Join-Path $rtlRoot 'ble_at_test_ctrl.v'),
    (Join-Path $rtlRoot 'ble_test_top.v'),
    (Join-Path $scriptDir 'tb_ble_test_top.v')
)

Push-Location $workDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') --log xvlog.log @rtlFiles
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE"
    }

    & (Join-Path $VivadoBin 'xelab.bat') tb_ble_test_top `
        -s tb_ble_snapshot --debug typical --log xelab.log
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed with exit code $LASTEXITCODE"
    }

    & (Join-Path $VivadoBin 'xsim.bat') tb_ble_snapshot `
        --runall --log xsim.log
    if ($LASTEXITCODE -ne 0) {
        throw "xsim failed with exit code $LASTEXITCODE"
    }

    $simulationLog = Get-Content -LiteralPath (Join-Path $workDir 'xsim.log') -Raw
    if ($simulationLog -notmatch 'BLE_RTL_SIM_PASS') {
        throw 'Simulation completed without BLE_RTL_SIM_PASS'
    }

    Write-Host "BLE_RTL_SIM_PASS work_dir=$workDir"
} finally {
    Pop-Location
}
