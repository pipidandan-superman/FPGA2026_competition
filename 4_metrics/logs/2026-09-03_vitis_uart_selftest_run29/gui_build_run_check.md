# Vitis GUI Build And Run Check
- GUI build result: PASS. `app_component/build/app_component.elf` was generated at 2026-09-03 21:47.
- ELF file size: 119548 bytes; program size: text=28517, data=1428, bss=22996, total=52941.
- BSP UART check: `STDIN_BASEADDRESS` and stdout target are UART1 at `0xE0001000`.
- GUI run log: 21:47:42 build finished; 21:47:56 and 21:48:47 run launches started using the latest ELF; no error/failure entry was found.
- Serial interpretation: if COM6 was opened after Run, the three one-second heartbeat messages are already missed and the program is waiting in RX echo mode.
- Required retry sequence: keep the COM6 terminal open, press Run again, and output should begin immediately; after three heartbeats, type characters to verify echo.
