param(
    [Parameter(Mandatory=$true)][string]$BuildRun,
    [string]$ReleaseDir='E:\competition\8_tools\EES331_PL_Reloader_v1.4'
)
$ErrorActionPreference='Stop'
$target=[IO.Path]::GetFullPath($BuildRun)
if(-not $target.StartsWith('E:\competition\4_metrics\logs\',[StringComparison]::OrdinalIgnoreCase)){
    throw 'BuildRun must be under E:\competition\4_metrics\logs'
}
if(Test-Path -LiteralPath $target){throw 'Use a new immutable build run directory'}
$release=[IO.Path]::GetFullPath($ReleaseDir)
if(Test-Path -LiteralPath $release){throw 'ReleaseDir already exists; choose a new version'}

$bootstrapPython='D:\work\Python\python.exe'
$wheelhouse='E:\competition\4_metrics\logs\2026-09-12_ble_host_tool_build_run02\wheelhouse'
if(-not (Test-Path -LiteralPath $bootstrapPython)){throw 'Bootstrap Python is missing'}
if(-not (Test-Path -LiteralPath $wheelhouse)){throw 'Offline PyInstaller wheelhouse is missing'}
$source=Join-Path $PSScriptRoot 'pl_reloader_gui.py'
$askpassSource=Join-Path $PSScriptRoot 'ssh_askpass.py'
$controller=Join-Path $PSScriptRoot 'board_pl_reload_controller.py'
$payloadSource='E:\competition\9_pynq\overlays\action_v1_20260913'
foreach($path in @($source,$askpassSource,$controller,$payloadSource)){
    if(-not (Test-Path -LiteralPath $path)){throw "Required input missing: $path"}
}

New-Item -ItemType Directory -Path $target | Out-Null
foreach($name in @('tmp','pyinstaller_cache')){
    New-Item -ItemType Directory -Path (Join-Path $target $name) | Out-Null
}
$venv=Join-Path $target 'venv'
& $bootstrapPython -m venv $venv
if($LASTEXITCODE -ne 0){throw 'Failed to create isolated build environment'}
$python=Join-Path $venv 'Scripts\python.exe'
$ErrorActionPreference='Continue'
& $python -m pip install --disable-pip-version-check --no-index --find-links $wheelhouse `
    'pyinstaller==6.22.2' *> (Join-Path $target 'offline_install.txt')
$installCode=$LASTEXITCODE
$ErrorActionPreference='Stop'
if($installCode -ne 0){throw "Offline PyInstaller install failed; see $target\offline_install.txt"}
& $python -c 'import platform,PyInstaller; print(platform.python_version()); print(PyInstaller.__version__)' `
    | Set-Content -LiteralPath (Join-Path $target 'tool_versions.txt') -Encoding UTF8
$env:PYTHONDONTWRITEBYTECODE='1'
$env:PYINSTALLER_CONFIG_DIR=Join-Path $target 'pyinstaller_cache'
$env:TEMP=Join-Path $target 'tmp'
$env:TMP=Join-Path $target 'tmp'

$ErrorActionPreference='Continue'
& $python -m PyInstaller --noconfirm --onedir --windowed `
    --name EES331_PL_Reloader `
    --distpath (Join-Path $target 'dist') `
    --workpath (Join-Path $target 'build') `
    --specpath $target `
    --hidden-import tkinter `
    $source *> (Join-Path $target 'build_console.txt')
$buildCode=$LASTEXITCODE
$ErrorActionPreference='Stop'
if($buildCode -ne 0){throw "PyInstaller failed; see $target\build_console.txt"}

$dist=Join-Path $target 'dist\EES331_PL_Reloader'
$ErrorActionPreference='Continue'
& $python -m PyInstaller --noconfirm --onefile --console `
    --name EES331_SSH_AskPass `
    --distpath (Join-Path $target 'askpass_dist') `
    --workpath (Join-Path $target 'askpass_build') `
    --specpath $target `
    $askpassSource *> (Join-Path $target 'askpass_build_console.txt')
$askpassBuildCode=$LASTEXITCODE
$ErrorActionPreference='Stop'
if($askpassBuildCode -ne 0){throw "AskPass build failed; see $target\askpass_build_console.txt"}
$askpassTarget=Join-Path $dist 'askpass'
New-Item -ItemType Directory -Path $askpassTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $target 'askpass_dist\EES331_SSH_AskPass.exe') `
    -Destination (Join-Path $askpassTarget 'EES331_SSH_AskPass.exe')

$payloadTarget=Join-Path $dist 'payload\action_v1_20260913'
New-Item -ItemType Directory -Path $payloadTarget | Out-Null
Copy-Item -Path (Join-Path $payloadSource '*') -Destination $payloadTarget -Recurse -Force
Copy-Item -LiteralPath $controller -Destination (Join-Path $payloadTarget 'board_pl_reload_controller.py') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $dist 'README.md') -Force

$selfTestPath=Join-Path $target 'packaged_self_test.txt'
$selfTestProcess=Start-Process -FilePath (Join-Path $dist 'EES331_PL_Reloader.exe') `
    -ArgumentList @('--self-test','--self-test-output',('"'+$selfTestPath+'"')) `
    -WindowStyle Hidden -Wait -PassThru
$selfTestCode=$selfTestProcess.ExitCode
if($selfTestCode -ne 0 -or -not (Select-String -LiteralPath $selfTestPath -Pattern 'PL_RELOADER_SELF_TEST_PASS' -Quiet)){
    throw "Packaged self-test failed; see $selfTestPath"
}

$manifest=@()
Get-ChildItem -LiteralPath $dist -Recurse -File | Sort-Object FullName | ForEach-Object {
    $manifest += [pscustomobject]@{
        path=$_.FullName.Substring($dist.Length+1).Replace('\','/')
        bytes=$_.Length
        sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower()
    }
}
$packageManifest=[ordered]@{
    marker='PL_RELOADER_PACKAGE_PASS'
    built_at=(Get-Date).ToString('o')
    source='3_host/pynq/pl_reloader/pl_reloader_gui.py'
    payload='9_pynq/overlays/action_v1_20260913'
    files=$manifest
}
$packageManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dist 'package_manifest.json') -Encoding UTF8

New-Item -ItemType Directory -Path $release | Out-Null
Copy-Item -Path (Join-Path $dist '*') -Destination $release -Recurse -Force
Write-Output "PL_RELOADER_BUILD_COMPLETE: $release"
