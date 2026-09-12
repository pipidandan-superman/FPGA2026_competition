$ErrorActionPreference='Stop'
$port=[IO.Ports.SerialPort]::new('COM4',9600,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
$port.Handshake=[IO.Ports.Handshake]::None
$port.DtrEnable=$false
$port.RtsEnable=$false
$port.WriteTimeout=1000
try {
    $port.Open()
    [Console]::WriteLine('{"ready":true,"port":"COM4","baud":9600}')
    while($null -ne ($line=[Console]::ReadLine())) {
        $cmd=$line | ConvertFrom-Json
        if($cmd.op -eq 'close'){break}
        if($cmd.op -eq 'write') {
            $bytes=[byte[]]@(for($i=0;$i -lt $cmd.hex.Length;$i+=2){[Convert]::ToByte($cmd.hex.Substring($i,2),16)})
            $port.Write($bytes,0,$bytes.Length)
            [Console]::WriteLine(('{"written":'+$bytes.Length+'}'))
        } elseif($cmd.op -eq 'read') {
            $received=[Collections.Generic.List[byte]]::new()
            $timer=[Diagnostics.Stopwatch]::StartNew()
            while($timer.ElapsedMilliseconds -lt $cmd.ms){
                while($port.BytesToRead -gt 0){$received.Add([byte]$port.ReadByte())}
                Start-Sleep -Milliseconds 5
            }
            $hex=[BitConverter]::ToString($received.ToArray()).Replace('-','')
            [Console]::WriteLine(('{"hex":"'+$hex+'"}'))
        } else {throw 'Unsupported operation'}
    }
} catch {
    [Console]::WriteLine((@{error=$_.Exception.Message} | ConvertTo-Json -Compress))
    exit 1
} finally {
    if($port.IsOpen){$port.Close()}
    $port.Dispose()
}
