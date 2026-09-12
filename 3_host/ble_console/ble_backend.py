"""Async Bleak worker isolated from the Tk GUI thread."""

from __future__ import annotations

import asyncio
import queue
import threading
import traceback
from dataclasses import dataclass
from typing import Any

from bleak import BleakClient, BleakScanner


@dataclass(frozen=True)
class BackendEvent:
    kind: str
    data: dict[str, Any]


class BleWorker:
    """Own one asyncio loop and expose thread-safe BLE commands/events."""

    def __init__(self) -> None:
        self.commands: queue.Queue[tuple[str, dict[str, Any]]] = queue.Queue()
        self.events: queue.Queue[BackendEvent] = queue.Queue()
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._client: BleakClient | None = None
        self._stopping = threading.Event()
        self._notify_uuids: set[str] = set()

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stopping.clear()
        self._thread = threading.Thread(
            target=self._thread_main,
            name="ees331-ble-worker",
            daemon=True,
        )
        self._thread.start()

    def submit(self, action: str, **data: Any) -> None:
        self.commands.put((action, data))

    def stop(self) -> None:
        self._stopping.set()
        self.commands.put(("stop", {}))
        if self._thread:
            self._thread.join(timeout=5.0)

    def _emit(self, kind: str, **data: Any) -> None:
        self.events.put(BackendEvent(kind, data))

    def _thread_main(self) -> None:
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)
        try:
            self._loop.run_until_complete(self._command_pump())
        finally:
            self._loop.close()
            self._loop = None

    async def _command_pump(self) -> None:
        self._emit("worker_ready")
        while not self._stopping.is_set():
            action, data = await asyncio.to_thread(self.commands.get)
            if action == "stop":
                break
            try:
                await self._dispatch(action, data)
            except Exception as exc:  # noqa: BLE001 - errors cross thread boundary
                self._emit(
                    "error",
                    action=action,
                    message=str(exc),
                    traceback=traceback.format_exc(),
                )
        await self._disconnect(emit=False)
        self._emit("worker_stopped")

    async def _dispatch(self, action: str, data: dict[str, Any]) -> None:
        if action == "scan":
            await self._scan(float(data.get("timeout", 5.0)))
        elif action == "connect":
            await self._connect(
                str(data["address"]),
                float(data.get("timeout", 15.0)),
            )
        elif action == "disconnect":
            await self._disconnect()
        elif action == "refresh_services":
            await self._emit_services()
        elif action == "write":
            await self._write(
                str(data["uuid"]),
                bytes(data["payload"]),
                bool(data.get("response", False)),
            )
        elif action == "read":
            await self._read(str(data["uuid"]))
        elif action == "start_notify":
            await self._start_notify(str(data["uuid"]))
        elif action == "stop_notify":
            await self._stop_notify(str(data["uuid"]))
        else:
            raise ValueError(f"未知BLE操作：{action}")

    async def _scan(self, timeout: float) -> None:
        self._emit("scan_started", timeout=timeout)
        discovered = await BleakScanner.discover(timeout=timeout, return_adv=True)
        devices: list[dict[str, Any]] = []
        for device, advertisement in discovered.values():
            name = advertisement.local_name or device.name or "(未命名)"
            devices.append(
                {
                    "name": name,
                    "address": device.address,
                    "rssi": advertisement.rssi,
                    "service_uuids": list(advertisement.service_uuids or []),
                }
            )
        devices.sort(key=lambda item: int(item["rssi"]), reverse=True)
        self._emit("scan_complete", devices=devices)

    async def _connect(self, address: str, timeout: float) -> None:
        await self._disconnect(emit=False)
        self._emit("connect_started", address=address)
        self._client = BleakClient(
            address,
            disconnected_callback=self._on_disconnect,
            timeout=timeout,
        )
        await self._client.connect()
        if not self._client.is_connected:
            raise ConnectionError("Bleak未报告连接成功")
        self._emit("connected", address=address, mtu_size=self._client.mtu_size)
        await self._emit_services()

    async def _disconnect(self, emit: bool = True) -> None:
        client = self._client
        self._notify_uuids.clear()
        self._client = None
        if client and client.is_connected:
            await client.disconnect()
        if emit:
            self._emit("disconnected", expected=True)

    def _on_disconnect(self, _client: BleakClient) -> None:
        self._notify_uuids.clear()
        self._emit("disconnected", expected=False)

    def _require_client(self) -> BleakClient:
        if not self._client or not self._client.is_connected:
            raise ConnectionError("BLE设备尚未连接")
        return self._client

    async def _emit_services(self) -> None:
        client = self._require_client()
        services: list[dict[str, Any]] = []
        for service in client.services:
            characteristics: list[dict[str, Any]] = []
            for characteristic in service.characteristics:
                descriptors = [
                    {"handle": descriptor.handle, "uuid": descriptor.uuid}
                    for descriptor in characteristic.descriptors
                ]
                characteristics.append(
                    {
                        "uuid": characteristic.uuid,
                        "handle": characteristic.handle,
                        "properties": list(characteristic.properties),
                        "descriptors": descriptors,
                    }
                )
            services.append(
                {
                    "uuid": service.uuid,
                    "handle": service.handle,
                    "characteristics": characteristics,
                }
            )
        self._emit("services", services=services)

    async def _write(self, uuid: str, payload: bytes, response: bool) -> None:
        client = self._require_client()
        await client.write_gatt_char(uuid, payload, response=response)
        self._emit("write_complete", uuid=uuid, payload=payload, response=response)

    async def _read(self, uuid: str) -> None:
        client = self._require_client()
        payload = bytes(await client.read_gatt_char(uuid))
        self._emit("read_complete", uuid=uuid, payload=payload)

    async def _start_notify(self, uuid: str) -> None:
        client = self._require_client()

        def callback(characteristic: Any, payload: bytearray) -> None:
            self._emit(
                "notification",
                uuid=str(characteristic.uuid),
                payload=bytes(payload),
            )

        await client.start_notify(uuid, callback)
        self._notify_uuids.add(uuid.lower())
        self._emit("notify_started", uuid=uuid)

    async def _stop_notify(self, uuid: str) -> None:
        client = self._require_client()
        await client.stop_notify(uuid)
        self._notify_uuids.discard(uuid.lower())
        self._emit("notify_stopped", uuid=uuid)
