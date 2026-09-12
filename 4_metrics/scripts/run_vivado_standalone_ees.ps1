param(
  [Parameter(Mandatory=$true)][string]$TclFile,
  [Parameter(Mandatory=$true)][string]$RunDirectory,
  [Parameter(Mandatory=$true)][string]$VivadoBat,
  [string]$PassMarker='EES_VIVADO_RESULT PASS',
  [int]$TimeoutSeconds=300
)

$ErrorActionPreference='Stop'
$run=[IO.Path]::GetFullPath($RunDirectory)
$tcl=[IO.Path]::GetFullPath($TclFile)
$vivadoBatResolved=[IO.Path]::GetFullPath($VivadoBat)
if(!(Test-Path -LiteralPath $tcl)){throw "TCL_NOT_FOUND $tcl"}
if(!(Test-Path -LiteralPath $vivadoBatResolved)){throw "VIVADO_BAT_NOT_FOUND $vivadoBatResolved"}
if(-not $run.StartsWith('E:\competition\4_metrics\logs\', [StringComparison]::OrdinalIgnoreCase)) {
  throw "EES_RUN_DIRECTORY_NOT_ALLOWED $run"
}
New-Item -ItemType Directory -Force -Path $run | Out-Null
$console=Join-Path $run 'vivado_console.log'
$status=Join-Path $run 'process_status.json'
$result=Join-Path $run 'result.json'
$start=Get-Date

Get-ChildItem -LiteralPath $run -File | ForEach-Object {
  [pscustomobject]@{
    path=$_.FullName
    size=$_.Length
    modified=$_.LastWriteTimeUtc.ToString('o')
    sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'run_input_manifest.json') -Encoding UTF8

$psi=[Diagnostics.ProcessStartInfo]::new()
$psi.FileName=$env:ComSpec
$psi.UseShellExecute=$false
$psi.CreateNoWindow=$true
$psi.WorkingDirectory=$run
$psi.RedirectStandardOutput=$true
$psi.RedirectStandardError=$true
$psi.Arguments='/d /c call "'+$vivadoBatResolved+'" -mode batch -source "'+$tcl+'" -nojournal -nolog'
$p=[Diagnostics.Process]::new()
$p.StartInfo=$psi
$null=$p.Start()
$outTask=$p.StandardOutput.ReadToEndAsync()
$errTask=$p.StandardError.ReadToEndAsync()
$childPid=$p.Id
$timedOut=$false
$deadline=$start.AddSeconds($TimeoutSeconds)
while(-not $p.HasExited){
  if((Get-Date) -gt $deadline){
    $timedOut=$true
    break
  }
  Start-Sleep -Milliseconds 500
}
if($timedOut){
  & taskkill.exe /PID $childPid /T /F 2>$null | Out-Null
  $p.WaitForExit(10000) | Out-Null
}

$raw=$outTask.Result+"`r`n"+$errTask.Result
$raw | Set-Content -LiteralPath $console -Encoding UTF8
$exitCode=if($p.HasExited){$p.ExitCode}else{999}
$markerFound=Select-String -LiteralPath $console -Pattern ('^\s*'+[regex]::Escape($PassMarker)+'\s*$') -Quiet
# Vivado echoes Tcl source with # prefixes; only actual diagnostic lines count.
$failFound=Select-String -LiteralPath $console -Pattern '^\s*(EES_VIVADO_RESULT FAIL|ERROR:|FATAL:|CRITICAL WARNING:)' -Quiet
$state=if($timedOut){'TIMEOUT'}elseif($exitCode -ne 0){'PROCESS_FAIL'}elseif($failFound){'DESIGN_FAIL'}elseif(-not $markerFound){'INCONCLUSIVE_NO_MARKER'}else{'PASS'}
[pscustomobject]@{
  run_id=(Split-Path $run -Leaf)
  pid=$childPid
  start=$start.ToString('o')
  end=(Get-Date).ToString('o')
  exit_code=$exitCode
  timeout=$timedOut
  marker=$markerFound
  fail_text=$failFound
  state=$state
  tcl=$tcl
  vivado=$vivadoBatResolved
} | ConvertTo-Json | Set-Content -LiteralPath $status -Encoding UTF8
if(!(Test-Path -LiteralPath $result)){
  [pscustomobject]@{state=$state;marker=$markerFound;exit_code=$exitCode} | ConvertTo-Json | Set-Content -LiteralPath $result -Encoding UTF8
}
if($state -ne 'PASS'){exit 2}
