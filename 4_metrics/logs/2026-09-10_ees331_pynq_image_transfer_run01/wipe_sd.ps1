# wipe_sd.ps1 — Wipe the TF card (disk 2) and recreate a single full-capacity FAT32 volume.
# Per user instruction 2026-09-10: stop image flashing, wipe the card.

$ErrorActionPreference = 'Stop'
$log = 'E:\Work\Projects\AMD_proj\FPGA_competition_2026\4_metrics\logs\2026-09-10_ees331_pynq_image_transfer_run01\wipe_sd_20260910.log'
function L($m) { $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m; Write-Host $line; Add-Content -Path $log -Value $line }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$elev = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L "elevated=$elev user=$($id.Name)"

$disk = Get-Disk -Number 2
L ("target: {0} {1:N2}GB readonly={2}" -f $disk.FriendlyName, ($disk.Size / 1GB), $disk.IsReadOnly)
if ($disk.BusType -ne 'USB') { L 'ABORT: disk 2 is not USB'; exit 1 }

L 'Clear-Disk (remove all partitions/data)...'
Clear-Disk -Number 2 -RemoveData -RemoveOEM -Confirm:$false
L 'disk cleared'

L 'New-Partition (full size, drive letter F)...'
$p = New-Partition -DiskNumber 2 -UseMaximumSize -AssignDriveLetter
L ("partition created: letter={0} size={1:N2}GB" -f $p.DriveLetter, ($p.Size / 1GB))

L 'Format-Volume FAT32 (quick)...'
$vol = Format-Volume -Partition $p -FileSystem FAT32 -NewFileSystemLabel 'EES331_SD' -Confirm:$false
L ("formatted: fs={0} label={1}" -f $vol.FileSystem, $vol.FileSystemLabel)

$chk = Get-Disk -Number 2
L ("DONE: disk now {0:N2}GB, partition style {1}, readonly={2}" -f ($chk.Size / 1GB), $chk.PartitionStyle, $chk.IsReadOnly)
exit 0
