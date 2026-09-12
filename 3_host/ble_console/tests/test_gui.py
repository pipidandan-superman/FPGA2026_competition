"""Tk event-state smoke tests with a mocked worker; never connect to hardware."""
import sys
import tempfile
import tkinter as tk
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import BleConsoleApp
from ble_backend import BackendEvent
from config_store import AppConfig


class GuiTests(unittest.TestCase):
    def setUp(self):
        self.temporary = self.enterContext(tempfile.TemporaryDirectory())
        self.root = tk.Tk()
        self.root.withdraw()
        self.addCleanup(self.root.destroy)
        self.worker = MagicMock()
        self.enterContext(patch("app.BleWorker", return_value=self.worker))
        self.enterContext(patch("app.load_config", return_value=AppConfig()))
        self.enterContext(patch.object(BleConsoleApp, "_create_session_log",
                                      return_value=Path(self.temporary) / "ui.jsonl"))
        self.enterContext(patch.object(self.root, "after", return_value="mock-timer"))
        self.enterContext(patch.object(self.root, "after_cancel"))
        self.dialog = self.enterContext(patch("app.messagebox.showerror"))
        self.app = BleConsoleApp(self.root)

    def event(self, kind, **data):
        self.app._handle_event(BackendEvent(kind, data))

    def test_connect_uses_new_config_disables_io_until_ready(self):
        self.app._connect()
        kwargs = self.worker.submit.call_args.kwargs
        self.assertTrue(kwargs["verified_direct"])
        self.assertTrue(kwargs["auto_notify"])
        self.assertEqual(str(self.app.send_button["state"]), "disabled")
        self.event("connection_stage", message="远端读取 1/3")
        self.assertFalse(self.app.connected)
        self.event("connected", verified=True, mtu_size=23)
        self.assertEqual(str(self.app.send_button["state"]), "normal")
        self.assertEqual(self.app.status_var.get(), "校验通过，可收发")

    def test_disconnect_stops_periodic_and_controls(self):
        self.event("connected", verified=True, mtu_size=23)
        self.app.periodic_var.set(True)
        self.app.periodic_job = "mock-timer"
        self.event("disconnected", expected=False, elapsed_s=.2)
        self.assertFalse(self.app.periodic_var.get())
        self.assertFalse(self.app.connected)
        self.assertIsNone(self.app.periodic_job)
        self.assertEqual(str(self.app.send_button["state"]), "disabled")

    def test_connect_failure_clears_auto_notify_state(self):
        self.event("notify_started", uuid=AppConfig().notify_uuid)
        self.event("error", action="connect", message="failed")
        self.assertFalse(self.app.notify_active)
        self.assertEqual(str(self.app.send_button["state"]), "disabled")
        self.assertEqual(str(self.app.connect_button["state"]), "normal")

    def test_stop_notify_uses_actual_subscription(self):
        old = AppConfig().notify_uuid
        self.event("notify_started", uuid=old)
        self.app.notify_uuid_var.set("ffff")
        self.app._toggle_notify()
        self.worker.submit.assert_called_with("stop_notify", uuid=old)

    def test_generic_does_not_claim_verified(self):
        self.event("connected", verified=False, mtu_size=23)
        self.assertIn("未做MLT校验", self.app.status_var.get())
