param(
    [Parameter(ParameterSetName = "Directory", Mandatory = $true)]
    [string]$InputDir,
    [Parameter(ParameterSetName = "Directory", Mandatory = $true)]
    [string[]]$Patterns,
    [Parameter(ParameterSetName = "Single", Mandatory = $true)]
    [string]$InputPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputDir,
    [string]$MineruExe = "D:\work\conda\miniconda3\envs\mineru\Scripts\mineru.exe",
    [string]$MineruApiExe = "D:\work\conda\miniconda3\envs\mineru\Scripts\mineru-api.exe",
    [string]$PythonExe = "python",
    [string]$ChineseQualityScript = "",
    [int]$ApiPort = 58120,
    [string]$WorkRoot = "",
    [string]$ApiOutputRoot = ""
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $Global:PSNativeCommandUseErrorActionPreference = $false
}

$workspaceRoot = "E:\competition"
$evidenceRoot = Join-Path $workspaceRoot "4_metrics\logs"

function Resolve-FullPath {
    param([string]$PathValue)
    return [IO.Path]::GetFullPath($PathValue)
}

function Assert-WithinPath {
    param(
        [string]$Child,
        [string]$Parent,
        [string]$Label
    )
    $childFull = Resolve-FullPath -PathValue $Child
    $parentFull = (Resolve-FullPath -PathValue $Parent).TrimEnd("\") + "\"
    if (-not $childFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must stay under $parentFull but resolved to $childFull"
    }
    return $childFull
}

function Quote-Arg {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

$outputFull = Assert-WithinPath -Child $OutputDir -Parent $evidenceRoot -Label "OutputDir"
$runName = Split-Path -Leaf $outputFull
if ($runName -notmatch "^\d{4}-\d{2}-\d{2}_.+_run\d+$") {
    throw "OutputDir leaf must match YYYY-MM-DD_<task>_runNN: $runName"
}

if (-not $ChineseQualityScript) {
    $ChineseQualityScript = Join-Path $PSScriptRoot "check_mineru_chinese_quality.py"
}
if (-not $WorkRoot) {
    $WorkRoot = Join-Path $outputFull "_mineru_work"
}
if (-not $ApiOutputRoot) {
    $ApiOutputRoot = Join-Path $outputFull "_mineru_api"
}

$workFull = Assert-WithinPath -Child $WorkRoot -Parent $outputFull -Label "WorkRoot"
$apiOutputFull = Assert-WithinPath -Child $ApiOutputRoot -Parent $outputFull -Label "ApiOutputRoot"

if (-not (Test-Path -LiteralPath $MineruExe -PathType Leaf)) {
    throw "MinerU executable not found: $MineruExe"
}
if (-not (Test-Path -LiteralPath $MineruApiExe -PathType Leaf)) {
    throw "MinerU API executable not found: $MineruApiExe"
}
if (-not (Test-Path -LiteralPath $ChineseQualityScript -PathType Leaf)) {
    throw "Chinese quality checker not found: $ChineseQualityScript"
}

New-Item -ItemType Directory -Force -Path $outputFull, $workFull, $apiOutputFull | Out-Null

$markerPath = Join-Path $outputFull "mineru_result_marker.txt"
if (Test-Path -LiteralPath $markerPath) {
    throw "OutputDir already contains a result marker; select a fresh run directory: $outputFull"
}

$runnerLog = Join-Path $outputFull "mineru_runner_console.txt"
$apiStdout = Join-Path $outputFull "mineru_api_stdout.txt"
$apiStderr = Join-Path $outputFull "mineru_api_stderr.txt"
$resultPath = Join-Path $outputFull "mineru_results.json"
$manifestPath = Join-Path $outputFull "input_manifest.json"
$commandLogRoot = Join-Path $outputFull "command_logs"
New-Item -ItemType Directory -Force -Path $commandLogRoot | Out-Null
Set-Content -LiteralPath $runnerLog -Value "" -Encoding UTF8
Set-Content -LiteralPath $markerPath -Value "MINERU_PARSE_RUNNING" -Encoding ASCII

function Write-RunMessage {
    param([string]$Message)
    $timestamped = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Add-Content -LiteralPath $runnerLog -Value $timestamped -Encoding UTF8
    Write-Output $timestamped
}

function Set-MineruEnv {
    $env:MINERU_MODEL_SOURCE = "local"
    $env:MINERU_API_OUTPUT_ROOT = $apiOutputFull
    $env:NO_PROXY = "127.0.0.1,localhost"
    $env:no_proxy = "127.0.0.1,localhost"
    $env:HTTP_PROXY = ""
    $env:HTTPS_PROXY = ""
    $env:ALL_PROXY = ""
    $env:http_proxy = ""
    $env:https_proxy = ""
    $env:all_proxy = ""
}

function Wait-ApiHealth {
    param([string]$Url)
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        try {
            $health = Invoke-RestMethod -Uri "$Url/health" -TimeoutSec 2
            if ($health.status -eq "healthy") {
                return
            }
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    throw "MinerU API did not become healthy at $Url"
}

function Get-ShortStem {
    param([string]$Name)
    $stem = [IO.Path]::GetFileNameWithoutExtension($Name)
    if ($stem -match "^(\d{2})[_ -]?") {
        $prefix = $Matches[1]
        $rest = $stem.Substring($Matches[0].Length)
        $token = (($rest -replace "[^\p{L}\p{Nd}_-]", "_") -split "[ _]")[0]
        if (-not $token) {
            $token = "document"
        }
        return "$($prefix)_$token"
    }
    $safeStem = $stem -replace "[^\p{L}\p{Nd}_-]", "_"
    if ($safeStem.Length -gt 32) {
        return $safeStem.Substring(0, 32)
    }
    return $safeStem
}

function Test-MineruOutput {
    param(
        [string]$Folder,
        [string]$Stem
    )
    $autoFolder = Join-Path $Folder "auto"
    $markdownPath = Join-Path $autoFolder ($Stem + ".md")
    $contentJsonPath = Join-Path $autoFolder ($Stem + "_content_list.json")
    $imagesPath = Join-Path $autoFolder "images"
    [PSCustomObject]@{
        Markdown = Test-Path -LiteralPath $markdownPath -PathType Leaf
        ContentJson = Test-Path -LiteralPath $contentJsonPath -PathType Leaf
        ImageCount = if (Test-Path -LiteralPath $imagesPath -PathType Container) {
            @(Get-ChildItem -LiteralPath $imagesPath -File -ErrorAction SilentlyContinue).Count
        } else {
            0
        }
        MarkdownPath = $markdownPath
        ContentJsonPath = $contentJsonPath
        OutputFolder = $Folder
    }
}

function Run-Mineru {
    param(
        [string]$FilePath,
        [string]$OutDir,
        [string]$ApiUrl,
        [string]$LogStem
    )
    $stdoutPath = Join-Path $commandLogRoot ($LogStem + "_stdout.txt")
    $stderrPath = Join-Path $commandLogRoot ($LogStem + "_stderr.txt")
    $argumentString = @(
        "-p", (Quote-Arg $FilePath),
        "-o", (Quote-Arg $OutDir),
        "--api-url", (Quote-Arg $ApiUrl),
        "-b", "pipeline"
    ) -join " "
    $process = Start-Process -FilePath $MineruExe -ArgumentList $argumentString -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    [PSCustomObject]@{
        ExitCode = $process.ExitCode
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
        Output = ((Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue), (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue)) -join [Environment]::NewLine
    }
}

function Test-ChineseQuality {
    param(
        [string]$Folder,
        [string]$LogStem
    )
    $stdoutPath = Join-Path $commandLogRoot ($LogStem + "_quality_stdout.json")
    $stderrPath = Join-Path $commandLogRoot ($LogStem + "_quality_stderr.txt")
    try {
        $arguments = (Quote-Arg $ChineseQualityScript) + " " + (Quote-Arg $Folder) + " --json"
        $process = Start-Process -FilePath $PythonExe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        if ($process.ExitCode -gt 1 -or -not (Test-Path -LiteralPath $stdoutPath)) {
            throw "Quality checker failed with exit code $($process.ExitCode)"
        }
        $parsed = Get-Content -LiteralPath $stdoutPath -Raw | ConvertFrom-Json
        return [PSCustomObject]@{
            Status = $parsed.status
            PreferredSource = $parsed.preferred_source
            Reasons = @($parsed.reasons) -join ","
        }
    } catch {
        return [PSCustomObject]@{
            Status = "unknown"
            PreferredSource = ""
            Reasons = "quality_check_failed:$($_.Exception.Message)"
        }
    }
}

if ($PSCmdlet.ParameterSetName -eq "Single") {
    $files = @(Get-Item -LiteralPath $InputPath)
} else {
    $normalizedPatterns = @()
    foreach ($patternValue in $Patterns) {
        $normalizedPatterns += ($patternValue -split ",") |
            ForEach-Object { $_.Trim().Trim("'").Trim('"') } |
            Where-Object { $_ }
    }
    $files = foreach ($pattern in $normalizedPatterns) {
        Get-ChildItem -LiteralPath $InputDir -Filter $pattern -File
    }
    $files = @($files | Sort-Object FullName -Unique)
}

if ($files.Count -eq 0) {
    Set-Content -LiteralPath $markerPath -Value ("MINERU_PARSE_FAIL" + [Environment]::NewLine + "reason=no_input_files") -Encoding ASCII
    throw "No input files matched."
}

$supportedExtensions = @(".pdf", ".png", ".jpg", ".jpeg", ".tif", ".tiff", ".docx", ".pptx", ".xlsx", ".xls")
foreach ($file in $files) {
    if ($file.Extension.ToLowerInvariant() -notin $supportedExtensions) {
        Set-Content -LiteralPath $markerPath -Value ("MINERU_PARSE_FAIL" + [Environment]::NewLine + "reason=unsupported_extension") -Encoding ASCII
        throw "Unsupported input extension: $($file.FullName)"
    }
}

$inputManifest = foreach ($file in $files) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName
    [PSCustomObject]@{
        Path = $file.FullName
        Name = $file.Name
        Size = $file.Length
        SHA256 = $hash.Hash
    }
}
$inputManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Set-MineruEnv
$apiUrl = "http://127.0.0.1:$ApiPort"
$apiProcess = $null

try {
    Write-RunMessage "workspace=$workspaceRoot"
    Write-RunMessage "output=$outputFull"
    Write-RunMessage "backend=pipeline model_source=local api=$apiUrl"
    $apiProcess = Start-Process -FilePath $MineruApiExe -ArgumentList @("--host", "127.0.0.1", "--port", "$ApiPort") -PassThru -WindowStyle Hidden -RedirectStandardOutput $apiStdout -RedirectStandardError $apiStderr
    Wait-ApiHealth -Url $apiUrl
    Write-RunMessage "MinerU API healthy."

    $results = @()
    $fileNumber = 0
    foreach ($file in $files) {
        $fileNumber++
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $logStem = "{0:D2}_{1}" -f $fileNumber, (Get-ShortStem -Name $file.Name)
        Write-RunMessage "START file=$($file.FullName) sha256=$($inputManifest[$fileNumber - 1].SHA256)"

        $run = Run-Mineru -FilePath $file.FullName -OutDir $outputFull -ApiUrl $apiUrl -LogStem $logStem
        $usedFallback = $false
        $finalFolder = Join-Path $outputFull $stem
        $finalStem = $stem

        if ($run.ExitCode -ne 0 -and $run.Output -match "_origin\.pdf|No such file or directory") {
            $usedFallback = $true
            $shortStem = Get-ShortStem -Name $file.Name
            $fallbackRoot = Join-Path $workFull $logStem
            $workInput = Join-Path $fallbackRoot "input"
            $workOutput = Join-Path $fallbackRoot "output"
            New-Item -ItemType Directory -Force -Path $workInput, $workOutput | Out-Null
            $shortPath = Join-Path $workInput ($shortStem + $file.Extension)
            Copy-Item -LiteralPath $file.FullName -Destination $shortPath
            Write-RunMessage "Long-path fallback file=$($file.Name) short=$shortPath"
            $run = Run-Mineru -FilePath $shortPath -OutDir $workOutput -ApiUrl $apiUrl -LogStem ($logStem + "_fallback")
            $finalFolder = Join-Path $outputFull $shortStem
            $finalStem = $shortStem

            if ($run.ExitCode -eq 0) {
                [void](Assert-WithinPath -Child $finalFolder -Parent $outputFull -Label "Fallback destination")
                if (Test-Path -LiteralPath $finalFolder) {
                    Remove-Item -LiteralPath $finalFolder -Recurse -Force
                }
                Copy-Item -LiteralPath (Join-Path $workOutput $shortStem) -Destination $finalFolder -Recurse
            }
        }

        $stopwatch.Stop()
        $check = Test-MineruOutput -Folder $finalFolder -Stem $finalStem
        $quality = Test-ChineseQuality -Folder $finalFolder -LogStem $logStem
        $results += [PSCustomObject]@{
            File = $file.Name
            InputPath = $file.FullName
            SHA256 = $inputManifest[$fileNumber - 1].SHA256
            ExitCode = $run.ExitCode
            Seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
            Fallback = $usedFallback
            Markdown = $check.Markdown
            ContentJson = $check.ContentJson
            ImageCount = $check.ImageCount
            ChineseQuality = $quality.Status
            PreferredSource = $quality.PreferredSource
            QualityReasons = $quality.Reasons
            MarkdownPath = $check.MarkdownPath
            ContentJsonPath = $check.ContentJsonPath
            OutputFolder = $check.OutputFolder
            StdoutPath = $run.StdoutPath
            StderrPath = $run.StderrPath
        }
        Write-RunMessage "END file=$($file.Name) code=$($run.ExitCode) markdown=$($check.Markdown) content_json=$($check.ContentJson) images=$($check.ImageCount) fallback=$usedFallback seconds=$([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))"
    }

    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $failed = @($results | Where-Object { $_.ExitCode -ne 0 -or -not $_.Markdown -or -not $_.ContentJson })
    if ($failed.Count -gt 0) {
        Set-Content -LiteralPath $markerPath -Value ("MINERU_PARSE_FAIL" + [Environment]::NewLine + "failed_count=$($failed.Count)") -Encoding ASCII
        Write-RunMessage "RESULT MINERU_PARSE_FAIL failed_count=$($failed.Count)"
        throw "MinerU parsing contract failed for $($failed.Count) file(s)."
    }

    Set-Content -LiteralPath $markerPath -Value ("MINERU_PARSE_PASS" + [Environment]::NewLine + "file_count=$($results.Count)") -Encoding ASCII
    Write-RunMessage "RESULT MINERU_PARSE_PASS file_count=$($results.Count)"
    $results | Format-Table File, ExitCode, Seconds, Fallback, Markdown, ContentJson, ImageCount, ChineseQuality, PreferredSource -AutoSize
} catch {
    if (-not (Test-Path -LiteralPath $markerPath) -or (Get-Content -LiteralPath $markerPath -Raw) -match "RUNNING") {
        Set-Content -LiteralPath $markerPath -Value ("MINERU_PARSE_FAIL" + [Environment]::NewLine + "reason=$($_.Exception.Message)") -Encoding ASCII
    }
    Write-RunMessage "ERROR $($_.Exception.Message)"
    throw
} finally {
    if ($apiProcess -and -not $apiProcess.HasExited) {
        Stop-Process -Id $apiProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
