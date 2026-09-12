$ErrorActionPreference = 'Stop'
$run = $PSScriptRoot
$board = 'E:\competition\4_metrics\logs\2026-09-12_ble_console_v11_board_run02'
$old = Get-Content -LiteralPath (Join-Path $run 'old_exe_hash.json') -Raw | ConvertFrom-Json
$oldNow = Get-FileHash 'E:\competition\8_tools\EES331_BLE_Console_v1.0\EES331_BLE_Console.exe'
if ($old.Hash -ne $oldNow.Hash) { throw 'Old EXE changed' }
$events = Get-Content -LiteralPath (Join-Path $board 'worker_board_events.json') -Raw | ConvertFrom-Json
$result = @($events | Where-Object event -eq 'result')
if ($result.Count -ne 1 -or $result[0].marker -ne 'BLE_CONSOLE_V11_WORKER_BOARD_PASS') { throw 'Worker test failed' }
if ($result[0].rounds -ne 3 -or $result[0].ready_hold_s -lt 60 -or $result[0].bytes_each_direction -ne 18) { throw 'Worker result bounds' }
if (@($events | Where-Object { $_.event -eq 'pairing_status' -and -not $_.paired }).Count -ne 2) { throw 'Pairing gate evidence' }
if (@($events | Where-Object { $_.event -eq 'round_pass' }).Count -ne 3) { throw 'Round count' }
$gui = Get-Content -LiteralPath (Join-Path $board 'exe_session_snapshot.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
if (@($gui | Where-Object { $_.event -eq 'connected' -and $_.data.verified -and $_.data.auto_notify }).Count -ne 1) { throw 'EXE ready missing' }
if (@($gui | Where-Object { $_.event -eq 'write_complete' -and $_.data.payload -eq '55AA3132' }).Count -ne 1) { throw 'EXE TX missing' }
if (@($gui | Where-Object { $_.event -eq 'notification' -and $_.data.payload -eq 'AA553231' }).Count -ne 1) { throw 'EXE notification missing' }
$serial = Get-Content -LiteralPath (Join-Path $board 'exe_serial_console.log') | ForEach-Object { $_ | ConvertFrom-Json }
if (@($serial | Where-Object { $_.event -eq 'serial_received' -and $_.actual -eq '55AA3132' }).Count -ne 1) { throw 'Serial comparison missing' }
$release = 'E:\competition\8_tools\EES331_BLE_Console_v1.1'
$missing = @()
foreach ($line in Get-Content (Join-Path $run 'release_sha256.txt')) {
    if ($line -match '^([A-Fa-f0-9]{64})  (.+)$') {
        $expected = $Matches[1]
        $relative = $Matches[2]
        if ((Get-FileHash -LiteralPath (Join-Path $release $relative)).Hash -ne $expected) { $missing += $relative }
    }
}
if ($missing.Count) { throw "Release manifest mismatch: $missing" }
Get-ChildItem 'E:\competition\3_host\ble_console' -Recurse -File |
    Where-Object { $_.Extension -in '.py', '.ps1', '.json', '.md', '.in' } |
    Get-FileHash | ConvertTo-Json -Depth 3 |
    Set-Content -LiteralPath (Join-Path $run 'source_final_hashes.json') -Encoding utf8
$receipt = [ordered]@{
    marker='BLE_CONSOLE_V11_DELIVERY_PASS'
    timestamp=(Get-Date -Format o)
    old_exe_unchanged=$true
    offline_tests=31
    worker_rounds=3
    worker_hold_s=$result[0].ready_hold_s
    worker_bytes_each_direction=18
    frozen_exe_gui_duplex=$true
    exe=(Get-FileHash -LiteralPath (Join-Path $release 'EES331_BLE_Console.exe')).Hash
    formal_long_term_acceptance=$false
}
$receipt | ConvertTo-Json | Tee-Object -FilePath (Join-Path $run 'delivery_verification.json')
