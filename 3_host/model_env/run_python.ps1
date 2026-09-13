param([Parameter(ValueFromRemainingArguments=$true)][string[]]$PythonArgs)
$ErrorActionPreference = 'Stop'
$baseline = 'E:/competition/4_metrics/logs/2026-09-12_model_env_run01'
$python = "$baseline/venv/Scripts/python.exe"
if (-not (Test-Path -LiteralPath $python)) { throw 'Model environment missing; follow model_env/README.md to rebuild.' }
$env:YOLO_CONFIG_DIR = "$baseline/ultralytics_config"
$env:MPLCONFIGDIR = "$baseline/matplotlib_config"
New-Item -ItemType Directory -Force -Path $env:YOLO_CONFIG_DIR,$env:MPLCONFIGDIR | Out-Null
$env:YOLO_AUTOINSTALL = 'false'
$env:YOLO_OFFLINE = 'true'
$env:PYTHONNOUSERSITE = '1'
$env:PYTHONDONTWRITEBYTECODE = '1'
& $python @PythonArgs
exit $LASTEXITCODE
