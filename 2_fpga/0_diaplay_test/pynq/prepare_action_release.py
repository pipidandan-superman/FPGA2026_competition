"""Create a new paired v1 deployment directory after simulation/build gates."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile
from action_hardware_contract import validate_action_hardware_contract

ROOT = Path(__file__).resolve().parents[3]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(build, out):
    if out.exists():
        raise RuntimeError("Release already exists; choose a new directory")
    status = json.loads((build/"process_status.json").read_text(encoding="utf-8-sig"))
    if status["state"] != "PASS":
        raise RuntimeError("Main build gate failed")
    stem = "display_test_axi_action_uart"
    contract = validate_action_hardware_contract(build/"release"/(stem+".hwh"))
    for run_name, marker in (
            ("2026-09-13_action_v1_rtl_run01", "AXI_ACTION_RTL_PASS"),
            ("2026-09-13_action_v1_reset_baud_run01", "ACTION_RESET_BAUD_PASS")):
        run = ROOT/"4_metrics/logs"/run_name
        state=json.loads((run/"process_status.json").read_text(encoding="utf-8-sig"))
        if state["state"] != "PASS" or marker not in (run/"vivado_console.log").read_text(encoding="utf-8-sig"):
            raise RuntimeError("Simulation gate failed")
        for name in ("axi_lite_slave", "axi_action_reg_bank", "action_uart_tx",
                     "action_command_executor", "axi_action_control_top"):
            if digest(ROOT/"2_fpga/2_axi_lite_test/rtl"/(name+".v")) != digest(run/"rtl"/(name+".v")):
                raise RuntimeError("RTL differs from accepted simulation: "+name)
    # XSA must contain the identical bitstream and HWH delivered to PYNQ.
    with zipfile.ZipFile(build/"release"/(stem+".xsa")) as archive:
        for suffix in (".bit", ".hwh"):
            wanted = digest(build/"release"/(stem+suffix))
            if sum(hashlib.sha256(archive.read(n)).hexdigest()==wanted
                   for n in archive.namelist() if n.endswith(suffix)) != 1:
                raise RuntimeError("XSA/pair mismatch: "+suffix)
    out.mkdir(parents=True)
    (out/"build_artifacts").mkdir()
    for suffix in (".bit", ".hwh", ".xsa"):
        target = out/"build_artifacts" if suffix == ".xsa" else out
        shutil.copy2(build/"release"/(stem+suffix),target/(stem+suffix))
    main=ROOT/"2_fpga/0_diaplay_test/pynq"
    independent=ROOT/"2_fpga/2_axi_lite_test/pynq"
    for name in ("camera.py","camera_action_v1.py","main_hardware_contract.py",
                 "action_hardware_contract.py","run_action_v1.sh"):
        shutil.copy2(main/name,out/name)
    for name in ("action_protocol.py","action_driver.py","action_service.py","axilt.py","mmio_ordered.c"):
        shutil.copy2(independent/name,out/name)
    manifest=dict(marker="ACTION_V1_RELEASE_PASS",hardware=contract,build=str(build),
                  board_validated=False, files={})
    for path in out.rglob("*"):
        if path.is_file():
            manifest["files"][path.relative_to(out).as_posix()]=dict(sha256=digest(path),bytes=path.stat().st_size)
    (out/"release_manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    return manifest


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--build",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args()
    print(json.dumps(prepare(args.build,args.out),indent=2))
