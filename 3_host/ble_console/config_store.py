"""Versioned JSON configuration storage for the EES-331 BLE console."""

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from pathlib import Path

from protocols import CommandPreset, normalize_uuid


CONFIG_VERSION = 1
DEFAULT_SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb"
DEFAULT_CHARACTERISTIC_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb"


@dataclass
class AppConfig:
    version: int = CONFIG_VERSION
    device_name: str = "MLT-BT05"
    device_address: str = "6A:C2:D2:F2:1B:5D"
    scan_timeout_s: float = 5.0
    connect_timeout_s: float = 15.0
    service_uuid: str = DEFAULT_SERVICE_UUID
    write_uuid: str = DEFAULT_CHARACTERISTIC_UUID
    notify_uuid: str = DEFAULT_CHARACTERISTIC_UUID
    write_with_response: bool = False
    tx_mode: str = "hex"
    append: str = "none"
    interval_ms: int = 1000
    presets: list[CommandPreset] = field(
        default_factory=lambda: [
            CommandPreset("PL接收验证", "hex", "55 AA 31 32"),
            CommandPreset("ASCII PING", "utf8", "PING", "crlf"),
        ]
    )

    def validate(self) -> None:
        if self.scan_timeout_s <= 0:
            raise ValueError("扫描超时必须大于0秒")
        if self.connect_timeout_s <= 0:
            raise ValueError("连接超时必须大于0秒")
        if not 50 <= self.interval_ms <= 3_600_000:
            raise ValueError("循环发送间隔必须在50到3600000毫秒之间")
        if self.tx_mode not in {"hex", "utf8"}:
            raise ValueError("发送格式只能为hex或utf8")
        if self.append not in {"none", "cr", "lf", "crlf"}:
            raise ValueError("行结束符无效")
        self.service_uuid = normalize_uuid(self.service_uuid)
        self.write_uuid = normalize_uuid(self.write_uuid)
        self.notify_uuid = normalize_uuid(self.notify_uuid)

    @classmethod
    def from_mapping(cls, value: dict[str, object]) -> "AppConfig":
        presets_value = value.get("presets", [])
        presets = [
            CommandPreset.from_mapping(item)
            for item in presets_value
            if isinstance(item, dict)
        ]
        config = cls(
            version=int(value.get("version", CONFIG_VERSION)),
            device_name=str(value.get("device_name", "MLT-BT05")),
            device_address=str(value.get("device_address", "")),
            scan_timeout_s=float(value.get("scan_timeout_s", 5.0)),
            connect_timeout_s=float(value.get("connect_timeout_s", 15.0)),
            service_uuid=str(value.get("service_uuid", DEFAULT_SERVICE_UUID)),
            write_uuid=str(value.get("write_uuid", DEFAULT_CHARACTERISTIC_UUID)),
            notify_uuid=str(value.get("notify_uuid", DEFAULT_CHARACTERISTIC_UUID)),
            write_with_response=bool(value.get("write_with_response", False)),
            tx_mode=str(value.get("tx_mode", "hex")),
            append=str(value.get("append", "none")),
            interval_ms=int(value.get("interval_ms", 1000)),
            presets=presets or cls().presets,
        )
        config.validate()
        return config

    def to_mapping(self) -> dict[str, object]:
        value = asdict(self)
        value["presets"] = [asdict(item) for item in self.presets]
        return value


def default_config_path() -> Path:
    root = Path(os.environ.get("LOCALAPPDATA", Path.home()))
    return root / "EES331_BLE_Console" / "config.json"


def load_config(path: Path | None = None) -> AppConfig:
    config_path = path or default_config_path()
    if not config_path.exists():
        return AppConfig()
    value = json.loads(config_path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("配置文件根节点必须是JSON对象")
    return AppConfig.from_mapping(value)


def save_config(config: AppConfig, path: Path | None = None) -> Path:
    config.validate()
    config_path = path or default_config_path()
    config_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = config_path.with_suffix(".tmp")
    temporary_path.write_text(
        json.dumps(config.to_mapping(), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary_path.replace(config_path)
    return config_path
