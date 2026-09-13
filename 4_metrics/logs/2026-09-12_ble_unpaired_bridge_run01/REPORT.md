# Authorized pairing removal and unpaired comparison

User explicitly approved removal of only MLT-BT05's Windows pairing record.
At 21:52:59 UTC+08:00, native API verified name MLT-BT05 and address
6A:C2:D2:F2:1B:5D; before paired=true, protection=3. unpair_async returned UNPAIRED.
This time a pairing record was actually removed (unlike the earlier ALREADY_UNPAIRED run).
Other devices and module configuration were not changed. The record can be recreated
by pairing again, but doing so is not recommended during this diagnostic comparison.

Then the same connect_gate.py used in the failed paired test was run in a new directory.
At 21:53:25 it reported paired=false. Three uncached remote name reads returned MLT-BT05
at 21:53:25, 21:53:27 and 21:53:30; connection held through 21:53:32, then the context
manager intentionally disconnected. Result: BLE_READ_HOLD_GATE_PASS. No data writes.

Evidence: unpair_target.py, unpair_events.jsonl, connect_gate.py, gate_events.json,
bleak_debug.log. The paired-before / unpaired-after comparison strongly implicates
pairing/security state in this setup's short connections, but does not identify the exact
firmware, bonding-key, authentication, or Windows defect. Do not claim Bluetooth security
was bypassed or that pairing will always fail. The module accepts this unpaired GATT access.

Next: independent bidirectional payload checks in ../2026-09-12_ble_bridge_duplex_run01/.
