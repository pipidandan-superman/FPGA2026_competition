"""Offline unit tests for BLE console codecs and configuration."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys


SOURCE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SOURCE_ROOT))

from config_store import AppConfig, load_config, save_config  # noqa: E402
from protocols import (  # noqa: E402
    encode_payload,
    find_characteristic,
    format_payload,
    normalize_uuid,
    parse_hex_payload,
)


class ProtocolTests(unittest.TestCase):
    def test_parse_hex_payload(self) -> None:
        expected = bytes((0x55, 0xAA, 0x31, 0x32))
        self.assertEqual(parse_hex_payload("55 AA 31 32"), expected)
        self.assertEqual(parse_hex_payload("0x55,0xAA,31,32"), expected)
        self.assertEqual(parse_hex_payload("55AA3132"), expected)

    def test_invalid_hex_payload(self) -> None:
        with self.assertRaises(ValueError):
            parse_hex_payload("55 GG")
        with self.assertRaises(ValueError):
            parse_hex_payload("123")

    def test_encode_suffix(self) -> None:
        self.assertEqual(encode_payload("AT", "utf8", "crlf"), b"AT\r\n")

    def test_format_payload(self) -> None:
        self.assertEqual(format_payload(b"OK\r\n"), ("4F 4B 0D 0A", "OK.."))

    def test_normalize_uuid(self) -> None:
        self.assertEqual(
            normalize_uuid("FFE0"),
            "0000ffe0-0000-1000-8000-00805f9b34fb",
        )

    def test_characteristic_selection(self) -> None:
        items = [
            {"uuid": "fff1", "properties": ["read"]},
            {"uuid": "fff2", "properties": ["write-without-response"]},
        ]
        self.assertEqual(
            find_characteristic(items, "write-without-response"),
            "fff2",
        )


class ConfigurationTests(unittest.TestCase):
    def test_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            original = AppConfig(device_address="AA:BB:CC:DD:EE:FF")
            save_config(original, path)
            restored = load_config(path)
            self.assertEqual(restored.device_address, original.device_address)
            self.assertEqual(restored.presets[0].encode(), bytes((0x55, 0xAA, 0x31, 0x32)))
            self.assertIsInstance(json.loads(path.read_text(encoding="utf-8")), dict)

    def test_interval_validation(self) -> None:
        config = AppConfig(interval_ms=10)
        with self.assertRaises(ValueError):
            config.validate()


if __name__ == "__main__":
    unittest.main(verbosity=2)
