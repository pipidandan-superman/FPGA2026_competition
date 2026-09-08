Title: feat: EES-331 PS ethernet UDP loopback bring-up app

## Why
EES-331 PS-only Ethernet test project reaches its first board-proven milestone: Zynq PS (ENET0/88E1518) boots a staged Vitis app and the PC↔board UDP loopback echo is verified at 1 Gbps.

## Scope
- `2_fpga/2_eth_onlytest_zynq7020/vitis/eth_test_app/src/`: authored `main.c`, `udp_echo.c/h`, `platform_config.h` + AMD lwip_echo_server template `platform.c/h`, `platform_zynq.c`, build config (`CMakeLists.txt`, `lscript.ld`, `app.yaml`, `UserConfig.cmake`, `vitis-comp.json`), vitis `.gitignore`.
- `4_metrics/logs/2026-09-08_eth_app_uart_udp_echo_code_run01/`: delivery report, code + ELF SHA-256, failure screenshot (port 8080), PASS screenshot (port 5000).
- `4_metrics/logs/2026-09-08_eth_zynq_psw_check_mineru_run01/ZYNQ_PS_CONFIG_CHECK_REPORT.md` (single declared report; MinerU raw output stays local).
- `7_logs/2026-09-08/` four engineering-log files.

## Verified
- `ETH_ZYNQ_PS_CONFIG_CHECK_PASS`: PS config vs EES-331 manual, 8/8.
- `APP_BUILD_PASS`: ELF 832,028 bytes, SHA-256 B2B2CCA9...618E25.
- `UDP_LOOPBACK_PASS`: NetAssist bound 192.168.240.2:5000, board 192.168.240.10:5000; counters 7/7 packets, RX 95 B = TX 95 B; PHY autonegotiated 1000 Mbps; screenshot SHA-256 776F4B8A...04518.

## Not verified / boundaries
- Full UART capture including periodic HEARTBEAT lines still to be archived.
- First failure (remote port 8080 vs board 5000) recorded as history in the logs.
- No camera-frame transport yet; frozen `2_fpga/0_diaplay_test` baseline untouched; no BIT/XSA/ELF artifacts uploaded.

## Rollback
Revert commits `7720731`, `d684c44` and this correction commit; nothing else depends on the new paths.
