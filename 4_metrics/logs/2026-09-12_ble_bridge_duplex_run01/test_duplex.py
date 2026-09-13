"""Fixed byte comparison then 10 bounded bidirectional rounds, no AT/config writes."""
import asyncio
import datetime
import json
import logging
from pathlib import Path
import subprocess
import time
from bleak import BleakClient, BleakScanner

ROOT = Path(__file__).parent
ADDRESS = '6A:C2:D2:F2:1B:5D'
CHAR = '0000ffe1-0000-1000-8000-00805f9b34fb'
NAME = '00002a00-0000-1000-8000-00805f9b34fb'
events = []
serial = None
expected_disconnect = False
connected_at = None

def emit(event, **data):
    row = dict(time=datetime.datetime.now().astimezone().isoformat(), event=event, **data)
    events.append(row)
    print(json.dumps(row), flush=True)

async def serial_reply():
    line = await asyncio.wait_for(asyncio.to_thread(serial.stdout.readline), 5)
    if not line:
        raise RuntimeError('Serial helper exited')
    reply = json.loads(line)
    if 'error' in reply:
        raise RuntimeError(reply['error'])
    return reply

async def rpc(op, **data):
    serial.stdin.write(json.dumps(dict(op=op, **data))+'\n')
    serial.stdin.flush()
    return await serial_reply()

async def main():
    global serial, expected_disconnect, connected_at
    q = asyncio.Queue()
    totals = dict(ble_to_serial=0, serial_to_ble=0)
    try:
        serial = subprocess.Popen(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                  '-File', str(ROOT/'serial_rpc.ps1')],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        emit('serial_open', **await serial_reply())
        device = await BleakScanner.find_device_by_address(ADDRESS, timeout=6)
        if device is None:
            raise RuntimeError('Target not found')
        def disconnected(_):
            emit('disconnected', expected=expected_disconnect,
                 elapsed_s=round(time.monotonic()-connected_at,3) if connected_at else None)
        async with BleakClient(device, timeout=15, pair=False,
                               winrt={'use_cached_services': False},
                               disconnected_callback=disconnected) as client:
            connected_at = time.monotonic()
            if client._backend._requester.device_information.pairing.is_paired:
                raise RuntimeError('Unexpected paired state; stop comparison')
            emit('connected', paired=False, mtu=client.mtu_size)
            if bytes(await asyncio.wait_for(client.read_gatt_char(NAME,use_cached=False),5)) != b'MLT-BT05':
                raise RuntimeError('Identity mismatch')
            char = client.services.get_characteristic(CHAR)
            if char is None or not {'write','notify'}.issubset(char.properties):
                raise RuntimeError('Required characteristic properties missing')
            def notification(_, data):
                value = bytes(data)
                emit('notification', hex=value.hex())
                q.put_nowait(value)
            await asyncio.wait_for(client.start_notify(char, notification),5)
            emit('notification_subscription_ready')
            initial = await rpc('read',ms=400)
            emit('serial_initial', **initial)

            async def exchange(index, outbound, inbound):
                if not client.is_connected:
                    raise RuntimeError('Disconnected before data exchange')
                if not q.empty():
                    raise RuntimeError('Unexpected pending notification')
                emit('ble_write_requested', index=index, hex=outbound.hex())
                await asyncio.wait_for(client.write_gatt_char(char,outbound,response=True),5)
                actual = bytes.fromhex((await rpc('read',ms=600))['hex'])
                emit('serial_received', index=index, hex=actual.hex())
                if actual != outbound:
                    raise RuntimeError(f'BLE to COM4 mismatch round {index}')
                totals['ble_to_serial'] += len(actual)
                emit('serial_write_requested', index=index, hex=inbound.hex())
                result = await rpc('write',hex=inbound.hex())
                if result['written'] != len(inbound):
                    raise RuntimeError('Serial write length mismatch')
                actual = b''
                deadline = time.monotonic()+4
                while len(actual)<len(inbound):
                    actual += await asyncio.wait_for(q.get(),max(.01,deadline-time.monotonic()))
                if actual != inbound:
                    raise RuntimeError(f'COM4 to BLE mismatch round {index}')
                await asyncio.sleep(.2)
                if not q.empty():
                    raise RuntimeError('Extra BLE data after expected payload')
                totals['serial_to_ble'] += len(actual)
                emit('round_pass', index=index, **totals)

            await exchange(0,bytes.fromhex('55aa313200ff'),bytes.fromhex('aa553231ff00'))
            for index in range(1,11):
                await asyncio.sleep(5)
                outbound=bytes([0xc3,index])+bytes((index*17+i)%256 for i in range(14))
                inbound=bytes([0x3c,index])+bytes((255-index*13-i)%256 for i in range(14))
                await exchange(index,outbound,inbound)
            while time.monotonic()-connected_at<60:
                await asyncio.sleep(.2)
                if not client.is_connected:
                    raise RuntimeError('Disconnected during final hold')
            name=bytes(await asyncio.wait_for(client.read_gatt_char(NAME,use_cached=False),5))
            if name != b'MLT-BT05' or not client.is_connected:
                raise RuntimeError('Final remote read failed')
            extra=bytes.fromhex((await rpc('read',ms=200))['hex'])
            if extra or not q.empty():
                raise RuntimeError('Unexpected trailing data')
            emit('result',marker='BLE_UART_DUPLEX_11_ROUNDS_60S_PASS',rounds=11,
                 connected_s=round(time.monotonic()-connected_at,3),**totals)
            expected_disconnect=True
        return 0
    except Exception as exc:
        emit('result',marker='BLE_UART_DUPLEX_FAIL',error=repr(exc),**totals)
        logging.exception('Duplex validation stopped')
        return 1
    finally:
        if serial:
            try:
                serial.stdin.write('{"op":"close"}\n')
                serial.stdin.flush()
                await asyncio.to_thread(serial.wait,5)
            except Exception:
                serial.kill()
                await asyncio.to_thread(serial.wait)
            emit('serial_closed',returncode=serial.returncode)
        (ROOT/'test_events.json').write_text(json.dumps(events,indent=2),encoding='utf-8')

logging.basicConfig(filename=ROOT/'bleak_debug.log',level=logging.DEBUG,
                    format='%(asctime)s %(name)s %(levelname)s %(message)s',encoding='utf-8')
raise SystemExit(asyncio.run(asyncio.wait_for(main(),120)))
