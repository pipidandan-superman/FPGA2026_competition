import ast
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path("E:/competition/2_fpga/2_axi_lite_test")
run = Path("E:/competition/4_metrics/logs/2026-09-12_axilt_local_project_run01")
project = root / "proj"
checks = []
def check(name, value, detail=None):
    checks.append(dict(name=name, passed=bool(value), detail=detail))
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
bd_path = project / "AXI_LITE_test.srcs/sources_1/bd/AXI_LITE_test/AXI_LITE_test.bd"
bd = json.loads(bd_path.read_text(encoding="utf-8-sig"))
check("BD name", bd["design"]["design_info"]["name"] == "AXI_LITE_test")
check("BD validated", bd["design"]["design_info"]["validated"] == "true")
check("Part", bd["design"]["design_info"]["device"] == "xc7z020clg484-1")
xpr = ET.parse(project / "AXI_LITE_test.xpr")
sources = []
for node in xpr.findall(".//FileSet[@Name='sources_1']/File"):
    path = node.get("Path")
    for key, value in {
        "$PPRDIR": project,
        "$PSRCDIR": project / "AXI_LITE_test.srcs",
        "$PGENDIR": project / "AXI_LITE_test.gen",
    }.items():
        path = path.replace(key, str(value))
    resolved = Path(path).resolve()
    sources.append(str(resolved))
    check("Source exists", resolved.is_file(), str(resolved))
check("Live .v module reference", str((root / "rtl/axi_lite_test_top.v").resolve()) in sources)
top = xpr.find(".//FileSet[@Name='sources_1']/Config/Option[@Name='TopModule']")
check("Verilog system top", top is not None and top.get("Val") == "AXI_LITE_test_wrapper")
for item in json.loads((run / "baseline_hashes.json").read_text(encoding="utf-8-sig")):
    check("Baseline unchanged", sha(Path(item["path"])).upper() == item["sha256"], item["path"])
for item in json.loads((run / "rtl_simulation_gate.json").read_text(encoding="utf-8-sig")):
    check("RTL still simulated version", sha(Path(item["path"])).upper() == item["sha256"], item["path"])
manifest = json.loads((run / "release/artifact_manifest.json").read_text())
for name, info in manifest["files"].items():
    check("Local release matches evidence", sha(project / "release" / name) == info["sha256"], name)
links = []
for path in [root / "README.md", *(root / "doc").glob("*.md")]:
    for label, target in re.findall(r"\[([^\]]+)\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
        if not target.startswith(("http:", "https:", "#")):
            dest = (path.parent / target.split("#")[0]).resolve()
            links.append(str(dest))
            check("Local document link", dest.exists(), str(dest))
for path in project.glob("*.py"):
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
check("Python build helpers parse", True)
notebook = json.loads((root / "pynq/demo.ipynb").read_text(encoding="utf-8"))
for cell in notebook["cells"]:
    if cell["cell_type"] == "code":
        ast.parse("".join(cell["source"]))
check("Notebook code parses", True)
result = dict(marker="AXI_LITE_TEST_POST_BUILD_AUDIT_PASS" if all(c["passed"] for c in checks) else "FAIL",
              checks=checks, link_count=len(links))
(run / "post_build_audit.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps(dict(marker=result["marker"], checks=len(checks), links=len(links),
                     failures=[c for c in checks if not c["passed"]]), indent=2))
raise SystemExit(0 if result["marker"].endswith("_PASS") else 1)

