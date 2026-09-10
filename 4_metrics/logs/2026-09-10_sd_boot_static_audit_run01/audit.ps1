$ErrorActionPreference = 'Stop'
$auditRoot = $PSScriptRoot
$priorRun = 'E:/competition/4_metrics/logs/2026-09-10_pynq_fsbl_rebuild_run03'
$fsblRoot = 'E:/competition/2_fpga/3_pynq_test/vitis/ws_fsbl/pynq_plat/zynq_fsbl'
$armTools = 'F:/vivado2025/2025.2/Vitis/gnu/aarch32/nt/gcc-arm-none-eabi/bin'
Start-Transcript -Path (Join-Path $auditRoot 'audit_console.txt')
try {
    Write-Output 'Scope: static audit only; no board access, SD writes, source edits, or rebuild.'
    foreach ($name in @('BOOT_MIN.BIN', 'BOOT_pynq_z2_orig.BIN', 'fsbl.elf', 'fsbl_only.bif', 'gen_fsbl_console.log')) {
        Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $priorRun $name) | Format-List
    }
    foreach ($name in @('fsbl_debug.h', 'Makefile', 'main.c', 'ps7_init.c', 'fsbl.elf')) {
        Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $fsblRoot $name) | Format-List
    }
    foreach ($name in @('BOOT_MIN.BIN', 'BOOT_pynq_z2_orig.BIN')) {
        Write-Output "BOOT_HEADER $name"
        $auditBytes = [IO.File]::ReadAllBytes((Join-Path $priorRun $name))
        foreach ($offset in @(0x20, 0x24, 0x28, 0x2c, 0x30, 0x34, 0x38, 0x3c, 0x40, 0x44, 0x48, 0x98, 0x9c)) {
            '{0:X4}: {1:X8}' -f $offset, [BitConverter]::ToUInt32($auditBytes, $offset)
        }
    }
    Write-Output 'BIF_CONTENT'
    Get-Content (Join-Path $priorRun 'fsbl_only.bif')
    Write-Output 'FSBL_DEBUG_HEADER'
    Get-Content (Join-Path $fsblRoot 'fsbl_debug.h')
    Write-Output 'FSBL_MAKEFILE'
    Get-Content (Join-Path $fsblRoot 'Makefile')
    $auditStrings = @(& (Join-Path $armTools 'arm-none-eabi-strings.exe') (Join-Path $priorRun 'fsbl.elf'))
    if ($LASTEXITCODE -ne 0) { throw 'strings failed' }
    $auditStrings | Out-File (Join-Path $auditRoot 'fsbl_strings.txt') -Encoding utf8
    foreach ($needle in @('Xilinx First Stage Boot Loader', 'Boot mode is SD', 'PS7_INIT_FAIL', 'FSBL Status')) {
        $found = @($auditStrings | Select-String -SimpleMatch $needle).Count
        Write-Output "STRING_MATCH_COUNT [$needle] = $found"
    }
    & (Join-Path $armTools 'arm-none-eabi-readelf.exe') -h -l (Join-Path $priorRun 'fsbl.elf') |
        Tee-Object -FilePath (Join-Path $auditRoot 'fsbl_readelf.txt')
    if ($LASTEXITCODE -ne 0) { throw 'readelf failed' }
    Write-Output 'SOURCE_ORDER_AND_UART'
    Select-String -Path (Join-Path $fsblRoot 'main.c') -Pattern 'Status = ps7_init', 'First Stage Boot Loader', 'Status = DDRInitCheck', 'Status = InitSD'
    Select-String -Path (Join-Path $fsblRoot 'zynq_fsbl_bsp/ps7_cortexa9_0/include/xparameters.h') -Pattern 'STDOUT_BASEADDRESS', 'XPAR_XSDPS_0_HAS_CD'
    Write-Output 'RESULT: STATIC_BOOT_IMAGE_DEFECT_CONFIRMED; BOARD_BOOT_STATUS_NOT_RETESTED'
} finally {
    Stop-Transcript
}
