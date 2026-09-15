"""Audit a generated release and emit hashes. Does not touch source or board."""
import argparse
import hashlib
import json
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("build_run", type=Path)
    args = parser.parse_args()
    run = args.build_run.resolve()
    release = run / "release"
    out = release / "artifact_manifest.json"
    if out.exists():
        raise RuntimeError("Release already sealed")
    status = json.loads((run / "process_status.json").read_text(encoding="utf-8-sig"))
    if status["state"] != "PASS":
        raise RuntimeError("Build not passed")
    tree = ET.parse(release / "axilt.hwh")
    ranges = [n.attrib for n in tree.iter("MEMRANGE")
              if n.get("INSTANCE") == "axi_lite_test_0"]
    if len(ranges) != 1:
        raise RuntimeError("Expected exactly one register address range: " + repr(ranges))
    attrs = ranges[0]
    if int(attrs["BASEVALUE"], 16) != 0x43C00000 or int(attrs["HIGHVALUE"], 16) != 0x43C00FFF:
        raise RuntimeError("Unexpected physical range")
    ps = next(n for n in tree.iter("MODULE") if n.get("INSTANCE") == "ps7")
    params = {n.get("NAME"): n.get("VALUE") for n in ps.iter("PARAMETER")}
    if float(params["PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ"]) != 100:
        raise RuntimeError("Wrong control clock")
    reset = next(n for n in tree.iter("MODULE") if n.get("INSTANCE") == "control_reset")
    reset_params = {n.get("NAME"): n.get("VALUE") for n in reset.iter("PARAMETER")}
    if reset_params.get("C_EXT_RESET_HIGH") != "0":
        raise RuntimeError("Wrong external reset polarity")
    with zipfile.ZipFile(release / "axilt.xsa") as archive:
        for ext in (".bit", ".hwh"):
            entry = "axilt" + ext
            if entry not in archive.namelist():
                raise RuntimeError("Expected root design artifact " + entry)
            if archive.read(entry) != (release / entry).read_bytes():
                raise RuntimeError("XSA release mismatch: " + ext)
    files = {p.name: dict(size=p.stat().st_size, sha256=digest(p))
             for p in sorted(release.iterdir()) if p.suffix in (".bit", ".hwh", ".xsa")}
    result = dict(marker="AXILT_RELEASE_AUDIT_PASS", stage="REGISTER_ONLY",
                  board_status="PENDING", base=attrs["BASEVALUE"], range=4096,
                  control_clock_mhz=100, files=files)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
