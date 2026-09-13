param(
    [Parameter(Mandatory=$true)][string]$EvidenceDir,
    [string]$BasePython = 'C:/Users/Administrator/AppData/Local/Programs/Python/Python312/python.exe',
    [string]$Wheelhouse = 'E:/competition/4_metrics/logs/2026-09-12_model_env_run01/wheelhouse'
)
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($EvidenceDir)
$allowedRoot = 'E:\competition\4_metrics\logs\'
if (-not $target.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'EvidenceDir must be under E:/competition/4_metrics/logs/' }
if (Test-Path -LiteralPath $target) { throw 'Use a new run directory; existing environments are never overwritten.' }
$version = & $BasePython -c "import platform; print(platform.python_version()+' '+platform.machine())"
if ($LASTEXITCODE -ne 0 -or $version -ne '3.12.10 AMD64') { throw "Required Python 3.12.10 AMD64; got $version" }
$lock = Join-Path $PSScriptRoot 'requirements-win-py312-cpu.lock'
if (-not (Test-Path -LiteralPath $lock)) { throw 'Missing frozen lock' }
if (-not (Test-Path -LiteralPath $Wheelhouse)) { throw 'Missing wheelhouse; restore baseline archive first' }
New-Item -ItemType Directory -Path $target | Out-Null
New-Item -ItemType Directory -Path "$target/tmp" | Out-Null
$env:TEMP = "$target/tmp"
$env:TMP = "$target/tmp"
$env:PIP_CONFIG_FILE = 'NUL'
$env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
Start-Transcript -Path "$target/rebuild_console.txt" | Out-Null
try {
    & $BasePython -m venv "$target/venv"
    if ($LASTEXITCODE -ne 0) { throw 'venv creation failed' }
    $venvPython = "$target/venv/Scripts/python.exe"
    & $venvPython -m pip --isolated install --no-index --no-cache-dir --find-links $Wheelhouse --require-hashes --only-binary=:all: -r $lock --report "$target/install_report.json"
    if ($LASTEXITCODE -ne 0) { throw 'Offline locked install failed' }
    & $venvPython -m pip check
    if ($LASTEXITCODE -ne 0) { throw 'pip check failed' }
    & $venvPython "$PSScriptRoot/verify_environment.py" --output "$target/environment_check.json"
    if ($LASTEXITCODE -ne 0) { throw 'Environment smoke check failed' }
    Write-Output 'OFFLINE_ENV_REBUILD_PASS'
} finally {
    Stop-Transcript | Out-Null
}
