"""Headless scan/connect probe used for reproducible BLE validation."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from typing import Any

from bleak import BleakClient, BleakScanner


def service_snapshot(client: BleakClient) -> list[dict[str, Any]]:
    services: list[dict[str, Any]] = []
    for service in client.services:
        characteristics: list[dict[str, Any]] = []
        for characteristic in service.characteristics:
            characteristics.append(
                {
                    "uuid": characteristic.uuid,
                    "handle": characteristic.handle,
                    "properties": list(characteristic.properties),
                }
            )
        services.append(
            {
                "uuid": service.uuid,
                "handle": service.handle,
                "characteristics": characteristics,
            }
        )
    return services


async def run_probe(address: str, scan_timeout: float, connect_timeout: float) -> int:
    result: dict[str, Any] = {
        "marker": "BLE_CONSOLE_LIVE_PROBE_FAIL",
        "target_address": address,
    }
    try:
        discovered = await BleakScanner.discover(
            timeout=scan_timeout,
            return_adv=True,
        )
        matches = []
        for device, advertisement in discovered.values():
            if device.address.lower() == address.lower():
                matches.append(
                    {
                        "name": advertisement.local_name or device.name,
                        "address": device.address,
                        "rssi": advertisement.rssi,
                        "advertised_services": list(advertisement.service_uuids or []),
                    }
                )
        result["scan_matches"] = matches

        async with BleakClient(address, timeout=connect_timeout) as client:
            result["connected"] = client.is_connected
            result["mtu_size"] = client.mtu_size
            result["services"] = service_snapshot(client)
            result["marker"] = "BLE_CONSOLE_LIVE_PROBE_PASS"
    except Exception as exc:  # noqa: BLE001 - serialized diagnostic result
        result["error_type"] = type(exc).__name__
        result["error"] = str(exc)

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["marker"] == "BLE_CONSOLE_LIVE_PROBE_PASS" else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", required=True)
    parser.add_argument("--scan-timeout", type=float, default=5.0)
    parser.add_argument("--connect-timeout", type=float, default=15.0)
    args = parser.parse_args()
    return asyncio.run(
        run_probe(args.address, args.scan_timeout, args.connect_timeout)
    )


if __name__ == "__main__":
    sys.exit(main())
