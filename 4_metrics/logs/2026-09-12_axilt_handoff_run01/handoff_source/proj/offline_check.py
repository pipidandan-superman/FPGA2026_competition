"""Preserve software tests and read-only board preflight in a fresh run."""
import argparse
import ast
import hashlib
import json
import socket
import shutil
import subprocess
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("run_dir", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
args.run_dir.mkdir(parents=True, exist_ok=False)
shutil.copytree(root, args.run_dir / "source")
sources = []
for path in sorted(root.rglob("*")):
    if path.is_file():
        sources.append(dict(path=str(path), size=path.stat().st_size,
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        if path.suffix == ".py":
            ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        if path.suffix == ".ipynb":
            notebook = json.loads(path.read_text(encoding="utf-8"))
            for cell in notebook["cells"]:
                if cell["cell_type"] == "code":
                    ast.parse("".join(cell["source"]))
(args.run_dir / "source_hashes.json").write_text(
    json.dumps(sources, indent=2) + "\n", encoding="utf-8")
p = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover",
                    "-s", str(root / "pynq"), "-p", "test_driver.py", "-v"],
                   capture_output=True, text=True)
(args.run_dir / "driver_tests.txt").write_text(p.stdout + p.stderr, encoding="utf-8")
board = dict(address="192.168.240.10", port=22, state="UNCONFIRMED")
try:
    with socket.create_connection((board["address"], 22), timeout=5) as sock:
        sock.settimeout(5)
        banner = sock.recv(128)
        board["banner"] = banner.decode("ascii", errors="replace")
        board["state"] = "SSH_BANNER_SEEN" if banner.startswith(b"SSH-") else "NO_SSH_BANNER"
except OSError as exc:
    board["state"] = "UNREACHABLE"
    board["error"] = str(exc)
(args.run_dir / "board_preflight.json").write_text(
    json.dumps(board, indent=2) + "\n", encoding="utf-8")
result = dict(marker="AXILT_SOFTWARE_OFFLINE_PASS" if p.returncode == 0 else "FAIL",
              driver_exit=p.returncode, board=board, board_tests_executed=False,
              arm_helper_compiled=False)
audit = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                        "-File", "E:/competition/4_metrics/scripts/audit_project_skill_paths.ps1"],
                       text=True, capture_output=True)
(args.run_dir / "skill_path_audit.txt").write_text(audit.stdout + audit.stderr, encoding="utf-8")
result["skill_path_audit_exit"] = audit.returncode
if audit.returncode:
    result["marker"] = "FAIL"
(args.run_dir / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, indent=2))
sys.exit(p.returncode or audit.returncode)
