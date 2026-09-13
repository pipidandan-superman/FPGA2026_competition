param([Parameter(Mandatory=$true)][string]$BuildRun)
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($BuildRun)
if (-not $target.StartsWith('E:\competition\4_metrics\logs\', [StringComparison]::OrdinalIgnoreCase)) { throw 'BuildRun must be an evidence run' }
$python = "$target/venv/Scripts/python.exe"
if (-not (Test-Path $python)) { throw 'Prepare the isolated locked build environment first' }
$env:PYTHONDONTWRITEBYTECODE='1'
$env:YOLO_CONFIG_DIR="$target/ultralytics_config"
$env:MPLCONFIGDIR="$target/matplotlib_config"
$env:YOLO_AUTOINSTALL='false'
$env:YOLO_OFFLINE='true'
$env:PYINSTALLER_CONFIG_DIR="$target/pyinstaller_cache"
$env:TEMP="$target/tmp"
$env:TMP="$target/tmp"
# Windows PowerShell 5 treats redirected native stderr (including INFO) as errors.
$ErrorActionPreference = 'Continue'
& $python -m PyInstaller --noconfirm --onedir --windowed --name EES331_Gesture_Viewer --distpath "$target/dist" --workpath "$target/build" --specpath "$target" --paths "$PSScriptRoot/../udp_video" --collect-data ultralytics --collect-submodules ultralytics.nn --copy-metadata ultralytics --add-data "$PSScriptRoot/../model/best.pt;model" --exclude-module onnx --exclude-module onnxruntime "$PSScriptRoot/gesture_viewer.py" *> "$target/build_console.txt"
$buildExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($buildExit -ne 0) { throw "Build failed: $target/build_console.txt" }
Write-Output "BUILD_COMPLETE: $target/dist/EES331_Gesture_Viewer"
