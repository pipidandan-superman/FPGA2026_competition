param(
  [string]$WorkspaceRoot = 'E:\competition'
)

$ErrorActionPreference = 'Stop'
$skillRoots = @(
  (Join-Path $WorkspaceRoot '.codex\skills'),
  (Join-Path $WorkspaceRoot '6_skill')
)
$skillFiles = @()
foreach ($root in $skillRoots) {
  if (Test-Path -LiteralPath $root) {
    $skillFiles += Get-ChildItem -LiteralPath $root -Recurse -Filter SKILL.md -File
  }
}

$failures = @()
foreach ($file in $skillFiles) {
  $relative = $file.FullName.Substring($WorkspaceRoot.Length + 1)
  $expectedName = Split-Path -Path $file.DirectoryName -Leaf
  $text = Get-Content -Raw -LiteralPath $file.FullName
  if ($text -notmatch '(?m)^---\r?\nname:\s*([^\r\n]+)\r?\n') {
    $failures += "$relative : missing valid front-matter name"
    continue
  }
  $actualName = $Matches[1].Trim()
  if ($actualName -ne $expectedName) {
    $failures += "$relative : front-matter name '$actualName' does not match directory '$expectedName'"
  }
  if ($text -notmatch [regex]::Escape('E:\competition')) {
    $failures += "$relative : missing fixed E:\competition workspace path"
  }

  $forbiddenExecutablePatterns = @(
    '<workspace>/log/',
    '<workspace>\log\',
    '<workspace>/logs/',
    '<workspace>\logs\',
    'D:\VitA\5_verify',
    'Desktop\competition\6_skill',
    'VITA_VIVADO_RESULT'
  )
  foreach ($pattern in $forbiddenExecutablePatterns) {
    if ($text.Contains($pattern)) {
      $failures += "$relative : contains non-adapted executable path/token '$pattern'"
    }
  }
}

$companionFiles = @()
foreach ($root in $skillRoots) {
  if (Test-Path -LiteralPath $root) {
    $companionFiles += Get-ChildItem -LiteralPath $root -Recurse -File |
      Where-Object { $_.Name -ne 'SKILL.md' -and $_.Extension -in @('.ps1', '.tcl', '.sv', '.v', '.md', '.yaml', '.yml', '.json') }
  }
}
foreach ($file in $companionFiles) {
  $relative = $file.FullName.Substring($WorkspaceRoot.Length + 1)
  $text = Get-Content -Raw -LiteralPath $file.FullName
  $forbiddenCompanionPatterns = @(
    'D:\VitA\5_verify',
    'D:/VitA/5_verify',
    'D:\VitA\6_proj',
    'D:/VitA/6_proj',
    'Desktop\competition\6_skill',
    'Desktop/competition/6_skill',
    'VITA_VIVADO_RESULT',
    '<workspace>/log/',
    '<workspace>/logs/'
  )
  foreach ($pattern in $forbiddenCompanionPatterns) {
    if ($text.Contains($pattern)) {
      $failures += "$relative : contains non-adapted path/token '$pattern'"
    }
  }
}

$requiredMarkers = @(
  'E:\competition\7_logs',
  'E:\competition\4_metrics\logs',
  'E:\competition\2_fpga'
)
$policyPath = Join-Path $WorkspaceRoot '.codex\skills\project-workspace-policy\SKILL.md'
if (-not (Test-Path -LiteralPath $policyPath)) {
  $failures += '.codex/skills/project-workspace-policy/SKILL.md : missing mandatory policy skill'
} else {
  $policy = Get-Content -Raw -LiteralPath $policyPath
  foreach ($marker in $requiredMarkers) {
    if (-not $policy.Contains($marker)) {
      $failures += ".codex/skills/project-workspace-policy/SKILL.md : missing required marker '$marker'"
    }
  }
}

[pscustomobject]@{
  workspace = $WorkspaceRoot
  skill_count = $skillFiles.Count
  pass = ($failures.Count -eq 0)
  failures = @($failures)
} | ConvertTo-Json -Depth 4

if ($failures.Count -ne 0) {
  exit 2
}
