$ErrorActionPreference = 'Stop'
$port = [System.IO.Ports.SerialPort]::new('COM4', 9600, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$port.Handshake = [System.IO.Ports.Handshake]::None
$port.ReadTimeout = 200
$port.WriteTimeout = 1000
$received = [System.Collections.Generic.List[byte]]::new()
try {
    $port.Open()
    Write-Output '{"event":"serial_ready","port":"COM4","baud":9600}'
    $deadline = [DateTime]::UtcNow.AddSeconds(35)
    while ([DateTime]::UtcNow -lt $deadline -and $received.Count -lt 4) {
        try { $received.Add([byte]$port.ReadByte()) } catch [System.TimeoutException] {}
    }
    $hex = [BitConverter]::ToString($received.ToArray()).Replace('-', '')
    @{event='serial_received'; expected='55AA3132'; actual=$hex} | ConvertTo-Json -Compress
    if ($hex -ne '55AA3132') { throw 'GUI to COM4 mismatch or timeout' }
    $response = [byte[]](0xAA, 0x55, 0x32, 0x31)
    $port.Write($response, 0, $response.Length)
    Write-Output '{"event":"serial_written","hex":"AA553231","note":"verify EXE notification separately"}'
} finally {
    if ($port.IsOpen) { $port.Close() }
    $port.Dispose()
}
