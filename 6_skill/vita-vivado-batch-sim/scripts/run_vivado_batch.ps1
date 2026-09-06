param(
  [Parameter(Mandatory=$true)][string]$TclFile,
  [Parameter(Mandatory=$true)][string]$RunDirectory,
  [Parameter(Mandatory=$true)][string]$VivadoBat,
  [string]$PassMarker='EES_VIVADO_RESULT PASS',
  [int]$TimeoutSeconds=300
)

$ErrorActionPreference='Stop'
$canonical='E:\competition\4_metrics\scripts\run_vivado_standalone_ees.ps1'
if(!(Test-Path -LiteralPath $canonical)){throw "EES_CANONICAL_LAUNCHER_NOT_FOUND $canonical"}
& $canonical -TclFile $TclFile -RunDirectory $RunDirectory -VivadoBat $VivadoBat -PassMarker $PassMarker -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
