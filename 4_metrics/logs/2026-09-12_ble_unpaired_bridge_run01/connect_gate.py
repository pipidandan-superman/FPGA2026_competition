"""Read-only gate before new-bridge data tests; preserve pairing/configuration."""
import asyncio
import datetime
import json
import logging
from pathlib import Path
from bleak import BleakClient, BleakScanner

ROOT = Path(__file__).parent
ADDRESS = '6A:C2:D2:F2:1B:5D'
NAME = '00002a00-0000-1000-8000-00805f9b34fb'
events = []

def emit(event, **data):
    row = dict(time=datetime.datetime.now().astimezone().isoformat(), event=event, **data)
    events.append(row)
    print(json.dumps(row, ensure_ascii=False), flush=True)

async def main():
    try:
        device = await BleakScanner.find_device_by_address(ADDRESS, timeout=6)
        if device is None:
            raise RuntimeError('Target not advertising in scan window')
        emit('target_seen', address=device.address, name=device.name)
        async with BleakClient(device, timeout=15, pair=False,
                               winrt={'use_cached_services': False},
                               disconnected_callback=lambda _: emit('disconnected')) as client:
            native = client._backend._requester
            emit('connected', paired=native.device_information.pairing.is_paired)
            for i in range(3):
                name = bytes(await asyncio.wait_for(client.read_gatt_char(NAME, use_cached=False), 5))
                if name != b'MLT-BT05':
                    raise RuntimeError(f'Unexpected device name {name!r}')
                emit('remote_read', round=i+1, value=name.decode())
                await asyncio.sleep(2)
                if not client.is_connected:
                    raise RuntimeError('Disconnected during hold')
            emit('result', marker='BLE_READ_HOLD_GATE_PASS', writes=0)
        return 0
    except Exception as exc:
        emit('result', marker='BLE_READ_HOLD_GATE_FAIL', error=repr(exc), writes=0)
        logging.exception('Read-only connection gate failed')
        return 1
    finally:
        (ROOT/'gate_events.json').write_text(json.dumps(events, ensure_ascii=False, indent=2), encoding='utf-8')

logging.basicConfig(filename=ROOT/'bleak_debug.log', level=logging.DEBUG,
                    format='%(asctime)s %(name)s %(levelname)s %(message)s', encoding='utf-8')
raise SystemExit(asyncio.run(asyncio.wait_for(main(), 35)))
