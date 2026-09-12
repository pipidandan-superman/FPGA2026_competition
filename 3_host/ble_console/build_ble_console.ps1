param(
    [Parameter(Mandatory = $true)]
    [string]$BuildRun,
    [string]$PythonExe =
        'C:\Users\Administrator\AppData\Local\Programs\Python\Python312\python.exe',
    [string]$ReleaseRoot =
        'E:\competition\8_tools\EES331_BLE_Console_v1.0'
)

$ErrorActionPreference = 'Stop'

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspaceRoot = 'E:\competition'
$evidenceRoot = Join-Path $workspaceRoot '4_metrics\logs'
$resolvedBuildRun = [System.IO.Path]::GetFullPath($BuildRun)
$resolvedEvidenceRoot = [System.IO.Path]::GetFullPath($evidenceRoot)
$resolvedReleaseRoot = [System.IO.Path]::GetFullPath($ReleaseRoot)
$requiredReleaseRoot = [System.IO.Path]::GetFullPath(
    'E:\competition\8_tools\EES331_BLE_Console_v1.0'
)

if (-not $resolvedBuildRun.StartsWith($resolvedEvidenceRoot)) {
    throw "BuildRun必须位于 $resolvedEvidenceRoot"
}
if ($resolvedReleaseRoot -ne $requiredReleaseRoot) {
    throw "ReleaseRoot必须为 $requiredReleaseRoot"
}
if (-not (Test-Path -LiteralPath $PythonExe)) {
    throw "Python不存在：$PythonExe"
}

$venvRoot = Join-Path $resolvedBuildRun 'venv'
$wheelRoot = Join-Path $resolvedBuildRun 'wheelhouse'
$distRoot = Join-Path $resolvedBuildRun 'dist'
$workRoot = Join-Path $resolvedBuildRun 'pyinstaller_work'
$specRoot = Join-Path $resolvedBuildRun 'spec'
$testLog = Join-Path $resolvedBuildRun 'unit_tests.log'
$buildLog = Join-Path $resolvedBuildRun 'pyinstaller.log'
$selfTestMarker = Join-Path $resolvedBuildRun 'exe_self_test.txt'

foreach ($path in @($venvRoot, $wheelRoot, $distRoot, $workRoot, $specRoot)) {
    if (Test-Path -LiteralPath $path) {
        throw "拒绝覆盖已有构建路径：$path"
    }
}

$releaseItems = Get-ChildItem -LiteralPath $resolvedReleaseRoot -Force
if ($releaseItems.Count -ne 0) {
    throw "拒绝覆盖非空发布目录：$resolvedReleaseRoot"
}

& $PythonExe -m venv $venvRoot
$venvPython = Join-Path $venvRoot 'Scripts\python.exe'

& $venvPython -m pip download `
    --only-binary=:all: `
    --dest $wheelRoot `
    -r (Join-Path $sourceRoot 'requirements.in')
if ($LASTEXITCODE -ne 0) {
    throw "依赖下载失败：$LASTEXITCODE"
}

& $venvPython -m pip install `
    --no-index `
    --find-links $wheelRoot `
    -r (Join-Path $sourceRoot 'requirements.in')
if ($LASTEXITCODE -ne 0) {
    throw "隔离环境安装失败：$LASTEXITCODE"
}

& $venvPython -m pip freeze |
    Set-Content -LiteralPath (Join-Path $resolvedBuildRun 'resolved_requirements.txt') `
        -Encoding utf8

Get-ChildItem -LiteralPath $wheelRoot -File |
    Get-FileHash -Algorithm SHA256 |
    ForEach-Object { '{0}  {1}' -f $_.Hash, (Split-Path -Leaf $_.Path) } |
    Set-Content -LiteralPath (Join-Path $resolvedBuildRun 'wheel_sha256.txt') `
        -Encoding utf8

Push-Location $sourceRoot
try {
    & $venvPython -m unittest discover -s tests -v 2>&1 |
        Tee-Object -FilePath $testLog
    if ($LASTEXITCODE -ne 0) {
        throw "单元测试失败：$LASTEXITCODE"
    }

    & $venvPython -m PyInstaller `
        --noconfirm `
        --clean `
        --windowed `
        --onedir `
        --name EES331_BLE_Console `
        --distpath $distRoot `
        --workpath $workRoot `
        --specpath $specRoot `
        --collect-all bleak `
        app.py 2>&1 |
        Tee-Object -FilePath $buildLog
    if ($LASTEXITCODE -ne 0) {
        throw "PyInstaller构建失败：$LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$builtRoot = Join-Path $distRoot 'EES331_BLE_Console'
$builtExe = Join-Path $builtRoot 'EES331_BLE_Console.exe'
if (-not (Test-Path -LiteralPath $builtExe)) {
    throw "未生成EXE：$builtExe"
}

$selfTestProcess = Start-Process -FilePath $builtExe `
    -ArgumentList @('--self-test', '--self-test-output', $selfTestMarker) `
    -Wait `
    -PassThru `
    -WindowStyle Hidden
if ($selfTestProcess.ExitCode -ne 0) {
    throw "EXE自检失败：$($selfTestProcess.ExitCode)"
}
$marker = Get-Content -LiteralPath $selfTestMarker -Raw
if ($marker -notmatch 'BLE_CONSOLE_SELF_TEST_PASS') {
    throw 'EXE自检缺少PASS标记'
}

Copy-Item -Path (Join-Path $builtRoot '*') `
    -Destination $resolvedReleaseRoot `
    -Recurse
Copy-Item -LiteralPath (Join-Path $SourceRoot '使用说明.md') `
    -Destination (Join-Path $resolvedReleaseRoot '使用说明.md')

Get-ChildItem -LiteralPath $resolvedReleaseRoot -File -Recurse |
    Get-FileHash -Algorithm SHA256 |
    ForEach-Object {
        $relative = [System.IO.Path]::GetRelativePath($resolvedReleaseRoot, $_.Path)
        '{0}  {1}' -f $_.Hash, $relative
    } |
    Set-Content -LiteralPath (Join-Path $resolvedBuildRun 'release_sha256.txt') `
        -Encoding utf8

Write-Host "BLE_CONSOLE_BUILD_PASS release=$resolvedReleaseRoot"
