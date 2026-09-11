import json,sys
from pathlib import Path
R=Path(__file__).resolve().parent
W=R.parents[2]
sys.path.insert(0,str(W/'3_host/pynq/sd_boot_builder_v02'))
sys.path.insert(0,str(W/'4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/python_deps'))
from builder import Builder,inspect
try:
    inspect(W/'2_fpga/0_diaplay_test/vitis/display_test_wrapper.xsa')
except Exception as exc:
    (R/'alternate_xsa_rejection.txt').write_text(str(exc),encoding='utf-8')
result=Builder(W/'2_fpga/3_pynq_test/vitis/pynq_test_wrapper.xsa',mode='linux',full_image=True,rebuild_fsbl=True).execute()
(R/'full_build_result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
