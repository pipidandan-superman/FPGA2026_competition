import json
from pynq import Overlay, Clocks
o=Overlay('/home/xilinx/axilt_test_20260913_run01/AXI_LITE_test.bit',download=False)
print('PARSE_ONLY',json.dumps(dict(clocks=o.clock_dict,ip=o.ip_dict,mem=o.mem_dict),default=str),flush=True)
print('LIVE_FCLK',Clocks.fclk0_mhz,flush=True)
