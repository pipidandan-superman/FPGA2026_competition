# PL UART bridge board acceptance

User confirmed the new bit was programmed and only LED0 illuminated.
COM4 at 9600 baud, 8N1, no flow control, DTR/RTS disabled.

At 19:05:45, 19:05:47 and 19:05:48 (2026-09-12 UTC+08:00), three separate
AT CRLF requests each returned the exact bytes 4F 4B 0D 0A (OK CRLF).
AT+VERSION returned MLT-BT05-V4.2 at 19:05:50.

Result: PL_UART_BRIDGE_AT_3X_BOARD_PASS. Both wired directions are exercised through
PC USB-UART -> PL -> module command reception -> module response -> PL -> PC USB-UART.
This is not wireless duplex acceptance or a throughput/reliability stress test.
Raw evidence: query.ps1 and serial_capture.json. Port closed after capture.
Previous run01's no-response remains preserved; no claim of exact programmed-bit identity
for that earlier failed attempt. Current success follows the user's corrected download.

Firmware help and PIN results are in ../2026-09-12_pl_uart_pin_query_run03/REPORT.md.
