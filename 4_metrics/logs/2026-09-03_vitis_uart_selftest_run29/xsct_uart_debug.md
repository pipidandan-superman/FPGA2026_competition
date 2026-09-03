# XSCT Target And UART Debug Evidence
- Initial JTAG target list: APU; Cortex-A9 #0 Running; Cortex-A9 #1 Running; xc7z020 present.
- Direct UART/app attempt: `run_uart_direct_and_app.tcl` sourced PS7 init, wrote `XSCT OK` bytes directly to UART1 TX FIFO, downloaded the latest ELF, and resumed CPU0. The XSCT console completed without a Tcl error.
- Follow-up target check after the direct attempt: `DAP (APB AP transaction error, DAP status 0x30000021)`.
- Required reset: power-cycle the EES-331 board before another Run or XSCT download.
- COM inventory: `COM1` and `COM6`; `COM6` is `VCP1`. No COM-port access-denied error was present in the latest screenshot.
- Next acceptance sequence: power-cycle board, keep one COM6 terminal at 115200-8-N1 open and connected, click Run once, and check for header plus three heartbeat messages.
