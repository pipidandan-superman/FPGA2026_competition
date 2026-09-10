$ErrorActionPreference = 'Stop'
$auditRoot = $PSScriptRoot
$priorRun = 'E:/competition/4_metrics/logs/2026-09-10_pynq_fsbl_rebuild_run03'
Start-Transcript -Path (Join-Path $auditRoot 'console.txt')
try {
    Get-Date -Format o
    Write-Output 'Read-only inspection of G:; evidence written only under audit directory.'
    Get-Volume -DriveLetter G | Format-List DriveLetter,FileSystemLabel,FileSystem,DriveType,HealthStatus,Size,SizeRemaining
    $sdPartition = Get-Partition -DriveLetter G
    Get-Disk -Number $sdPartition.DiskNumber | Format-List Number,FriendlyName,BusType,PartitionStyle,Size,HealthStatus,OperationalStatus
    Get-Partition -DiskNumber $sdPartition.DiskNumber | Format-Table PartitionNumber,DriveLetter,Type,Size,Offset -AutoSize
    Get-ChildItem -LiteralPath 'G:/' -Force | Format-Table Name,Length,LastWriteTime,Attributes -AutoSize
    $fileChecks = foreach ($sdFile in (Get-ChildItem -LiteralPath 'G:/' -File)) {
        [pscustomobject]@{Name=$sdFile.Name;Length=$sdFile.Length;SHA256=(Get-FileHash -LiteralPath $sdFile.FullName -Algorithm SHA256).Hash}
    }
    $fileChecks | ConvertTo-Json | Out-File (Join-Path $auditRoot 'file_hashes.json') -Encoding utf8
    $fileChecks | Format-List
    $sdBootBytes = [IO.File]::ReadAllBytes('G:/BOOT.BIN')
    $knownBootBytes = [IO.File]::ReadAllBytes((Join-Path $priorRun 'BOOT_MIN.BIN'))
    $same = $sdBootBytes.Length -eq $knownBootBytes.Length
    if ($same) {
        for ($i=0; $i -lt $sdBootBytes.Length; $i++) {
            if ($sdBootBytes[$i] -ne $knownBootBytes[$i]) { $same=$false; break }
        }
    }
    Write-Output "BYTE_FOR_BYTE_EQUALS_RUN03_BOOT_MIN=$same"
    foreach ($offset in @(0x20,0x24,0x30,0x34,0x38,0x3c,0x40,0x48,0x98,0x9c)) {
        'BOOT_HEADER 0x{0:X2}=0x{1:X8}' -f $offset,[BitConverter]::ToUInt32($sdBootBytes,$offset)
    }
    $asciiBoot = [Text.Encoding]::ASCII.GetString($sdBootBytes)
    foreach ($needle in @('Xilinx First Stage Boot Loader','Boot mode is SD','U-Boot')) {
        Write-Output "BOOT_STRING_PRESENT [$needle]=$($asciiBoot.Contains($needle))"
    }
    Write-Output 'REVISION_CONTENT'
    Get-Content -LiteralPath 'G:/REVISION'
    foreach ($name in @('image.ub','boot.scr')) {
        $stream = [IO.File]::OpenRead("G:/$name")
        try {
            $header = New-Object byte[] 64
            $count = $stream.Read($header,0,$header.Length)
            Write-Output "$name first_64_bytes=$([BitConverter]::ToString($header,0,$count))"
        } finally { $stream.Dispose() }
    }
    Write-Output 'RESULT=SD_CARD_G_BOOT_DEFECT_CONFIRMED'
    Write-Output 'No filesystem repair, card write, eject, board access, or rebuild performed. Linux partition contents and complete card media were not validated.'
} finally {
    Stop-Transcript
}
