"""Exercise exactly the GUI worker's public queue on the authorized PL UART bridge."""
import asyncio
import datetime
import json
import logging
from pathlib import Path
import queue
import subprocess
import sys
import time

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT.parents[2] / "3_host" / "ble_console"))
from ble_backend import BleWorker, DEVICE_NAME_UUID
from config_store import DEFAULT_CHARACTERISTIC_UUID as CHAR

rows = []
worker = BleWorker()
serial = None
rx = bytearray()


def emit(event, **data):
    row = dict(time=datetime.datetime.now().astimezone().isoformat(), event=event, **data)
    rows.append(row)
    print(json.dumps(row, default=str), flush=True)


async def wait_event(kind, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            event = worker.events.get_nowait()
        except queue.Empty:
            await asyncio.sleep(.02)
            continue
        values = {k: v.hex() if isinstance(v, bytes) else v for k, v in event.data.items()}
        emit(event.kind, **values)
        if event.kind == "notification":
            rx.extend(event.data["payload"])
        if event.kind == "error" or (event.kind == "disconnected" and not event.data.get("expected")):
            raise RuntimeError(str(values))
        if event.kind == kind:
            return event.data
    raise TimeoutError(f"Waiting for {kind}")


async def reply():
    value = json.loads(await asyncio.wait_for(asyncio.to_thread(serial.stdout.readline), 5))
    if "error" in value:
        raise RuntimeError(str(value))
    return value


async def rpc(op, **data):
    serial.stdin.write(json.dumps(dict(op=op, **data)) + "\n")
    serial.stdin.flush()
    return await reply()


async def main():
    global serial
    try:
        worker.start()
        worker.submit("connect", address="6A:C2:D2:F2:1B:5D", timeout=15)
        ready = await wait_event("connected", 55)
        assert ready["verified"] and ready["auto_notify"]
        started = time.monotonic()
        serial = subprocess.Popen(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
             "-File", str(ROOT / "serial_rpc.ps1")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, creationflags=subprocess.CREATE_NO_WINDOW,
        )
        emit("serial_open", **await reply())
        initial = await rpc("read", ms=200)
        if initial["hex"]:
            raise RuntimeError("Unexpected initial serial data")
        for index in range(3):
            if index:
                await asyncio.sleep(20)
            outbound = bytes([0x55, 0xaa, index, 0, 0xff, 0x31])
            inbound = bytes([0xaa, 0x55, index, 0xff, 0, 0x32])
            worker.submit("write", uuid=CHAR, payload=outbound, response=False)
            await wait_event("write_complete")
            actual = bytes.fromhex((await rpc("read", ms=600))["hex"])
            emit("serial_received", round=index, actual=actual.hex(), expected=outbound.hex())
            assert actual == outbound
            rx.clear()
            await rpc("write", hex=inbound.hex())
            deadline = time.monotonic() + 5
            while len(rx) < len(inbound):
                await wait_event("notification", max(.1, deadline - time.monotonic()))
            assert bytes(rx) == inbound
            emit("round_pass", round=index, ble_to_serial=6, serial_to_ble=6)
        await asyncio.sleep(max(0, 60 - (time.monotonic() - started)))
        worker.submit("read", uuid=DEVICE_NAME_UUID)
        final = await wait_event("read_complete")
        assert final["payload"] == b"MLT-BT05"
        trailing = await rpc("read", ms=200)
        assert trailing["hex"] == ""
        worker.submit("disconnect")
        await wait_event("disconnected")
        emit("result", marker="BLE_CONSOLE_V11_WORKER_BOARD_PASS", rounds=3,
             ready_hold_s=round(time.monotonic() - started, 3), bytes_each_direction=18)
        return 0
    except Exception as exc:
        emit("result", marker="BLE_CONSOLE_V11_WORKER_BOARD_FAIL", error=repr(exc))
        logging.exception("Worker board test")
        return 1
    finally:
        await asyncio.to_thread(worker.stop)
        if serial:
            try:
                await rpc("close")
                await asyncio.to_thread(serial.wait, 5)
            except Exception:
                serial.kill()
                serial.wait()
            emit("serial_closed", returncode=serial.returncode)
        (ROOT / "worker_board_events.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")


logging.basicConfig(filename=ROOT / "worker_board_debug.log", level=logging.DEBUG,
                    format="%(asctime)s %(name)s %(levelname)s %(message)s", encoding="utf-8")
raise SystemExit(asyncio.run(asyncio.wait_for(main(), 140)))
