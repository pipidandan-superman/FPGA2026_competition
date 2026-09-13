#!/usr/bin/env python3
"""Exercise AXI registers while the integrated camera/HDMI/UDP path is live."""
import argparse
import fcntl
import hashlib
import json
import os
import random
import sys
import time
from pathlib import Path

from axi_lite import Axilt
from main_hardware_contract import validate_main_hardware_contract


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bit", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--library", type=Path,
                        default=Path(__file__).with_name("libmmio_ordered.so"))
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--rounds", type=int, default=1000)
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Run with the board PYNQ Python as root")
    if args.rounds < 1000:
        parser.error("Coexistence acceptance requires at least 1000 commands")
    args.run_dir.mkdir(parents=True, exist_ok=False)
    events = (args.run_dir / "events.jsonl").open("x", encoding="utf-8")
    result = {"stage": "MAIN_AXI_VIDEO_COEXIST", "state": "INCOMPLETE",
              "commands": 0, "seed": 3312026}

    def event(kind, **details):
        row = {"event": kind, "monotonic": time.monotonic(), **details}
        events.write(json.dumps(row) + "\n")
        events.flush()
        os.fsync(events.fileno())
        if kind != "COMMAND_PASS" or details["index"] % 100 == 0:
            print(json.dumps(row), flush=True)

    owner = None
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8-sig"))
        for suffix in (".bit", ".hwh"):
            path = args.bit.with_suffix(suffix)
            expected = manifest["files"][path.name]["sha256"].lower()
            if sha256(path) != expected:
                raise RuntimeError(f"Artifact hash mismatch: {path}")
        event("HARDWARE_CONTRACT",
              **validate_main_hardware_contract(args.bit.with_suffix(".hwh")))
        if Path("/sys/class/fpga_manager/fpga0/state").read_text().strip() != "operating":
            raise RuntimeError("FPGA manager is not operating")
        if not args.library.is_file():
            raise RuntimeError("Compile libmmio_ordered.so before the test")
        owner = open("/run/lock/ees331_axilt.lock", "a")
        fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
        from pynq import Overlay, __version__
        overlay = Overlay(str(args.bit), download=False)
        driver = Axilt.from_overlay(overlay, args.library)
        event("PREFLIGHT_PASS", pynq=__version__, bit_sha256=sha256(args.bit),
              hwh_sha256=sha256(args.bit.with_suffix(".hwh")),
              status=driver.status())
        if driver.read("EXEC_COUNT") or driver.read("ACCEPT_SEQ") or \
                driver.read("DONE_SEQ") or driver.read("STATUS") != 1:
            raise RuntimeError("Integrated AXI block did not begin in reset state")
        rng = random.Random(result["seed"])
        for index in range(args.rounds):
            value = rng.getrandbits(32)
            driver.write("SCRATCH", value)
            if driver.read("SCRATCH") != value:
                raise RuntimeError(f"Scratch mismatch at command {index}")
            observed = driver.execute(value)
            try:
                driver.execute(value, seq=observed["seq"])
            except ValueError:
                pass
            else:
                raise RuntimeError("Duplicate sequence was not rejected")
            if driver.read("EXEC_COUNT") != index + 1:
                raise RuntimeError("Duplicate command changed EXEC_COUNT")
            result["commands"] += 1
            event("COMMAND_PASS", index=index, **observed)
        result.update(state="PASS", marker="MAIN_AXI_VIDEO_COEXIST_PASS",
                      final_status=driver.status(),
                      exec_count=driver.read("EXEC_COUNT"))
        event("TEST_PASS", commands=result["commands"],
              exec_count=result["exec_count"])
    except BaseException as exc:
        result.update(state="FAIL", error=repr(exc))
        event("FAIL", error=repr(exc))
    finally:
        if owner is not None:
            owner.close()
        (args.run_dir / "result.json").write_text(
            json.dumps(result, indent=2) + "\n", encoding="utf-8")
        events.close()
    return 0 if result["state"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
