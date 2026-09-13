"""Deterministic offline connection-gate regressions; no Bluetooth hardware."""
import asyncio
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ble_backend import BleWorker
from config_store import AppConfig, DEFAULT_CHARACTERISTIC_UUID as CHAR


class GateTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.worker = BleWorker()
        self.client = MagicMock()
        self.client.is_connected = True
        self.client.mtu_size = 23
        self.client.connect = AsyncMock()
        self.client.disconnect = AsyncMock()
        self.client.read_gatt_char = AsyncMock(return_value=b"MLT-BT05")
        self.client.start_notify = AsyncMock()
        self.client.write_gatt_char = AsyncMock()
        self.char = SimpleNamespace(uuid=CHAR, service_uuid=AppConfig().service_uuid,
                                    properties=["read", "write", "write-without-response", "notify"])
        self.service = MagicMock()
        self.service.get_characteristic.return_value = self.char
        self.client.services.get_service.return_value = self.service
        self.client.services.get_characteristic.return_value = self.char
        self.client.services.__iter__.return_value = iter([])
        self.device = object()
        self.scan = self.enterContext(patch("ble_backend.BleakScanner.find_device_by_address",
                                           new=AsyncMock(return_value=self.device)))
        self.constructor = self.enterContext(patch("ble_backend.BleakClient", return_value=self.client))
        self.paired = self.enterContext(patch("ble_backend.is_target_paired", new=AsyncMock(return_value=False)))
        self.sleep = self.enterContext(patch("ble_backend.asyncio.sleep", new=AsyncMock()))

    async def connect(self, **kwargs):
        await self.worker._connect("6A:C2:D2:F2:1B:5D", 15, **kwargs)

    def events(self):
        result = []
        while not self.worker.events.empty():
            result.append(self.worker.events.get_nowait())
        return result

    async def test_ready_only_after_reads_hold_and_subscribe(self):
        async def read(*args, **kwargs):
            self.assertFalse(self.worker._ready)
            self.assertFalse(kwargs["use_cached"])
            return b"MLT-BT05"
        self.client.read_gatt_char.side_effect = read
        await self.connect()
        args, kwargs = self.constructor.call_args
        self.assertIs(args[0], self.device)
        self.assertFalse(kwargs["pair"])
        self.assertEqual(kwargs["winrt"], {"use_cached_services": False})
        self.assertEqual(self.client.read_gatt_char.await_count, 3)
        self.assertEqual(self.sleep.await_count, 3)
        self.assertEqual(self.paired.await_count, 2)
        kinds = [e.kind for e in self.events()]
        self.assertLess(kinds.index("notify_started"), kinds.index("connected"))
        self.assertTrue(self.worker._ready)

    async def test_paired_rejected_without_connect_or_mutation(self):
        self.paired.return_value = True
        with self.assertRaisesRegex(ConnectionError, "已配对"):
            await self.connect()
        self.constructor.assert_not_called()
        self.assertIsNone(self.worker._client)

    async def test_wrong_name_cleanup(self):
        self.client.read_gatt_char.return_value = b"Different module"
        with self.assertRaises(ConnectionError):
            await self.connect()
        self.client.disconnect.assert_awaited_once()
        self.assertFalse(any(e.kind == "connected" for e in self.events()))

    async def test_short_disconnect_never_ready(self):
        async def drop(*args):
            self.client.is_connected = False
            self.worker._on_disconnect(self.client)
        self.sleep.side_effect = drop
        with self.assertRaises(ConnectionError):
            await self.connect()
        self.assertFalse(self.worker._ready)
        self.assertFalse(any(e.kind == "connected" for e in self.events()))

    async def test_missing_service(self):
        self.client.services.get_service.return_value = None
        with self.assertRaises(ConnectionError):
            await self.connect()
        self.assertFalse(self.worker._ready)

    async def test_wrong_notify_service(self):
        self.char.service_uuid = "wrong"
        with self.assertRaises(ConnectionError):
            await self.connect()
        self.client.start_notify.assert_not_awaited()

    async def test_notify_failure_cleans_connection(self):
        self.client.start_notify.side_effect = RuntimeError("subscribe failed")
        with self.assertRaises(RuntimeError):
            await self.connect()
        self.assertIsNone(self.worker._client)
        self.assertFalse(self.worker._ready)

    async def test_connect_timeout_cleans_connection(self):
        self.client.connect.side_effect = TimeoutError()
        with self.assertRaises(TimeoutError):
            await self.connect()
        self.assertIsNone(self.worker._client)

    async def test_scan_absent(self):
        self.scan.return_value = None
        with self.assertRaises(ConnectionError):
            await self.connect()
        self.constructor.assert_not_called()

    async def test_cancel_cleans_connection(self):
        self.client.read_gatt_char.side_effect = asyncio.CancelledError()
        with self.assertRaises(asyncio.CancelledError):
            await self.connect()
        self.assertIsNone(self.worker._client)
        self.client.disconnect.assert_awaited_once()

    async def test_intentional_disconnect_ignores_callback(self):
        await self.connect()
        self.events()
        async def callback():
            self.worker._on_disconnect(self.client)
        self.client.disconnect.side_effect = callback
        await self.worker._disconnect()
        disconnects = [e for e in self.events() if e.kind == "disconnected"]
        self.assertEqual(len(disconnects), 1)
        self.assertTrue(disconnects[0].data["expected"])

    async def test_io_before_ready_rejected(self):
        self.worker._client = self.client
        with self.assertRaises(ConnectionError):
            await self.worker._write(CHAR, b"55", False)
        self.client.write_gatt_char.assert_not_called()

    async def test_generic_mode_does_not_claim_verification(self):
        await self.connect(verified_direct=False, auto_notify=False)
        self.paired.assert_not_called()
        self.client.read_gatt_char.assert_not_called()
        self.client.start_notify.assert_not_called()
        connected = next(e for e in self.events() if e.kind == "connected")
        self.assertFalse(connected.data["verified"])

    async def test_no_repeat_subscription(self):
        await self.connect()
        await self.worker._start_notify(CHAR)
        self.client.start_notify.assert_awaited_once()

    async def test_stale_io_dropped_by_queue(self):
        self.worker.commands.put(("write", {"_generation": -1}))
        self.worker.commands.put(("stop", {}))
        await self.worker._command_pump()
        self.client.write_gatt_char.assert_not_called()

    async def test_invalid_timeout_address(self):
        for timeout in [0, float("nan"), float("inf"), 121]:
            with self.assertRaises(ValueError):
                await self.worker._connect("6A:C2:D2:F2:1B:5D", timeout)
        with self.assertRaises(ValueError):
            await self.worker._connect("bad", 15)
        self.scan.assert_not_called()


class ConfigMigrationTests(unittest.TestCase):
    def test_old_config_defaults_to_verified_flow(self):
        config = AppConfig.from_mapping({"version": 1, "device_address": "AA:BB:CC:DD:EE:FF"})
        self.assertTrue(config.verified_direct)
        self.assertTrue(config.auto_notify)
        self.assertEqual(config.device_address, "AA:BB:CC:DD:EE:FF")

    def test_generic_mode_round_trip(self):
        config = AppConfig(verified_direct=False, auto_notify=False)
        restored = AppConfig.from_mapping(config.to_mapping())
        self.assertFalse(restored.verified_direct)
        self.assertFalse(restored.auto_notify)
