param([string]$BoardHost='192.168.240.10')
$ErrorActionPreference='Stop'
$sharedExe=Join-Path (Split-Path -Parent $PSScriptRoot) 'EES331_Gesture_Viewer_v1.0\EES331_Gesture_Viewer.exe'
$localExe=Join-Path $PSScriptRoot 'EES331_Action_Viewer.exe'
$exe=if(Test-Path -LiteralPath $sharedExe){$sharedExe}else{$localExe}
if(-not (Test-Path -LiteralPath $exe)){throw 'Action-capable viewer executable missing. Run git lfs pull and keep both viewer folders together.'}
# Explicit action-enabled launch. Double-clicking the EXE remains display-only.
# The paired action-v1 PYNQ application must already own the video and AXI path.
Start-Process -FilePath $exe -ArgumentList '--action-control','--action-host',$BoardHost
