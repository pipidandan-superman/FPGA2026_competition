# UART TXFULL Bit Fix Result

## Root Cause

The first minimal application did not print because `UART1_STATUS_TX_FULL` incorrectly used bit 3 (`0x00000008`).

The Zynq UART1 status register returned:

```text
UART_STATUS=E000102C: 0000000A
```

In this value, bit 3 is `TXEMPTY`, not `TXFULL`. Therefore the application entered the TX FULL wait loop immediately. The target stopped at:

```text
main.c:9
while ((UART1_STATUS & UART1_STATUS_TX_FULL) != 0UL)
```

The BSP defines:

```text
XUARTPS_SR_TXEMPTY = 0x00000008
XUARTPS_SR_TXFULL  = 0x00000010
```

## Fix

Changed:

```c
#define UART1_STATUS_TX_FULL (1UL << 3)
```

to:

```c
#define UART1_STATUS_TX_FULL (1UL << 4)
```

## Build And Run Evidence

```text
[3/3] Linking C executable app_component.elf
   text     data     bss     dec     hex filename
  25600    1420   22952   49972   c334 app_component.elf

Setting PC to Program Start Address 0x00100000
Successfully downloaded app_component.elf
Info: ARM Cortex-A9 MPCore #0 (target 2) Running
```

## Board Status

- UART physical path: PASS, confirmed by direct `XSCT OK` write.
- Raw TX application: fixed and running.
- COM6 confirmation of repeated `UART OK`: PENDING.
