# New bridge wireless test: stopped at connection gate

Current result: **BLE_READ_HOLD_GATE_FAIL**; bidirectional wireless data testing NOT RUN.

The user asked to test an apparently connected link. GUI log shows connected at
21:46:31.318, services at 21:46:31.320, and unexpected disconnect at 21:46:31.541:
only 223 ms between application connect and disconnect. Preserved in gui_connection_events.jsonl.

At 21:48:35 target advertisement was observed. An independent Bleak connection with
uncached services, pair=False (no pairing operation), timed out after 15 s. Underlying
WinRT repeatedly reported ACTIVE then CLOSED; first interval was 21:48:35.743 to
21:48:36.024 (281 ms), and service queries reported unreachable. Counts and complete raw
logs are retained. No remote-read gate passed and no application GATT payload was sent.
Service trees or Windows 'connected' labels alone are not accepted as transfer evidence.

After that attempt completed, the wired control check succeeded at COM4/9600/8N1:

| Query | Actual reply |
|---|---|
| AT | OK |
| AT+TYPE | +TYPE=0 |
| AT+ROLE | +ROLE=0 |
| AT+BAUD | +BAUD=4 |
| AT+VERSION | MLT-BT05-V4.2 |

These are raw configuration values; numeric meanings are not inferred without matching
firmware documentation. No setters, factory reset, power cycle, FPGA reprogramming,
adapter reset, unpair operation, or PIN changes were performed. COM4 was closed afterward.

Conclusion: wired command-response path currently works, but the wireless session does
not stay usable long enough to test data. This does not establish the root cause of
wireless instability, nor rule out RF/power/firmware/Windows causes. Previous user report
of PIN connection success was immediately qualified by '马上就断了'; stable connection
acceptance is explicitly revoked. PIN remains the value previously read twice.

Next bounded comparison, only with user approval: disconnect the test application and
remove only MLT-BT05's Windows pairing, then repeat unpaired GATT remote-read/hold tests.
Prior unpaired success motivates the comparison, but does not prove it will fix this run.
Preserve other Bluetooth devices and module settings. If stable, verify each wireless
direction against COM4 with fixed bytes before any sustained reliability test.
