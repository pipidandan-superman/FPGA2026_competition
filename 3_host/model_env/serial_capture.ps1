param(
    [string]$Port = 'COM4',
    [Parameter(Mandatory=$true)][string]$Output,
    [double]$Seconds = 300
)
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($Output)
if (-not $target.StartsWith('E:\competition\4_metrics\logs\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Serial evidence must be under 4_metrics/logs'
}
if (Test-Path -LiteralPath $target) {throw 'Capture output already exists'}
$stream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
$serial = [IO.Ports.SerialPort]::new($Port,9600,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
$serial.Handshake = [IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.ReadTimeout = 100
$buffer = New-Object byte[] 4096
$clock = [Diagnostics.Stopwatch]::StartNew()
$count = 0
try {
    $serial.Open()
    [Console]::WriteLine('SERIAL_CAPTURE_READY '+$Port)
    while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
        try { $length = $serial.Read($buffer,0,$buffer.Length) }
        catch [TimeoutException] {continue}
        if ($length -gt 0) {
            $stream.Write($buffer,0,$length)
            $stream.Flush()
            $count += $length
            [Console]::WriteLine(('RX {0:F6} {1}' -f $clock.Elapsed.TotalSeconds,[BitConverter]::ToString($buffer,0,$length)))
        }
    }
    [Console]::WriteLine('SERIAL_CAPTURE_COMPLETE bytes='+$count)
} finally {
    if ($serial.IsOpen) {$serial.Close()}
    $serial.Dispose()
    $stream.Dispose()
}
