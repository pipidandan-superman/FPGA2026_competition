import sys
import json
import hashlib
import subprocess
from pathlib import Path
RUN=Path(__file__).resolve().parent
ROOT=Path('E:/competition/2_fpga/2_axi_lite_test')
sys.path.insert(0,str(ROOT/'pynq'))
from hardware_contract import validate_reset_contract
result=json.loads((RUN/'board_result.json').read_text())
assert result['marker']=='AXILT_REG_BOARD_TEST_PASS' and result['completed']==1000 and result['reloads']==3
events=[json.loads(line) for line in (RUN/'events.jsonl').read_text().splitlines()]
commands=[r for r in events if r['event']=='REGISTER_COMMAND_PASS']
assert len(commands)==1000
for i,r in enumerate(commands,1):
    assert r['seq']==r['accept_seq']==r['done_seq']==r['exec_count']==i
    assert r['result']==(r['input']^0xffffffff) and r['error']==0
assert len([r for r in events if r['event']=='RELOAD_PASS'])==3
assert json.loads((RUN/'video_after.json').read_text())['pass']
build=Path('E:/competition/4_metrics/logs/2026-09-13_axilt_reset_fix_build_run01')
try:
    validate_reset_contract(build/'release_before/AXI_LITE_test.hwh')
except ValueError as e:
    old_rejected=str(e)
else:
    raise AssertionError('Original faulty HWH accepted')
validate_reset_contract(build/'release/AXI_LITE_test.hwh')
test=subprocess.run([sys.executable,'-B','-m','unittest','discover','-s',str(ROOT/'pynq'),'-p','test_*.py','-v'],capture_output=True,text=True)
(RUN/'unit_tests.log').write_text(test.stdout+test.stderr)
assert test.returncode==0
rtl=[]
for p in (ROOT/'rtl').glob('*.v'):
    old=Path('E:/competition/4_metrics/logs/2026-09-12_axilt_reg_sim_run02/source/rtl')/p.name
    assert p.read_bytes()==old.read_bytes()
    rtl.append(dict(name=p.name,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
summary=dict(marker='AXILT_REG_BOARD_EVIDENCE_AUDIT_PASS',commands=1000,reloads=3,unit_tests=15,rtl_unchanged=rtl,old_hwh_rejected=old_rejected,hdmi='AWAIT_USER_CONFIRMATION',bram='NOT_STARTED')
(RUN/'audit.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary,indent=2))
