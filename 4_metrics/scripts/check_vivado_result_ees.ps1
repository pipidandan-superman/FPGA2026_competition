param(
  [Parameter(Mandatory=$true)][string]$RunDirectory,
  [string]$PassMarker='EES_VIVADO_RESULT PASS'
)

$ErrorActionPreference='Stop'
$run=[IO.Path]::GetFullPath($RunDirectory)
if(-not $run.StartsWith('E:\competition\4_metrics\logs\', [StringComparison]::OrdinalIgnoreCase)) {
  throw "EES_RUN_DIRECTORY_NOT_ALLOWED $run"
}
$statusPath=Join-Path $run 'process_status.json'
$logPath=Join-Path $run 'vivado_console.log'
$status=Get-Content -Raw -LiteralPath $statusPath | ConvertFrom-Json
$logExists=Test-Path -LiteralPath $logPath
$markerFound=$false
if($logExists){
  $markerFound=Select-String -LiteralPath $logPath -Pattern ([regex]::Escape($PassMarker)) -Quiet
}
$ok=$logExists -and $markerFound -and $status.state -eq 'PASS'
[pscustomobject]@{
  run=$run
  state=$status.state
  marker=$status.marker
  pass_marker_found=$markerFound
  exit_code=$status.exit_code
  timeout=$status.timeout
  valid_pass=$ok
} | ConvertTo-Json
if(-not $ok){exit 2}
