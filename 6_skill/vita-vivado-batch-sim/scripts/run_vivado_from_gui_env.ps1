param(
  [Parameter(Mandatory=$true)][int]$GuiPid,
  [Parameter(Mandatory=$true)][string]$TclFile,
  [Parameter(Mandatory=$true)][string]$RunDirectory,
  [int]$TimeoutSeconds=300
)

$ErrorActionPreference='Stop'
if(-not ('ViTA.GuiEnvironment' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace ViTA {
 public static class GuiEnvironment {
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool b,int p);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,int n,out IntPtr r);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h,int c,IntPtr i,int l,out int r);
  public static string[] Read(int pid) {
   IntPtr h=OpenProcess(0x0410,false,pid); if(h==IntPtr.Zero) throw new Exception("OpenProcess failed");
   IntPtr q=Marshal.AllocHGlobal(48); int ignored;
   if(NtQueryInformationProcess(h,0,q,48,out ignored)!=0) throw new Exception("NtQueryInformationProcess failed");
   IntPtr peb=Marshal.ReadIntPtr(q,8), got; byte[] ptr=new byte[8];
   if(!ReadProcessMemory(h,IntPtr.Add(peb,0x20),ptr,8,out got)) throw new Exception("Cannot read PEB");
   IntPtr parameters=(IntPtr)BitConverter.ToInt64(ptr,0);
   if(!ReadProcessMemory(h,IntPtr.Add(parameters,0x80),ptr,8,out got)) throw new Exception("Cannot read process parameters");
   IntPtr environment=(IntPtr)BitConverter.ToInt64(ptr,0); byte[] data=new byte[262144];
   if(!ReadProcessMemory(h,environment,data,data.Length,out got)) throw new Exception("Cannot read environment");
   CloseHandle(h); Marshal.FreeHGlobal(q); int length=0;
   for(;length+3<data.Length;length+=2) if(data[length]==0 && data[length+1]==0 && data[length+2]==0 && data[length+3]==0) break;
   return System.Text.Encoding.Unicode.GetString(data,0,length).Split('\0');
 }
 }
}
'@
}

$run=[IO.Path]::GetFullPath($RunDirectory); $tcl=[IO.Path]::GetFullPath($TclFile)
if(!(Test-Path -LiteralPath $tcl)){throw "TCL_NOT_FOUND $tcl"}
$tclText = Get-Content -Raw -LiteralPath $tcl
if($tclText -match '(?i)xsim\.simulate\.log_all_signals\s+\{?1\}?'){
  throw "VITA_WAVEFORM_LOGGING_ENABLED $tcl"
}
New-Item -ItemType Directory -Force -Path $run | Out-Null
$inputFiles = Get-ChildItem -LiteralPath $run -File -Recurse | Sort-Object FullName |
  ForEach-Object {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName
    [pscustomobject]@{
      path = $_.FullName
      relative_path = $_.FullName.Substring($run.Length).TrimStart('\\')
      length = $_.Length
      last_write_utc = $_.LastWriteTimeUtc.ToString('o')
      sha256 = $hash.Hash
    }
  }
[pscustomobject]@{
  created_utc = (Get-Date).ToUniversalTime().ToString('o')
  run_directory = $run
  tcl_file = $tcl
  inputs = @($inputFiles)
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run 'run_input_manifest.json') -Encoding utf8
$envPairs=[ViTA.GuiEnvironment]::Read($GuiPid)
$vivadoEnv=($envPairs | Where-Object {$_ -like 'XILINX_VIVADO=*'} | Select-Object -First 1)
if(!$vivadoEnv){throw 'GUI_ENV_MISSING_XILINX_VIVADO'}
$vivadoRoot=$vivadoEnv.Substring('XILINX_VIVADO='.Length).Replace('/','\')
$exe=Join-Path $vivadoRoot 'bin\unwrapped\win64.o\vivado.exe'
if(!(Test-Path -LiteralPath $exe)){throw "VIVADO_EXE_NOT_FOUND $exe"}

$psi=[Diagnostics.ProcessStartInfo]::new(); $psi.FileName=$exe; $psi.UseShellExecute=$false
$psi.CreateNoWindow=$true; $psi.WorkingDirectory=$run; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
$psi.Arguments='-mode batch -source "'+$tcl+'" -nojournal -nolog'
$psi.Environment.Clear()
foreach($pair in $envPairs){$i=$pair.IndexOf('='); if($i -gt 0){$psi.Environment[$pair.Substring(0,$i)]=$pair.Substring($i+1)}}
$proc=[Diagnostics.Process]::new(); $proc.StartInfo=$psi; $null=$proc.Start(); $started=Get-Date
$out=$proc.StandardOutput.ReadToEndAsync(); $err=$proc.StandardError.ReadToEndAsync()
$timedOut=-not $proc.WaitForExit($TimeoutSeconds*1000)
if($timedOut){
  & taskkill.exe /PID $proc.Id /T /F 2>$null | Out-Null
  $proc.WaitForExit()
}
$raw=$out.Result+"`r`n"+$err.Result; $raw | Set-Content -LiteralPath (Join-Path $run 'vivado_console.log') -Encoding utf8
$marker=($raw -match 'VITA_VIVADO_RESULT PASS'); $fatal=($raw -match '(?im)^Fatal:|VITA_VIVADO_RESULT FAIL|\bERROR:')
$state=if(-not $timedOut -and $proc.ExitCode -eq 0 -and $marker -and -not $fatal){'PASS'}else{'FAIL'}
[pscustomobject]@{gui_pid=$GuiPid;pid=$proc.Id;start=$started.ToString('o');exit_code=$proc.ExitCode;timed_out=$timedOut;marker=$marker;fatal_or_error=$fatal;state=$state;vivado=$exe;tcl=$tcl}|ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'process_status.json') -Encoding utf8
if($state -ne 'PASS'){exit 2}
