"""Read the PYNQ runtime and optionally load the matched display overlay."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--load', action='store_true')
parser.add_argument('--bit', default=str(Path(__file__).with_name('overlay.bit')))
args = parser.parse_args()

if args.load:
    import fcntl
    lock = open('/run/lock/ees331_camera.lock', 'w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

import pynq
from pynq import Overlay, MMIO, allocate

print('PYNQ_VERSION', pynq.__version__, flush=True)
for path in (Path(args.bit), Path(args.bit).with_suffix('.hwh')):
    print('FILE', str(path), hashlib.sha256(path.read_bytes()).hexdigest(), flush=True)
print('FPGA_STATE', Path('/sys/class/fpga_manager/fpga0/state').read_text().strip(), flush=True)
ol = Overlay(args.bit, download=False)
print('IP_DICT', json.dumps({k: {x: v.get(x) for x in ('type', 'phys_addr', 'addr_range', 'interrupts')}
                            for k, v in ol.ip_dict.items()}, default=str), flush=True)
print('CLOCK_DICT', json.dumps(ol.clock_dict, default=str), flush=True)
if args.load:
    ol.download()
    print('OVERLAY_DOWNLOAD_RETURNED', ol.is_loaded(), flush=True)
    print('FPGA_STATE', Path('/sys/class/fpga_manager/fpga0/state').read_text().strip(), flush=True)
    desc = ol.ip_dict['axi_vdma_0']
    regs = MMIO(desc['phys_addr'], desc['addr_range'])
    print('VDMA_RESET_REGS', {hex(x): hex(regs.read(x)) for x in (0, 4, 0x28, 0x30, 0x34)}, flush=True)
    buf = allocate(shape=(3, 1024 * 1024), dtype='u1')
    print('BUFFER', hex(buf.device_address), buf.nbytes, 'coherent', buf.coherent, flush=True)
    buf.freebuffer()
