param(
  [Parameter(Mandatory=$true)][string]$RunDirectory,
  [string]$PassMarker='EES_VIVADO_RESULT PASS'
)

$ErrorActionPreference='Stop'
$canonical='E:\competition\4_metrics\scripts\check_vivado_result_ees.ps1'
if(!(Test-Path -LiteralPath $canonical)){throw "EES_CANONICAL_CHECKER_NOT_FOUND $canonical"}
& $canonical -RunDirectory $RunDirectory -PassMarker $PassMarker
exit $LASTEXITCODE
