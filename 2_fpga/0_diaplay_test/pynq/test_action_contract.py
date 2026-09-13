"""Reject unsafe generated HWH mutations and the previous non-action overlay."""
import argparse
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from action_hardware_contract import validate_action_hardware_contract

parser=argparse.ArgumentParser()
parser.add_argument("--hwh",type=Path,required=True)
parser.add_argument("--prior",type=Path,required=True)
parser.add_argument("--out",type=Path,required=True)
args=parser.parse_args()
args.out.mkdir(parents=True,exist_ok=False)
validate_action_hardware_contract(args.hwh)
root=ET.parse(args.hwh).getroot()
tests=[]
def reject(name, tree):
    path=args.out/(name+".hwh")
    ET.ElementTree(tree).write(path)
    try:
        validate_action_hardware_contract(path)
    except ValueError as exc:
        tests.append(dict(test=name,rejected=True,error=str(exc)))
    else:
        raise RuntimeError("Unsafe HWH was accepted: "+name)

for pin, instance in (("aux_reset_in","control_const_zero"),
                      ("dcm_locked","control_const_zero"),
                      ("mb_debug_sys_rst","control_const_one")):
    tree=copy.deepcopy(root)
    module=next(n for n in tree.iter("MODULE") if n.get("INSTANCE")=="rst_ps7_0_50M")
    const=next(n for n in tree.iter("MODULE") if n.get("INSTANCE")==instance)
    module.find('./PORTS/PORT[@NAME="'+pin+'"]').set("SIGNAME",const.find('./PORTS/PORT[@NAME="dout"]').get("SIGNAME"))
    reject("wrong_"+pin,tree)
for port in ("PL_RS232_TX","ACTION_LED"):
    tree=copy.deepcopy(root)
    tree.find('./EXTERNALPORTS/PORT[@NAME="'+port+'"]').set("DIR","I")
    reject("wrong_"+port,tree)
tree=copy.deepcopy(root)
module=next(n for n in tree.iter("MODULE") if n.get("INSTANCE")=="axi_action_0")
module.find('./PORTS/PORT[@NAME="clk"]').set("CLKFREQUENCY","100000000")
reject("wrong_control_clock",tree)
try:
    validate_action_hardware_contract(args.prior)
except ValueError:
    tests.append(dict(test="prior_overlay",rejected=True))
else:
    raise RuntimeError("Previous non-action overlay was accepted")
result=dict(marker="ACTION_HWH_NEGATIVE_TEST_PASS",tests=tests)
(args.out/"result.json").write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
