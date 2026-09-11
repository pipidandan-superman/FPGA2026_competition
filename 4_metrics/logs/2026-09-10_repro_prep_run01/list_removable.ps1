Get-Disk | Select-Object Number, FriendlyName, @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}}, BusType, PartitionStyle | Format-Table -AutoSize
Get-Volume | Select-Object DriveLetter, FileSystemLabel, DriveType, @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}} | Format-Table -AutoSize
