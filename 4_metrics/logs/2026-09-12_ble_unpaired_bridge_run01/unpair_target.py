"""Remove only the in-scope MLT-BT05 pairing for a controlled GATT comparison."""
import asyncio
import datetime
import json

from winrt.windows.devices.bluetooth import BluetoothLEDevice
from winrt.windows.devices.enumeration import DeviceUnpairingResultStatus

ADDRESS = int("6AC2D2F21B5D", 16)


def emit(event, **values):
    print(json.dumps({"timestamp": datetime.datetime.now().astimezone().isoformat(),
                      "event": event, **values}, ensure_ascii=False), flush=True)


async def main():
    device = await BluetoothLEDevice.from_bluetooth_address_async(ADDRESS)
    if device is None:
        raise RuntimeError("Target device unavailable; no changes made")
    try:
        if device.bluetooth_address != ADDRESS or device.name != "MLT-BT05":
            raise RuntimeError("Target identity mismatch; no changes made")
        pairing = device.device_information.pairing
        emit("before", name=device.name, address="6A:C2:D2:F2:1B:5D",
             paired=pairing.is_paired, protection=int(pairing.protection_level))
        result = await asyncio.wait_for(pairing.unpair_async(), timeout=15)
        emit("unpair_result", name=result.status.name, code=int(result.status))
        if result.status not in (DeviceUnpairingResultStatus.UNPAIRED,
                                  DeviceUnpairingResultStatus.ALREADY_UNPAIRED):
            return 1
        return 0
    finally:
        device.close()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
