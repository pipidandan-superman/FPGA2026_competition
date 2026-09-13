#!/usr/bin/env python3
"""Video + single-owner ACTL service on an explicitly audited v1 overlay."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import threading
import time
import zlib

import camera as video
from action_hardware_contract import validate_action_hardware_contract
from action_driver import ActionDriver
from action_service import ActionService


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bit", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--library", type=Path, default=Path(__file__).with_name("libmmio_ordered.so"))
    parser.add_argument("--peer", default="192.168.240.2")
    parser.add_argument("--fps", type=float, default=5)
    parser.add_argument("--seconds", type=float, default=0)
    args = parser.parse_args()
    if os.geteuid() != 0 or not 0 < args.fps <= 15 or args.seconds < 0:
        parser.error("Run as root; fps in (0,15]; seconds >= 0")
    args.evidence.mkdir(parents=True, exist_ok=False)
    event_lock = threading.Lock()
    events = (args.evidence/"events.jsonl").open("x", buffering=1)

    def emit(kind, **details):
        row = dict(event=kind, monotonic=time.monotonic(), **details)
        with event_lock:
            events.write(json.dumps(row)+"\n")
            events.flush()
            os.fsync(events.fileno())
        print(json.dumps(row), flush=True)

    signal.signal(signal.SIGTERM, video.request_stop)
    signal.signal(signal.SIGINT, video.request_stop)
    video.log = emit
    owners, camera, actions, udp = [], None, None, None
    action_error = None
    result = dict(state="INCOMPLETE")
    try:
        for name in ("ees331_camera", "ees331_axilt"):
            owner = open("/run/lock/"+name+".lock", "a")
            fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
            owners.append(owner)
        manifest = json.loads(args.manifest.read_text())
        if manifest["marker"] != "ACTION_V1_RELEASE_PASS":
            raise RuntimeError("Action v1 release was not audited")
        hashes = {}
        for suffix in (".bit", ".hwh"):
            path = args.bit.with_suffix(suffix)
            hashes[suffix] = manifest["files"][path.name]["sha256"]
            if hashlib.sha256(path.read_bytes()).hexdigest() != hashes[suffix]:
                raise RuntimeError("Artifact SHA256 mismatch: "+str(path))
        camera = video.Camera.__new__(video.Camera)
        video.Camera.__init__(camera, args.bit, hashes, validate_action_hardware_contract)
        camera.start()
        emit("VIDEO_READY_BEFORE_ACTION")
        try:
            emit("ACTION_ATTACH_BEGIN")
            actions = ActionService(ActionDriver.from_overlay(camera.overlay, args.library),
                                    args.peer, emit)
            actions.start()
        except Exception as exc:
            action_error = repr(exc)
            emit("ACTION_DISABLED_VIDEO_CONTINUES", error=action_error)
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 2*1024*1024)
        udp.settimeout(1)
        started = next_send = last_report = last_frame = time.monotonic()
        frames = packets = changes = 0
        first_crc = None
        last_image = None
        while not video.stopping and (not args.seconds or time.monotonic()-started < args.seconds):
            status = camera.status()
            if actions is not None and actions.error and action_error is None:
                action_error = actions.error
                emit("ACTION_DISABLED_VIDEO_CONTINUES", error=action_error)
            now = time.monotonic()
            if now >= next_send:
                frame = camera.snapshot()
                if frame is not None:
                    last_image = frame
                    crc = zlib.crc32(frame)
                    if frames == 0:
                        first_crc = crc
                        (args.evidence/"first_frame.bgr").write_bytes(frame)
                    changes += int(crc != first_crc)
                    for pid, packet in enumerate(video.datagrams(frame, frames, int(now*1e6))):
                        udp.sendto(packet, (args.peer,5000))
                        packets += 1
                        if (pid+1)%16 == 0:
                            time.sleep(.001)
                    frames += 1
                    last_frame = time.monotonic()
                    next_send = max(next_send+1/args.fps, last_frame)
            if time.monotonic()-last_frame > 5:
                raise RuntimeError("No stable video snapshot for 5 seconds")
            if now-last_report >= 2:
                emit("VIDEO_HEARTBEAT", frames=frames, packets=packets, changes=changes, **status)
                last_report = now
            time.sleep(.001)
        action_status = None
        if actions is not None and action_error is None:
            try:
                action_status = actions.driver.status()
            except Exception as exc:
                action_error = repr(exc)
        result = dict(state="DEGRADED" if action_error else "COMPLETE", frames=frames, packets=packets, changes=changes,
                      seconds=time.monotonic()-started, vdma=camera.status(),
                      action=action_status, action_error=action_error,
                      hdmi="MANUAL_CONFIRMATION_REQUIRED")
        if last_image is not None:
            (args.evidence/"last_frame.bgr").write_bytes(last_image)
    except BaseException as exc:
        result = dict(state="FAIL", error=repr(exc))
        emit("FAIL", error=repr(exc))
    finally:
        shutdown_errors = []
        for name, resource in (("action", actions), ("camera", camera)):
            try:
                if resource is not None and (name != "camera" or hasattr(resource, "mmio")):
                    resource.close()
            except BaseException as exc:
                shutdown_errors.append(name+": "+repr(exc))
        if shutdown_errors:
            result = dict(state="FAIL", prior_result=result,
                          error="Shutdown", details=shutdown_errors)
        if udp is not None:
            udp.close()
        for owner in owners:
            owner.close()
        emit("FINAL", **result)
        (args.evidence/"result.json").write_text(json.dumps(result,indent=2))
        events.close()
    return 0 if result["state"] == "COMPLETE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
