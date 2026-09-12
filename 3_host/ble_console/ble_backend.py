"""Async Bleak worker isolated from the Tk GUI thread."""

from __future__ import annotations

import asyncio
import math
import queue
import re
import threading
import time
import traceback
from dataclasses import dataclass
from typing import Any

from bleak import BleakClient, BleakScanner
from config_store import DEFAULT_SERVICE_UUID, DEFAULT_CHARACTERISTIC_UUID
from protocols import normalize_uuid


DEVICE_NAME_UUID = "00002a00-0000-1000-8000-00805f9b34fb"


async def is_target_paired(address: str) -> bool:
    """Read only: never pair, unpair or change the module configuration."""
    from winrt.windows.devices.bluetooth import BluetoothLEDevice

    device = await BluetoothLEDevice.from_bluetooth_address_async(
        int(address.replace(":", ""), 16)
    )
    if device is None:
        raise ConnectionError("无法查询目标配对状态；本次未修改任何配对")
    try:
        return bool(device.device_information.pairing.is_paired)
    finally:
        device.close()


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
        self._ready = False
        self._connected_at = 0.0
        self._active_task: asyncio.Task | None = None
        self._generation = 0

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
        data["_generation"] = self._generation
        if action == "disconnect" and self._loop:
            self._loop.call_soon_threadsafe(self._cancel_active)
        self.commands.put((action, data))

    def _cancel_active(self) -> None:
        if self._active_task and not self._active_task.done():
            self._active_task.cancel()

    def stop(self) -> None:
        self._stopping.set()
        if self._loop:
            self._loop.call_soon_threadsafe(self._cancel_active)
        self.commands.put(("stop", {}))
        if self._thread:
            self._thread.join(timeout=6.0)

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
            if action not in {"scan", "connect", "disconnect"}:
                if data.get("_generation") != self._generation:
                    continue  # Never replay queued I/O across connections.
            try:
                self._active_task = asyncio.create_task(self._dispatch(action, data))
                await self._active_task
            except asyncio.CancelledError:
                self._emit("operation_cancelled", action=action)
            except Exception as exc:  # noqa: BLE001 - errors cross thread boundary
                if action in {"write", "read", "start_notify", "stop_notify"}:
                    await self._disconnect()
                self._emit(
                    "error",
                    action=action,
                    message=str(exc),
                    traceback=traceback.format_exc(),
                )
            finally:
                self._active_task = None
        await self._disconnect(emit=False)
        self._emit("worker_stopped")

    async def _dispatch(self, action: str, data: dict[str, Any]) -> None:
        if action == "scan":
            await self._scan(float(data.get("timeout", 5.0)))
        elif action == "connect":
            await self._connect(
                str(data["address"]),
                float(data.get("timeout", 15.0)),
                verified_direct=bool(data.get("verified_direct", True)),
                auto_notify=bool(data.get("auto_notify", True)),
                service_uuid=str(data.get("service_uuid", DEFAULT_SERVICE_UUID)),
                write_uuid=str(data.get("write_uuid", DEFAULT_CHARACTERISTIC_UUID)),
                notify_uuid=str(data.get("notify_uuid", DEFAULT_CHARACTERISTIC_UUID)),
                response=bool(data.get("response", False)),
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

    async def _connect(
        self, address: str, timeout: float, *, verified_direct: bool = True,
        auto_notify: bool = True, service_uuid: str = DEFAULT_SERVICE_UUID,
        write_uuid: str = DEFAULT_CHARACTERISTIC_UUID,
        notify_uuid: str = DEFAULT_CHARACTERISTIC_UUID, response: bool = False,
    ) -> None:
        await self._disconnect(emit=False)
        if not re.fullmatch(r"[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}", address):
            raise ValueError("请填写有效的 Windows BLE 地址，例如 AA:BB:CC:DD:EE:FF")
        if not math.isfinite(timeout) or not 0 < timeout <= 120:
            raise ValueError("连接超时必须在 0 到 120 秒之间")
        self._emit("connect_started", address=address)
        try:
            self._emit("connection_stage", message="重新扫描目标广播")
            device = await BleakScanner.find_device_by_address(address, timeout=timeout)
            if device is None:
                raise ConnectionError("未找到目标广播；检查板卡上电及是否被其他软件占用")
            if verified_direct:
                await self._check_unpaired(address)
            client = BleakClient(
                device, disconnected_callback=self._on_disconnect, timeout=timeout,
                pair=False, winrt={"use_cached_services": False},
            )
            self._client = client
            self._emit("connection_stage", message="GATT 直连（不发起配对）")
            await asyncio.wait_for(client.connect(), timeout)
            if not client.is_connected:
                raise ConnectionError("Bleak未报告连接成功")
            self._connected_at = time.monotonic()
            if verified_direct:
                await self._check_unpaired(address)
                service = client.services.get_service(normalize_uuid(service_uuid))
                if service is None:
                    raise ConnectionError("未找到配置的透传服务；不自动改用其他服务")
                write_char = service.get_characteristic(normalize_uuid(write_uuid))
                required = "write" if response else "write-without-response"
                if write_char is None or required not in write_char.properties:
                    raise ConnectionError(f"配置的写特征不支持 {required}")
                for index in range(3):
                    name = bytes(await asyncio.wait_for(
                        client.read_gatt_char(DEVICE_NAME_UUID, use_cached=False), 5
                    ))
                    if name != b"MLT-BT05":
                        raise ConnectionError(
                            "MLT-BT05 校验模式下远端名称不符；其他模块请使用通用模式"
                        )
                    self._emit("connection_stage", message=f"远端读取 {index + 1}/3 通过；保持连接")
                    await asyncio.sleep(2)
                    if self._client is not client or not client.is_connected:
                        raise ConnectionError("实际读取/保持期间掉线，未开放收发")
            if auto_notify:
                characteristic = client.services.get_characteristic(normalize_uuid(notify_uuid))
                if characteristic is None or not {"notify", "indicate"}.intersection(characteristic.properties):
                    raise ConnectionError("配置的通知特征不存在或不支持订阅")
                if verified_direct and characteristic.service_uuid.lower() != normalize_uuid(service_uuid):
                    raise ConnectionError("通知特征不属于配置的透传服务")
                await self._subscribe(client, normalize_uuid(notify_uuid))
            if self._client is not client or not client.is_connected:
                raise ConnectionError("连接准备期间掉线")
            self._ready = True
            await self._emit_services()
            self._emit(
                "connected", address=address, mtu_size=client.mtu_size,
                verified=verified_direct, auto_notify=auto_notify,
                elapsed_s=round(time.monotonic() - self._connected_at, 3),
            )
        except BaseException:
            await self._disconnect(emit=False)
            raise

    async def _check_unpaired(self, address: str) -> None:
        paired = await asyncio.wait_for(is_target_paired(address), 5)
        self._emit("pairing_status", paired=paired, address=address)
        if paired:
            raise ConnectionError(
                "目标仍是 Windows 已配对设备。已验证直连模式要求未配对；"
                "请自行在系统设置中移除仅此 MLT-BT05 后重试。程序不会自动移除或修改 PIN。"
            )

    async def _disconnect(self, emit: bool = True) -> None:
        client = self._client
        self._ready = False
        self._generation += 1
        self._notify_uuids.clear()
        self._client = None
        if client and client.is_connected:
            try:
                await asyncio.wait_for(client.disconnect(), 5)
            except Exception as exc:
                self._emit("cleanup_warning", message=str(exc))
        if emit:
            self._emit("disconnected", expected=True)

    def _on_disconnect(self, _client: BleakClient) -> None:
        if self._client is not _client:
            return  # Intentional cleanup or a callback from an obsolete session.
        self._ready = False
        self._generation += 1
        self._notify_uuids.clear()
        self._emit("disconnected", expected=False,
                   elapsed_s=round(time.monotonic() - self._connected_at, 3)
                   if self._connected_at else 0)

    def _require_client(self) -> BleakClient:
        if not self._ready or not self._client or not self._client.is_connected:
            raise ConnectionError("BLE连接尚未通过准备/校验，禁止收发")
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
        await asyncio.wait_for(client.write_gatt_char(uuid, payload, response=response), 5)
        self._emit("write_complete", uuid=uuid, payload=payload, response=response)

    async def _read(self, uuid: str) -> None:
        client = self._require_client()
        payload = bytes(await asyncio.wait_for(client.read_gatt_char(uuid, use_cached=False), 5))
        self._emit("read_complete", uuid=uuid, payload=payload)

    async def _start_notify(self, uuid: str) -> None:
        client = self._require_client()
        await self._subscribe(client, uuid)

    async def _subscribe(self, client: BleakClient, uuid: str) -> None:
        if uuid.lower() in self._notify_uuids:
            return

        def callback(characteristic: Any, payload: bytearray) -> None:
            if self._client is not client:
                return
            self._emit(
                "notification",
                uuid=str(characteristic.uuid),
                payload=bytes(payload),
            )

        await asyncio.wait_for(client.start_notify(uuid, callback), 5)
        self._notify_uuids.add(uuid.lower())
        self._emit("notify_started", uuid=uuid)

    async def _stop_notify(self, uuid: str) -> None:
        client = self._require_client()
        await asyncio.wait_for(client.stop_notify(uuid), 5)
        self._notify_uuids.discard(uuid.lower())
        self._emit("notify_stopped", uuid=uuid)
