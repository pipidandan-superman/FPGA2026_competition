"""Run register acceptance on EES-331 PYNQ; restore the existing camera service."""
import argparse
import fcntl
import hashlib
import json
import os
import random
import subprocess
import sys
import time
from pathlib import Path

from axilt import Axilt


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def service_state():
    p = subprocess.run(["systemctl", "is-active", "ees331-camera"],
                       text=True, capture_output=True)
    return p.stdout.strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bit", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--library", type=Path,
                        default=Path(__file__).with_name("libmmio_ordered.so"))
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--rounds", type=int, default=1000)
    args = parser.parse_args()
    if args.rounds < 1000:
        parser.error("Formal register acceptance requires at least 1000 rounds")
    if os.geteuid() != 0:
        parser.error("Run through the board's PYNQ Python as root")
    args.run_dir.mkdir(parents=True, exist_ok=False)
    log = (args.run_dir / "events.jsonl").open("x", encoding="utf-8")
    summary = dict(stage="REG_BOARD", state="INCOMPLETE", completed=0, reloads=0,
                   recovery="NOT_STARTED", bram="NOT_STARTED")
    owner = None
    camera_lock = None
    stopped = False

    def event(kind, **details):
        row = dict(event=kind, monotonic=time.monotonic(), **details)
        log.write(json.dumps(row) + "\n")
        log.flush()
        print(json.dumps(row), flush=True)

    try:
        files = json.loads(args.manifest.read_text(encoding="utf-8-sig"))["files"]
        for suffix in (".bit", ".hwh"):
            path = args.bit.with_suffix(suffix)
            if sha(path) != files[path.name]["sha256"].lower():
                raise RuntimeError("Artifact hash mismatch: " + str(path))
        owner = open("/run/lock/ees331_axilt.lock", "a")
        fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if service_state() != "active":
            raise RuntimeError("Camera service not active; automatic recovery target unconfirmed")
        if not args.library.is_file():
            raise RuntimeError("Compile the ARM MMIO helper before board acceptance")
        event("PREFLIGHT", bit_sha256=sha(args.bit),
              hwh_sha256=sha(args.bit.with_suffix(".hwh")),
              helper_sha256=sha(args.library))
        stopped = True
        subprocess.run(["systemctl", "stop", "ees331-camera"], check=True)
        camera_lock = open("/run/lock/ees331_camera.lock", "a")
        fcntl.flock(camera_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        from pynq import Overlay, __version__
        event("PYNQ_RUNTIME", version=__version__)

        def load():
            overlay = Overlay(str(args.bit), download=False)
            desc = overlay.ip_dict["axi_lite_test_0"]
            if desc["addr_range"] != 4096:
                raise RuntimeError("Wrong CSR range in HWH")
            # Download only after manifest and HWH checks.
            overlay.download()
            event("OVERLAY_LOADED", ip=desc["phys_addr"], clocks=overlay.clock_dict)
            return overlay, Axilt.from_overlay(overlay, args.library)

        overlay, driver = load()
        if driver.read("EXEC_COUNT") or driver.read("ACCEPT_SEQ") or driver.read("STATUS") != 1:
            raise RuntimeError("Reset state mismatch")
        rng = random.Random(12345)
        for index in range(args.rounds):
            value = rng.getrandbits(32)
            driver.write("SCRATCH", value)
            if driver.read("SCRATCH") != value:
                raise RuntimeError("Scratch register mismatch")
            result = driver.execute(value)
            # Software rejection is logged separately from RTL SLVERR simulation.
            try:
                driver.execute(value, seq=result["seq"])
            except ValueError:
                pass
            else:
                raise RuntimeError("Duplicate sequence was not rejected")
            if driver.read("EXEC_COUNT") != index + 1:
                raise RuntimeError("Duplicate caused an execution")
            summary["completed"] += 1
            event("REGISTER_COMMAND_PASS", index=index, **result)
        for index in range(3):
            del driver, overlay
            overlay, driver = load()
            if (driver.read("EXEC_COUNT") or driver.read("ACCEPT_SEQ") or
                    driver.read("DONE_SEQ") or driver.read("SCRATCH") or
                    driver.read("STATUS") != 1):
                raise RuntimeError("Overlay reload did not reset state")
            result = driver.execute(0x13579BDF)
            if result["seq"] != 1:
                raise RuntimeError("New reset epoch did not start at sequence 1")
            summary["reloads"] += 1
            event("RELOAD_PASS", index=index, **result)
        summary["state"] = "TEST_PASS_RECOVERY_PENDING"
    except BaseException as exc:
        summary["state"] = "FAIL"
        summary["error"] = repr(exc)
        event("FAIL", error=repr(exc))
    finally:
        if camera_lock is not None:
            camera_lock.close()
        if stopped:
            try:
                subprocess.run(["systemctl", "start", "ees331-camera"], check=True)
                time.sleep(3)
                if service_state() != "active":
                    raise RuntimeError("Camera service failed to restart")
                summary["recovery"] = "SERVICE_ACTIVE_VIDEO_CHECK_PENDING"
                event("CAMERA_SERVICE_RESTORED")
            except BaseException as exc:
                summary["recovery"] = "FAIL"
                summary["state"] = "FAIL"
                summary["recovery_error"] = repr(exc)
                event("RECOVERY_FAIL", error=repr(exc))
        if owner is not None:
            owner.close()
        if summary["state"] == "TEST_PASS_RECOVERY_PENDING":
            summary["state"] = "REGISTER_TEST_PASS"
            summary["marker"] = "AXILT_REG_BOARD_TEST_PASS"
        (args.run_dir / "result.json").write_text(
            json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        log.close()
    # Video restoration requires a separate real-frame/HDMI check.
    return 0 if summary["state"] == "REGISTER_TEST_PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
