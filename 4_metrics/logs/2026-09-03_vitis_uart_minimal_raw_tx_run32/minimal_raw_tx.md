# Vitis UART Minimal Raw TX Test

## Change

- Replaced `app_component/src/main.c` with a minimal UART-only test.
- Removed `xil_printf`, `usleep`, `inbyte`, `outbyte`, BSP headers, heartbeat logic, and RX echo.
- Writes the fixed string `UART OK\r\n` directly to PS UART1 TX FIFO at `0xE0001030`.
- Checks only UART1 status register `0xE000102C`, TX FULL bit 3.
- Repeats continuously with a software delay so a terminal opened later can still see output.

## Status

- SOURCE UPDATE: COMPLETE
- BUILD: PASS

## Build Evidence

```text
[3/3] Linking C executable app_component.elf
   text     data     bss     dec     hex filename
  25600    1420   22952   49972   c334 app_component.elf
```

- BOARD TEST: PENDING

## Test Conditions

- COM6 terminal: `115200-8-N1`
- Only one serial terminal may own COM6.
- Expected text repeats:

```text
UART OK
```

If this still produces no output, the remaining issue is likely UART MIO/pin mapping, UART clock/baud configuration, hardware initialization, wrong COM port, or board hardware path—not application print formatting.
