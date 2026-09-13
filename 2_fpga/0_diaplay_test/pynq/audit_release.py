#!/usr/bin/env python3
"""Offline audit of the deployable integrated BIT/HWH pair."""
import hashlib
import importlib.util
import json
from pathlib import Path

from main_hardware_contract import validate_main_hardware_contract


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / "release_manifest.json").read_text(
        encoding="utf-8-sig"))
    checked = {}
    for name in ("overlay.bit", "overlay.hwh"):
        path = root / name
        expected = manifest["files"][name]
        actual = {"sha256": sha256(path), "bytes": path.stat().st_size}
        if actual != expected:
            raise RuntimeError(f"Release mismatch for {name}: {actual}")
        checked[name] = actual
    camera_spec = importlib.util.spec_from_file_location(
        "ees331_camera_release_audit", root / "camera.py")
    camera = importlib.util.module_from_spec(camera_spec)
    camera_spec.loader.exec_module(camera)
    if (camera.BIT_HASH != checked["overlay.bit"]["sha256"] or
            camera.HWH_HASH != checked["overlay.hwh"]["sha256"]):
        raise RuntimeError("camera.py is not pinned to the manifest BIT/HWH pair")
    result = {
        "marker": "MAIN_AXI_BLE_RELEASE_AUDIT_PASS",
        "files": checked,
        "hardware_contract": validate_main_hardware_contract(root / "overlay.hwh"),
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
