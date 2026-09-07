param(
  [Parameter(Mandatory=$true)][int]$GuiPid,
  [Parameter(Mandatory=$true)][string]$TclFile,
  [Parameter(Mandatory=$true)][string]$RunDirectory,
  [int]$TimeoutSeconds=300
)

$ErrorActionPreference='Stop'
$canonical='E:\competition\4_metrics\scripts\run_vivado_batch_ees.ps1'
if(!(Test-Path -LiteralPath $canonical)){throw "EES_CANONICAL_LAUNCHER_NOT_FOUND $canonical"}
& $canonical -GuiPid $GuiPid -TclFile $TclFile -RunDirectory $RunDirectory -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
