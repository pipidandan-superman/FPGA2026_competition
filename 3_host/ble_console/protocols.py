"""Payload codecs and extensible command profiles for the BLE console."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable


def normalize_uuid(value: str) -> str:
    """Normalize 16-bit Bluetooth UUIDs and preserve full UUID strings."""
    text = value.strip().lower()
    if not text:
        return ""
    if len(text) == 4 and all(char in "0123456789abcdef" for char in text):
        return f"0000{text}-0000-1000-8000-00805f9b34fb"
    return text


def parse_hex_payload(text: str) -> bytes:
    """Parse bytes separated by spaces, commas, dashes, or 0x prefixes."""
    cleaned = text.replace(",", " ").replace("-", " ")
    tokens = cleaned.split()
    if not tokens:
        return b""

    values: list[int] = []
    for token in tokens:
        item = token[2:] if token.lower().startswith("0x") else token
        if not item:
            raise ValueError("十六进制字节不能为空")
        if len(item) > 2:
            if len(tokens) == 1 and len(item) % 2 == 0:
                try:
                    return bytes.fromhex(item)
                except ValueError as exc:
                    raise ValueError("十六进制数据包含非法字符") from exc
            raise ValueError(f"字节 {token!r} 超过两位十六进制")
        try:
            value = int(item, 16)
        except ValueError as exc:
            raise ValueError(f"无法解析十六进制字节 {token!r}") from exc
        values.append(value)
    return bytes(values)


def encode_payload(text: str, mode: str, append: str = "none") -> bytes:
    """Encode the send editor using the selected mode and suffix."""
    if mode == "hex":
        payload = parse_hex_payload(text)
    elif mode == "utf8":
        payload = text.encode("utf-8")
    else:
        raise ValueError(f"未知发送格式：{mode}")

    suffixes = {
        "none": b"",
        "cr": b"\r",
        "lf": b"\n",
        "crlf": b"\r\n",
    }
    try:
        return payload + suffixes[append]
    except KeyError as exc:
        raise ValueError(f"未知行结束符：{append}") from exc


def format_payload(payload: bytes) -> tuple[str, str]:
    """Return uppercase hexadecimal and printable UTF-8 representations."""
    hex_text = " ".join(f"{byte:02X}" for byte in payload)
    decoded = payload.decode("utf-8", errors="replace")
    printable = "".join(char if char.isprintable() else "." for char in decoded)
    return hex_text, printable


@dataclass(frozen=True)
class CommandPreset:
    """A configurable application-level command without transport coupling."""

    name: str
    mode: str
    payload: str
    append: str = "none"

    @classmethod
    def from_mapping(cls, value: dict[str, object]) -> "CommandPreset":
        return cls(
            name=str(value.get("name", "未命名")),
            mode=str(value.get("mode", "hex")),
            payload=str(value.get("payload", "")),
            append=str(value.get("append", "none")),
        )

    def encode(self) -> bytes:
        return encode_payload(self.payload, self.mode, self.append)


def find_characteristic(
    characteristics: Iterable[dict[str, object]],
    required_property: str,
    preferred_uuid: str = "",
) -> str:
    """Select a characteristic by preferred UUID or required property."""
    normalized_preferred = normalize_uuid(preferred_uuid)
    items = list(characteristics)
    if normalized_preferred:
        for item in items:
            if normalize_uuid(str(item.get("uuid", ""))) == normalized_preferred:
                return str(item["uuid"])

    for item in items:
        properties = {str(value).lower() for value in item.get("properties", [])}
        if required_property.lower() in properties:
            return str(item["uuid"])
    return ""
