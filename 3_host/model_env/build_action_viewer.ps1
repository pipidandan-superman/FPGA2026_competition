param([Parameter(Mandatory=$true)][string]$BuildRun)
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($BuildRun)
if (-not $target.StartsWith('E:\competition\4_metrics\logs\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'BuildRun must be under evidence root'
}
if (Test-Path -LiteralPath $target) {throw 'Use a new build run'}
$python = 'E:/competition/4_metrics/logs/2026-09-12_gesture_viewer_build_run01/venv/Scripts/python.exe'
if (-not (Test-Path $python)) {throw 'Existing locked PyInstaller environment is missing'}
New-Item -ItemType Directory -Path $target | Out-Null
foreach ($name in @('tmp','ultralytics_config','matplotlib_config','pyinstaller_cache')) {
    New-Item -ItemType Directory -Path (Join-Path $target $name) | Out-Null
}
$env:PYTHONDONTWRITEBYTECODE='1'
$env:YOLO_CONFIG_DIR="$target/ultralytics_config"
$env:MPLCONFIGDIR="$target/matplotlib_config"
$env:YOLO_AUTOINSTALL='false'
$env:YOLO_OFFLINE='true'
$env:PYINSTALLER_CONFIG_DIR="$target/pyinstaller_cache"
$env:TEMP="$target/tmp"
$env:TMP="$target/tmp"
$ErrorActionPreference='Continue'
& $python -m PyInstaller --noconfirm --onedir --windowed --name EES331_Action_Viewer --distpath "$target/dist" --workpath "$target/build" --specpath "$target" --paths "$PSScriptRoot/../udp_video" --paths 'E:/competition/2_fpga/2_axi_lite_test/pynq' --hidden-import action_link --hidden-import action_protocol --hidden-import stable_action --collect-data ultralytics --collect-submodules ultralytics.nn --copy-metadata ultralytics --add-data "$PSScriptRoot/../model/best.pt;model" --exclude-module onnx --exclude-module onnxruntime "$PSScriptRoot/gesture_viewer.py" *> "$target/build_console.txt"
$code=$LASTEXITCODE
$ErrorActionPreference='Stop'
if ($code -ne 0) {throw 'PyInstaller failed; retain build_console.txt'}
Get-FileHash "$target/dist/EES331_Action_Viewer/EES331_Action_Viewer.exe" | ConvertTo-Json |
    Set-Content "$target/executable_hash.json"
Write-Output 'ACTION_VIEWER_BUILD_COMPLETE'
