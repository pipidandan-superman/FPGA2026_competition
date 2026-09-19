$ErrorActionPreference = 'Stop'
$taskDoc = 'E:\competition\1_docs\yolo7020_hardware_deployment_plan_20260914.md'
$taskBase = 'E:\competition\4_metrics\logs\2026-09-14_yolo7020_plan_consolidation_run01'
$taskUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$taskText = $taskUtf8.GetString([IO.File]::ReadAllBytes($taskDoc))
$taskChecks = [ordered]@{}
$taskChecks['utf8_no_replacement_character'] = -not $taskText.Contains([char]0xFFFD)
$taskChecks['revision_r3'] = $taskText.Contains('2026-09-14 r3')
$taskExpectedRoute = [regex]::Unescape('\u6d6e\u70b9\u57fa\u7ebf \u2192 \u786c\u4ef6\u4e00\u81f4\u7684\u6574\u6570\u53c2\u8003 \u2192 \u5355\u6a21\u5757\u9a8c\u8bc1 \u2192 \u5b50\u56fe\u9a8c\u8bc1 \u2192 \u6574\u7f51\u9a8c\u8bc1 \u2192 \u5b9e\u65f6\u7cfb\u7edf\u9a8c\u6536')
$taskChecks['formal_six_stage_route'] = $taskText.Contains($taskExpectedRoute)
$taskHeadings = @([regex]::Matches($taskText, '(?m)^## ([0-9]+)\. ') | ForEach-Object { [int]$_.Groups[1].Value })
$taskChecks['chapters_1_through_13_once_in_order'] = (($taskHeadings -join ',') -eq ((1..13) -join ','))
$taskFencePattern = '(?m)^' + ([string][char]96)*3
$taskFenceCount = [regex]::Matches($taskText, $taskFencePattern).Count
$taskChecks['balanced_code_fences'] = ($taskFenceCount % 2 -eq 0)
$taskSections = @('4.4.1','4.4.2','4.4.3','4.4.4','4.6','4.7','5.5','9.1','9.2','9.3','9.4','10.1','10.2','10.3','10.4','10.5','10.6','12.1','12.2','12.3','12.4','13.1','13.2','13.3')
foreach ($taskSection in $taskSections) {
    $taskChecks['section_' + $taskSection] = [regex]::IsMatch($taskText, '(?m)^#{3,4} ' + [regex]::Escape($taskSection) + ' ')
}
$taskRequiredTerms = @('dataset_manifest.json','class_map.json','calibration_list.txt','validation_list.txt','test_list.txt','INT64','RNE','QDQ','mismatch_count=0','unpack(pack(tensor)) == tensor','golden_index.json','EXPERIMENTAL','B0','B1','B2','B3','B4','P95','P99','frame_id','TREADY','S2MM','DFL','NMS','QUANTIZATION_NOT_RUN','INTEGER_REFERENCE_NOT_IMPLEMENTED','RTL_NOT_IMPLEMENTED','BOARD_NOT_RUN')
foreach ($taskTerm in $taskRequiredTerms) {
    $taskChecks['coverage_' + $taskTerm] = $taskText.Contains($taskTerm)
}
$taskLinks = @()
$taskMissingLinks = @()
foreach ($taskMatch in [regex]::Matches($taskText, '\[[^\]]+\]\(([^\s\)]+)\)')) {
    $taskTarget = $taskMatch.Groups[1].Value
    if ($taskTarget -match '^[A-Za-z][A-Za-z0-9+.-]*://' -or $taskTarget.StartsWith('#')) { continue }
    $taskTargetPath = [Uri]::UnescapeDataString(($taskTarget -split '#',2)[0])
    $taskResolved = [IO.Path]::GetFullPath((Join-Path (Split-Path $taskDoc -Parent) $taskTargetPath))
    $taskLinks += $taskResolved
    if (-not (Test-Path -LiteralPath $taskResolved)) { $taskMissingLinks += $taskResolved }
}
$taskChecks['all_local_document_links_exist'] = ($taskMissingLinks.Count -eq 0)
$taskExpectedModelHashes = [ordered]@{
    'E:\competition\3_host\model\best.pt' = '68DB7CACBDD6D9C9A583E1C50A9F5934A3A6B78675B215EC86717827BE8BFC79'
    'E:\competition\3_host\model\best.onnx' = 'AC45C457BE282EA1D9DB819180930B062436ECC834219C3418FF06E9E6BBBF0F'
}
foreach ($taskModelPath in $taskExpectedModelHashes.Keys) {
    $taskChecks['unchanged_' + [IO.Path]::GetFileName($taskModelPath)] = ((Get-FileHash -LiteralPath $taskModelPath -Algorithm SHA256).Hash -eq $taskExpectedModelHashes[$taskModelPath])
}
$taskChecks['r1_snapshot_preserved'] = ((Get-FileHash -LiteralPath (Join-Path $taskBase 'plan_before_r1.md') -Algorithm SHA256).Hash -eq '9632590C505ABF45EEB2BADDB3BBA91DFEA53DC142C2A8051AFDF794E657859F')
$taskDailyNames = @('01_daily_plan.md','02_execution_plan.md','03_validation_summary.md','04_next_start_guide.md')
foreach ($taskDailyName in $taskDailyNames) {
    $taskDailyPath = Join-Path 'E:\competition\7_logs\2026-09-14' $taskDailyName
    $taskChecks['daily_' + $taskDailyName] = ((Test-Path -LiteralPath $taskDailyPath) -and ([IO.File]::ReadAllText($taskDailyPath).Contains('yolo7020_plan_consolidation_run01/REPORT.md')))
}
$taskAuditRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File 'E:\competition\4_metrics\scripts\audit_project_skill_paths.ps1'
$taskAuditExit = $LASTEXITCODE
$taskAudit = ($taskAuditRaw -join [Environment]::NewLine) | ConvertFrom-Json
$taskChecks['project_skill_paths'] = ($taskAuditExit -eq 0 -and $taskAudit.pass -eq $true)
$taskFailures = @($taskChecks.Keys | Where-Object { -not $taskChecks[$_] })
$taskResult = [ordered]@{
    result = $(if ($taskFailures.Count -eq 0) { 'DOCUMENT_VALIDATION_PASS' } else { 'DOCUMENT_VALIDATION_FAIL' })
    document = $taskDoc
    document_sha256 = (Get-FileHash -LiteralPath $taskDoc -Algorithm SHA256).Hash
    document_characters = $taskText.Length
    line_count = ($taskText -split '\r?\n').Count
    chapters = $taskHeadings
    check_count = $taskChecks.Count
    local_link_count = $taskLinks.Count
    missing_links = $taskMissingLinks
    checks = $taskChecks
    failed_checks = $taskFailures
    skill_path_audit = $taskAudit
    validation_scope = 'Documentation, references, encoding, topic coverage and input identity only; no quantization, RTL or board execution.'
}
$taskResult | ConvertTo-Json -Depth 7
if ($taskFailures.Count -ne 0) { exit 1 }
