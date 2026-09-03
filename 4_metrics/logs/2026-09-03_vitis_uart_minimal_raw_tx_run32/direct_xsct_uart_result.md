# Direct XSCT UART1 Test Result

## Purpose

Bypass the Vitis Run flow and verify the UART path in two stages:

1. Directly initialize PS7 and write `XSCT OK\r\n` to UART1 TX FIFO.
2. Download and run the already-built minimal raw TX application.

## PS7 Register Evidence

```text
MIO48_CTRL=F80007C0: 000012E0
MIO49_CTRL=F80007C4: 000012E1
UART_CTRL=E0001000:  00000114
UART_MODE=E0001004:  00000020
UART_BAUDGEN=E0001018: 0000007C
UART_BAUDDIV=E0001034: 00000006
UART_STATUS=E000102C: 0000000A
DIRECT_UART1_WRITE_DONE
```

These values confirm that the generated PS7 configuration selects UART1 on MIO48/49 and configures the 115200 baud divisors.

## Application Download Evidence

```text
section, .text: 0x00100000 - 0x0010238f
Setting PC to Program Start Address 0x00100000
Successfully downloaded app_component.elf
Info: ARM Cortex-A9 MPCore #0 (target 2) Running
```

## Expected COM6 Output

```text
XSCT OK
UART OK
UART OK
```
The first line should appear immediately after the direct FIFO writes. The remaining lines should repeat once the minimal application starts.
