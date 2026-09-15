import os
import json
import time
import fcntl
from pathlib import Path
from pynq import Overlay, MMIO
base=Path('/home/xilinx/axilt_test_20260913_run01')
with (base/'load_only_events.jsonl').open('x') as log:
    def event(name,**data):
        row=json.dumps(dict(event=name,monotonic=time.monotonic(),**data))
        log.write(row+'\n'); log.flush(); os.fsync(log.fileno())
        print(row,flush=True)
    owner=open('/run/lock/ees331_axilt.lock','a')
    camera=open('/run/lock/ees331_camera.lock','a')
    fcntl.flock(owner,fcntl.LOCK_EX|fcntl.LOCK_NB)
    fcntl.flock(camera,fcntl.LOCK_EX|fcntl.LOCK_NB)
    slcr=MMIO(0xf8000000,4096)
    def regs():
        return {hex(x):hex(slcr.read(x)) for x in (0x100,0x108,0x170,0x240,0x900)}
    event('BEFORE_PARSE',ps=regs())
    o=Overlay(str(base/'AXI_LITE_test.bit'),download=False)
    event('PARSED',clocks=o.clock_dict)
    def wrap(name):
        old=getattr(o.device,name)
        def call(*args,**kwargs):
            event(name+'_ENTER')
            result=old(*args,**kwargs)
            event(name+'_EXIT')
            return result
        setattr(o.device,name,call)
    for name in ('shutdown','gen_cache','set_axi_port_width','_xrt_download'):
        wrap(name)
    event('DOWNLOAD_ENTER')
    o.download()
    event('DOWNLOAD_EXIT',ps=regs(),state=Path('/sys/class/fpga_manager/fpga0/state').read_text())
    event('LOAD_ONLY_PASS_NO_CSR_ACCESS')
