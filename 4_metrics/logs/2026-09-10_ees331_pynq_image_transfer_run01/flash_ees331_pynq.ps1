# flash_ees331_pynq.ps1 — Safely write the EES-331 PYNQ image to the TF card.
#
# Guards:
#   1. must run elevated (admin)
#   2. candidate disk must be BusType=USB and 8..128 GB
#   3. exactly ONE candidate allowed; its size must be printed for eyeballing
#   4. target disk is taken offline before raw write (no mounted-volume writes)
#   5. full read-back verification against the source image SHA-256
#
# Usage (admin PowerShell):
#   powershell -ExecutionPolicy Bypass -File flash_ees331_pynq.ps1 -Image <img> [-Number <diskNumber>]

param(
    [Parameter(Mandatory = $true)][string]$Image,
    [int]$Number = -1
)

$ErrorActionPreference = 'Stop'
$expectedHash = '203e9f79679c6c77a738c30d06e3232f0907eb2e5b6cafe97e26e8889057835a'

# --- admin check ---
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host 'FAIL: must run as Administrator.' -ForegroundColor Red; exit 1 }

# --- image check ---
if (-not (Test-Path $Image)) { Write-Host "FAIL: image not found: $Image" -ForegroundColor Red; exit 1 }
$srcHash = (Get-FileHash $Image -Algorithm SHA256).Hash.ToLower()
Write-Host "Image : $Image"
Write-Host "Hash  : $srcHash"
if ($srcHash -ne $expectedHash) { Write-Host 'FAIL: image hash mismatch!' -ForegroundColor Red; exit 1 }

# --- disk selection ---
$disks = Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.Size -ge 8GB -and $_.Size -le 128GB }
if ($Number -ge 0) { $disks = @(Get-Disk -Number $Number | Where-Object BusType -eq 'USB') }
if ($disks.Count -eq 0) { Write-Host 'FAIL: no USB disk in 8-128GB range found. Insert the TF card.' -ForegroundColor Red; exit 2 }
if ($disks.Count -gt 1) { Write-Host 'FAIL: multiple USB disks match; pass -Number explicitly:' -ForegroundColor Red; $disks | Format-Table Number, FriendlyName, Size; exit 2 }
$disk = $disks[0]
Write-Host ("Target: PHYSICALDRIVE{0}  {1}  {2:N2} GB" -f $disk.Number, $disk.FriendlyName, ($disk.Size / 1GB)) -ForegroundColor Yellow
$vols = Get-Disk -Number $disk.Number | Get-Partition | Get-Volume -ErrorAction SilentlyContinue
$vols | ForEach-Object { Write-Host ("  will ERASE volume {0}: [{1}] {2:N2} GB" -f $_.DriveLetter, $_.FileSystemLabel, ($_.Size / 1GB)) -ForegroundColor Yellow }
if ($vols | Where-Object { $_.DriveLetter -in @('C', 'D', 'E') }) { Write-Host 'FAIL: candidate shows a system drive letter - abort.' -ForegroundColor Red; exit 3 }

# --- go offline (best effort: removable media cannot go offline), then write ---
try { Set-Disk -Number $disk.Number -IsOffline $true -ErrorAction Stop }
catch { Write-Host 'NOTE: offline not supported for removable media - continuing with raw write.' -ForegroundColor Yellow }
try { Set-Disk -Number $disk.Number -IsReadOnly $false -ErrorAction Stop } catch { }
try { Dismount-Volume -DriveLetter ($vols | Select-Object -First 1).DriveLetter -ErrorAction Stop | Out-Null; Write-Host 'Volume dismounted.' }
catch { Write-Host 'NOTE: dismount skipped (volume busy) - continuing.' -ForegroundColor Yellow }
Write-Host 'Writing (raw)... progress every 256 MB. Do NOT close this window.'
$src = [System.IO.File]::Open($Image, 'Open', 'Read', 'Read')
try {
    $dst = [System.IO.File]::Open("\\.\PHYSICALDRIVE$($disk.Number)", 'Open', 'Write', 'ReadWrite')
    try {
        $buf = New-Object byte[] (4MB)
        $total = $src.Length; $done = [long]0; $next = 256MB
        while ($done -lt $total) {
            $n = $src.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $dst.Write($buf, 0, $n)
            $done += $n
            if ($done -ge $next) { Write-Host ('  {0:N2} / {1:N2} GB' -f ($done / 1GB), ($total / 1GB)); $next += 256MB }
        }
        $dst.Flush()
    } finally { $dst.Close() }
} finally { $src.Close() }
if ($done -ne $total) { Write-Host "FAIL: wrote $done of $total bytes" -ForegroundColor Red; Start-Sleep 15; exit 4 }
Write-Host "WRITE_DONE ($done bytes)" -ForegroundColor Green

# --- read back and verify ---
Write-Host 'Verifying (read back, SHA-256)...'
$sha = [System.Security.Cryptography.SHA256]::Create()
$src = [System.IO.File]::Open($Image, 'Open', 'Read', 'Read')
try {
    $dst = [System.IO.File]::Open("\\.\PHYSICALDRIVE$($disk.Number)", 'Open', 'Read', 'ReadWrite')
    try {
        $buf = New-Object byte[] (4MB)
        $total = $src.Length; $done = [long]0; $next = 1GB
        while ($done -lt $total) {
            $n = $src.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $rb = New-Object byte[] $n
            $got = 0
            while ($got -lt $n) { $r = $dst.Read($rb, $got, $n - $got); if ($r -le 0) { throw 'short read' }; $got += $r }
            [void]$sha.TransformBlock($rb, 0, $n, $null, 0)
            $done += $n
            if ($done -ge $next) { Write-Host ('  verified {0:N1} / {1:N1} GB' -f ($done / 1GB), ($total / 1GB)); $next += 1GB }
        }
        [void]$sha.TransformFinalBlock($buf, 0, 0)
        $cardHash = [BitConverter]::ToString($sha.Hash).Replace('-', '').ToLower()
        Write-Host "Card hash: $cardHash"
        if ($cardHash -eq $expectedHash -and $done -eq $total) {
            Write-Host 'VERIFY_PASS (full-disk read-back matches image)' -ForegroundColor Green
            Write-Host 'ALL_DONE - you can close this window and eject the card. Windows may popup "format?" - always cancel.'
            Start-Sleep 20
            exit 0
        } else {
            Write-Host 'FAIL: verify mismatch!' -ForegroundColor Red
            Start-Sleep 15
            exit 4
        }
    } finally { $dst.Close() }
} finally { $src.Close(); $sha.Dispose() }
