# Vitis UART No-Output DDR Root Cause Record

## Conclusion

- User confirmed that the Zynq DDR device type/model had not been selected correctly for the EES-331 board.
- User has modified the DDR configuration.
- This can explain the observed no-output symptom: FSBL or application execution may become unstable after DDR access, causing the debug session to disconnect and the automatically opened COM6 terminal to close.
- This record does **not** claim that the UART board test has passed.

## Required Revalidation

1. Validate the BD and regenerate the Vivado design.
2. Run implementation/bitstream if the generated design changes.
3. Export an updated XSA.
4. Update the Vitis platform from the new XSA and regenerate BSP/FSBL.
5. Rebuild `app_component`.
6. Power-cycle the board.
7. Open exactly one COM6 terminal at 115200-8-N1 and rerun the UART self-test.

## Acceptance

UART board test PASS requires all of the following:

- COM6 remains open and connected.
- UART header and three heartbeat messages are visible.
- Typed characters are echoed.
- The debug session remains connected through the RX echo test.
