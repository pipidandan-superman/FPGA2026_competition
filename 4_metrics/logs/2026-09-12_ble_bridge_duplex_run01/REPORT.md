# Wireless / PL-UART bridge: bounded bidirectional board PASS

Result: **BLE_UART_DUPLEX_11_ROUNDS_60S_PASS**.
2026-09-12 21:54:58.765 to 21:56:00.466 UTC+08:00, connected 61.703 seconds.
Target MLT-BT05 6A:C2:D2:F2:1B:5D, paired=false, FFE1, MTU 23.
Serial endpoint COM4, 9600/8N1/no flow control, DTR/RTS false.

## Actual checks

- Verified remote device name with an uncached read, then enabled FFE1 notifications.
- BLE write-with-response -> module UART -> PL bridge -> COM4: 11 rounds, 166 bytes exact.
- COM4 -> PL bridge -> module UART -> BLE notification: 11 rounds, 166 bytes exact.
- Round 0: BLE payload 55 AA 31 32 00 FF; reverse AA 55 32 31 FF 00.
- Rounds 1..10: independently generated 16-byte payloads per direction with round indexes,
  approximately 5-second pauses between rounds. Complete payloads retained in test_events.json.
- Notifications are aggregated as a byte stream, not assumed to equal UART frame boundaries.
- No missing, mismatching, duplicated or trailing bytes observed in the checked windows.
- Final uncached remote-name read succeeded; connection was then intentionally closed.
- Only disconnect event has expected=true; serial helper exited 0 and closed COM4.

This is paced **bidirectional** traffic, not a simultaneous full-duplex stress test.
Total observed payload 332 bytes is not a throughput benchmark or long-duration reliability
claim. No mechanical-arm interface, hardware control command, autonomous PL byte parser,
authentication security, or arbitrary BLE-module compatibility is proven here.

## Reproduction

Run test_duplex.py using the existing BLE console build venv. serial_rpc.ps1 uses the
Windows .NET SerialPort API and no new dependency installation. It holds COM4 during the
run. Do not run another serial terminal or a second active BLE client simultaneously.

Raw evidence: test_events.json, bleak_debug.log, test_duplex.py, serial_rpc.ps1.
Source/evidence hashes: delivery_hashes.json. Project skill path audit: skill_path_audit.json.
No RTL, bitstream, module configuration or GUI executable was modified during this test.

## Connection state and comparison

Only the target's Windows pairing was removed with user approval in the preceding
ble_unpaired_bridge_run01. That record can be recreated by pairing, but the validated
workflow is direct unpaired GATT connection through the console, not Windows PIN pairing.
This A/B comparison associates the earlier short connections with pairing/security state,
without identifying the precise Windows/module defect or proving encrypted pairing is
impossible. No other Bluetooth devices were removed or reconfigured.

## Next gate

Keep the current bit and module parameters. Reconnect through the BLE console, subscribe
FFE1, and use an independent COM4 serial terminal for visibility; no ILA is required for
these byte checks. Future long-duration/reconnection tests and byte-aware PL UART/FIFO
controller design should be separate stages before AXI-Lite/BRAM or mechanical-arm control.
