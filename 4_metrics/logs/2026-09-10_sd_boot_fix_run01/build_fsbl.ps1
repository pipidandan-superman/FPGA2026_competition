$ErrorActionPreference = 'Stop'
$buildRoot = Join-Path $PSScriptRoot 'fsbl_build'
$armBin = 'F:/vivado2025/2025.2/Vitis/gnu/aarch32/nt/gcc-arm-none-eabi/bin'
$gcc = Join-Path $armBin 'arm-none-eabi-gcc.exe'
Start-Transcript -Path (Join-Path $PSScriptRoot 'fsbl_build_console.txt')
Push-Location $buildRoot
try {
    $common = @('-mcpu=cortex-a9','-mfpu=vfpv3','-mfloat-abi=hard','-DFSBL_DEBUG_INFO','-O2','-g3','-Iinclude','-I.')
    $objects = @()
    foreach ($source in (Get-ChildItem -File | Where-Object { $_.Extension -in @('.c','.S') } | Sort-Object Name)) {
        $obj = $source.BaseName + '.o'
        Write-Output ('COMPILE: ' + $gcc + ' ' + ($common -join ' ') + ' -c ' + $source.Name + ' -o ' + $obj)
        & $gcc @common -c $source.Name -o $obj
        if ($LASTEXITCODE -ne 0) { throw ('Compile failed: '+$source.Name) }
        $objects += $obj
    }
    $link = @('-mcpu=cortex-a9','-mfpu=vfpv3','-mfloat-abi=hard','-Wl,--build-id=none','-specs=Xilinx.spec','-Wl,--gc-sections','-Wl,-Map=fsbl.map','-Llib','-L.','-Tlscript.ld','-Wl,--start-group','-lxilffs','-lrsa','-lxil','-lgcc','-lc','-Wl,--end-group')
    Write-Output ('LINK: ' + $gcc + ' -o fsbl.elf ' + ($objects -join ' ') + ' ' + ($link -join ' '))
    & $gcc -o fsbl.elf @objects @link
    if ($LASTEXITCODE -ne 0) { throw 'FSBL link failed' }
    & (Join-Path $armBin 'arm-none-eabi-size.exe') fsbl.elf
    & (Join-Path $armBin 'arm-none-eabi-readelf.exe') -h -l fsbl.elf | Tee-Object -FilePath fsbl_readelf.txt
    $strings = & (Join-Path $armBin 'arm-none-eabi-strings.exe') fsbl.elf
    $strings | Out-File fsbl_strings.txt -Encoding utf8
    if (-not ($strings | Select-String -SimpleMatch 'Xilinx First Stage Boot Loader')) { throw 'FSBL banner absent' }
    if (-not ($strings | Select-String -SimpleMatch 'Boot mode is SD')) { throw 'FSBL SD diagnostics absent' }
    Copy-Item fsbl.elf (Join-Path $PSScriptRoot 'candidate/fsbl.elf')
    Get-FileHash fsbl.elf | Format-List
    Write-Output 'FSBL_DEBUG_BUILD_PASS'
} finally { Pop-Location; Stop-Transcript }
