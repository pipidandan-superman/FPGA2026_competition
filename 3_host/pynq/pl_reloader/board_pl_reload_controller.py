#!/usr/bin/env python3
"""Fail-closed board-side controller for the EES-331 action overlay.

This helper is uploaded with the versioned payload and executed as root. It
never changes boot files and never enables the action service at boot.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time


ORIGINAL_SERVICE = "ees331-camera"
STATE_FILE = Path("/run/ees331_pl_reloader_state.json")
RUN_ROOT = Path("/home/xilinx/pl_reload_runs")
ACTION_PROCESS = "camera_action_v1.py"
ORIGINAL_PROCESS = "/home/xilinx/ees331_camera/camera.py"
ACTION_READY_TIMEOUT_SECONDS = 75


class ControllerError(RuntimeError):
    pass


def emit(event: str, **details) -> None:
    row = {"event": event, "monotonic": time.monotonic(), **details}
    print(json.dumps(row, ensure_ascii=False), flush=True)


def run(argv: list[str], *, check: bool = True, timeout: float = 30) -> subprocess.CompletedProcess:
    completed = subprocess.run(
        argv,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    if check and completed.returncode:
        tail = completed.stdout[-2000:] if completed.stdout else ""
        raise ControllerError(f"Command failed ({completed.returncode}): {argv[0]}\n{tail}")
    return completed


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_payload(app_dir: Path) -> dict:
    manifest_path = app_dir / "release_manifest.json"
    if not manifest_path.is_file():
        raise ControllerError("release_manifest.json is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("marker") != "ACTION_V1_RELEASE_PASS":
        raise ControllerError("Release marker is not ACTION_V1_RELEASE_PASS")

    failures = []
    for name, metadata in manifest.get("files", {}).items():
        path = app_dir / name
        actual = file_sha256(path) if path.is_file() else None
        if actual != metadata.get("sha256"):
            failures.append({"file": name, "expected": metadata.get("sha256"), "actual": actual})
    if failures:
        emit("PAYLOAD_HASH_FAIL", failures=failures)
        raise ControllerError("Payload hash verification failed")

    contract_path = app_dir / "action_hardware_contract.py"
    spec = importlib.util.spec_from_file_location("action_hardware_contract_runtime", contract_path)
    if spec is None or spec.loader is None:
        raise ControllerError("Cannot import action hardware contract")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    hwh = app_dir / "display_test_axi_action_uart.hwh"
    contract = module.validate_action_hardware_contract(hwh)
    if contract.get("marker") != "ACTION_HARDWARE_CONTRACT_PASS":
        raise ControllerError("Hardware contract did not pass")
    emit("PAYLOAD_VERIFIED", files=len(manifest["files"]), hardware=contract)
    return manifest


def compile_mmio(app_dir: Path) -> str:
    source = app_dir / "mmio_ordered.c"
    output = app_dir / "libmmio_ordered.so"
    run([
        "cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
        "-fPIC", "-shared", str(source), "-o", str(output),
    ], timeout=60)
    digest = file_sha256(output)
    emit("MMIO_LIBRARY_READY", path=str(output), sha256=digest)
    return digest


def service_properties(service: str) -> dict[str, str]:
    result = run([
        "systemctl", "show", service,
        "-p", "MainPID", "-p", "ActiveState", "-p", "SubState",
    ], check=False)
    properties = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            properties[key] = value
    return properties


def processes() -> str:
    result = run(["pgrep", "-af", "camera.py|camera_action_v1.py"], check=False)
    return result.stdout.strip()


def journal(service: str, since_epoch: float, lines: int = 200) -> str:
    result = run([
        "journalctl", "-u", service, "-b", "--since", f"@{int(since_epoch)}",
        "-n", str(lines), "--no-pager", "-o", "cat",
    ], check=False)
    return result.stdout


def journal_delta(previous: str, current: str) -> list[str]:
    """Return only newly appended journal lines, tolerating journal truncation."""
    old_lines = previous.splitlines()
    new_lines = current.splitlines()
    overlap_limit = min(len(old_lines), len(new_lines))
    for overlap in range(overlap_limit, -1, -1):
        if overlap == 0 or old_lines[-overlap:] == new_lines[:overlap]:
            return new_lines[overlap:]
    return new_lines


def wait_until(predicate, timeout: float, interval: float = 0.25) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


def stop_original() -> str:
    props = service_properties(ORIGINAL_SERVICE)
    if props.get("ActiveState") != "active" or props.get("MainPID") in (None, "", "0"):
        raise ControllerError("Original video service is not the active baseline owner")
    if ORIGINAL_PROCESS not in processes():
        raise ControllerError("Original service PID does not match the expected camera.py")

    started = time.time() - 1
    emit("ORIGINAL_STOP_BEGIN", service=ORIGINAL_SERVICE, properties=props)
    run(["systemctl", "stop", ORIGINAL_SERVICE], timeout=25)
    stopped = wait_until(
        lambda: service_properties(ORIGINAL_SERVICE).get("MainPID") == "0"
        and ORIGINAL_PROCESS not in processes(),
        10,
    )
    stop_log = journal(ORIGINAL_SERVICE, started)
    halted = stop_log.rfind("VDMA_HALTED")
    freed = stop_log.rfind("BUFFER_FREED")
    if not stopped or halted < 0 or freed < halted:
        emit("ORIGINAL_STOP_UNSAFE", stopped=stopped, halted=halted >= 0, freed=freed > halted)
        run(["systemctl", "start", ORIGINAL_SERVICE], check=False, timeout=30)
        raise ControllerError("Original VDMA/buffer release was not proven; original service restart requested")
    emit("ORIGINAL_STOP_SAFE", service=ORIGINAL_SERVICE)
    return stop_log


def action_units() -> list[str]:
    result = run([
        "systemctl", "list-units", "--type=service", "--state=running",
        "--no-legend", "--no-pager",
    ], check=False)
    units = []
    for line in result.stdout.splitlines():
        name = line.split(maxsplit=1)[0] if line.strip() else ""
        if name.startswith("ees331-action-"):
            units.append(name)
    return units


def restore_original(*, reason: str) -> dict:
    emit("RESTORE_BEGIN", reason=reason)
    current_processes = processes()
    original_props = service_properties(ORIGINAL_SERVICE)
    if (ACTION_PROCESS not in current_processes
            and ORIGINAL_PROCESS in current_processes
            and original_props.get("ActiveState") == "active"
            and original_props.get("MainPID") not in (None, "", "0")):
        if STATE_FILE.exists():
            STATE_FILE.unlink()
        result = {
            "service": ORIGINAL_SERVICE,
            "properties": original_props,
            "physical_confirmation": "REQUIRED",
        }
        emit("ORIGINAL_ALREADY_RUNNING_NO_RELOAD", **result)
        return result

    units = action_units()
    saved = None
    if STATE_FILE.is_file():
        try:
            saved = json.loads(STATE_FILE.read_text(encoding="utf-8"))
            unit = saved.get("unit")
            if unit and unit not in units:
                units.append(unit)
        except Exception as exc:
            emit("STATE_FILE_WARNING", error=repr(exc))

    action_was_running = ACTION_PROCESS in current_processes
    stop_started = time.time() - 1
    for unit in units:
        run(["systemctl", "stop", unit], check=False, timeout=30)
    if action_was_running and ACTION_PROCESS in processes():
        raise ControllerError("Action process remains after service stop; refusing to start competing video owner")

    evidence_since = stop_started
    if saved and isinstance(saved.get("started_epoch"), (int, float)):
        evidence_since = min(evidence_since, float(saved["started_epoch"]))
    action_log = "\n".join(journal(unit, evidence_since) for unit in units)
    touched_dma = "BUFFER_ALLOCATED" in action_log or "VDMA_STREAM_STARTED" in action_log
    halted = action_log.rfind("VDMA_HALTED")
    freed = action_log.rfind("BUFFER_FREED")
    if touched_dma and (halted < 0 or freed < halted):
        emit("ACTION_STOP_UNSAFE", units=units, halted=halted >= 0, freed=freed > halted)
        raise ControllerError("Action VDMA/buffer release was not proven; original service remains stopped")

    started = time.time() - 1
    run(["systemctl", "start", ORIGINAL_SERVICE], timeout=30)

    def original_ready() -> bool:
        props = service_properties(ORIGINAL_SERVICE)
        if props.get("ActiveState") != "active" or props.get("MainPID") in (None, "", "0"):
            return False
        text = journal(ORIGINAL_SERVICE, started)
        return "PL_LOADED" in text and ("HEARTBEAT" in text or "CAPTURE_VDMA_RUN_COMPLETE" in text)

    ready = wait_until(original_ready, 35, interval=1)
    props = service_properties(ORIGINAL_SERVICE)
    if STATE_FILE.exists():
        STATE_FILE.unlink()
    if not ready:
        emit("ORIGINAL_RESTORE_INCOMPLETE", properties=props)
        raise ControllerError("Original service did not produce a new-frame readiness marker")
    result = {"service": ORIGINAL_SERVICE, "properties": props, "physical_confirmation": "REQUIRED"}
    emit("ORIGINAL_RESTORE_READY", **result)
    return result


def start_action(app_dir: Path) -> dict:
    current_processes = processes()
    if ACTION_PROCESS in current_processes:
        result = {"state": "ALREADY_RUNNING", "processes": current_processes}
        emit("ACTION_ALREADY_RUNNING_NO_RELOAD", **result)
        return result

    validate_payload(app_dir)
    compile_mmio(app_dir)
    stop_original()

    timestamp = time.strftime("%Y%m%d_%H%M%S")
    unit_base = f"ees331-action-reloader-{timestamp}"
    unit = unit_base + ".service"
    run_dir = RUN_ROOT / timestamp
    RUN_ROOT.mkdir(parents=True, exist_ok=True)
    if run_dir.exists():
        raise ControllerError(f"Run directory already exists: {run_dir}")

    command = (
        f"cd {shlex.quote(str(app_dir))} && "
        f"exec bash ./run_action_v1.sh --evidence {shlex.quote(str(run_dir))} --seconds 0"
    )
    started = time.time() - 1
    emit("ACTION_START_BEGIN", unit=unit, run_dir=str(run_dir))
    try:
        run([
            "systemd-run", "--unit", unit_base,
            "--property=Type=simple", "--property=Restart=no",
            "--property=TimeoutStopSec=infinity", "--property=SendSIGKILL=no",
            "--setenv=XILINX_XRT=/usr", "/bin/bash", "-lc", command,
        ], timeout=20)
        STATE_FILE.write_text(json.dumps({
            "state": "STARTING",
            "unit": unit,
            "run_dir": str(run_dir),
            "app_dir": str(app_dir),
            "started_epoch": started,
        }, indent=2), encoding="utf-8")

        last_text = ""
        deadline = time.monotonic() + ACTION_READY_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            current_text = journal(unit, started)
            for line in journal_delta(last_text, current_text):
                if line:
                    print(line, flush=True)
            last_text = current_text
            if "ACTION_SERVICE_READY" in last_text:
                state = {
                    "unit": unit,
                    "run_dir": str(run_dir),
                    "app_dir": str(app_dir),
                    "started_epoch": started,
                }
                STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")
                emit("ACTION_OVERLAY_READY", **state, physical_confirmation="REQUIRED")
                return state
            if any(marker in last_text for marker in (
                "FIRST_FRAME_TIMEOUT", '"event": "FAIL"', '"state": "DEGRADED"'
            )):
                raise ControllerError("Action runtime reported a fail-closed marker")
            props = service_properties(unit)
            if props.get("ActiveState") in ("failed", "inactive"):
                raise ControllerError(f"Action service stopped before READY: {props}")
            time.sleep(1)
        raise ControllerError("Timed out waiting for ACTION_SERVICE_READY")
    except BaseException as exc:
        emit("ACTION_START_FAILED", error=repr(exc), unit=unit, run_dir=str(run_dir))
        run(["systemctl", "stop", unit], check=False, timeout=30)
        try:
            restore_original(reason="ACTION_START_FAILED")
        except BaseException as restore_exc:
            emit("AUTOMATIC_RESTORE_FAILED", error=repr(restore_exc))
        raise


def status() -> dict:
    result = {
        "original": service_properties(ORIGINAL_SERVICE),
        "processes": processes(),
        "action_units": action_units(),
        "state_file": None,
    }
    if STATE_FILE.is_file():
        try:
            result["state_file"] = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception as exc:
            result["state_file"] = {"error": repr(exc)}
    emit("BOARD_STATUS", **result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("status", "load", "restore"))
    parser.add_argument("--app-dir", type=Path, default=Path("/home/xilinx/pl_reloader/action_v1_20260913"))
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Run this controller as root")

    try:
        if args.action == "status":
            status()
        elif args.action == "load":
            start_action(args.app_dir.resolve())
        else:
            restore_original(reason="USER_REQUEST")
        emit("CONTROLLER_COMPLETE", action=args.action)
        return 0
    except BaseException as exc:
        emit("CONTROLLER_FAILED", action=args.action, error=repr(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
