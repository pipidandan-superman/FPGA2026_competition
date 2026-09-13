"""Export only existing board settings; remove calculated GUI bookkeeping."""
import json
import sys
from pathlib import Path

source, dest = map(Path, sys.argv[1:3])
bd = json.loads(source.read_text(encoding="utf-8-sig"))
if bd["design"]["design_info"]["device"] != "xc7z020clg484-1":
    raise ValueError("Unexpected board part")
params = bd["design"]["components"]["processing_system7_0"]["parameters"]
lines = ["# Board configuration extracted from the run-local baseline BD.", "set board_cfg [list]"]
for key, item in sorted(params.items()):
    if key.startswith(("PCW_ACT_", "PCW_CLK", "PCW_EN_", "PCW_MIO_TREE")):
        continue
    value = item["value"]
    if isinstance(value, list):
        value = "".join(value)
    if any(c in str(value) for c in "{}\n\r"):
        raise ValueError("Unsupported Tcl value")
    lines.append("lappend board_cfg CONFIG." + key + " {" + str(value) + "}")
lines += [
    "set_property -dict $board_cfg $ps",
    "set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 {0} CONFIG.PCW_USE_S_AXI_HP1 {0} CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {0} CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}] $ps",
]
dest.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("PS_CONFIG_EXPORTED", len(lines) - 2)
