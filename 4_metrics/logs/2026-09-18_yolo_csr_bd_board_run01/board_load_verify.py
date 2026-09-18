#!/usr/bin/env python3
"""board_load_verify.py - load the yolo CSR overlay and verify, staged.

Maps 1:1 to zynq-pynq-overlay-workflow skill steps 4/5 + design contract:
  CK1 metadata  : Overlay(bit, download=False); HWH contract must show
                  u_yolo_csr at 0x43c10000 (module reference parses)
  CK2 download  : .download() as root with XILINX_XRT=/usr
  CK3 liveness  : fpga0 state == operating
  CK4 identity  : dmesg zocl 'locked, ref=1' delta == +1 (fresh load)
  CK5 L1 reads  : ID==0x594F4C32, VERSION==0x0300; log CAP0/CAP1/STATUS/
                  ERROR_STATUS/SCHED_STATUS (read class proven safe)
  CK6 L2 writes : MODEL_ID(0x20) scratch write/readback/restore, then
                  BUF window(0x3000) word0 write/readback - the real
                  table write path. Each write is preceded/followed by
                  dual-channel markers so a hard freeze pinpoints it.
  CK7 verdict   : BOARD_CSR_PASS only if every gate passed.

Dual-channel logging: stdout (host tee) + /dev/console (survives a
mid-run board freeze via COM6).
Usage (root): python3 board_load_verify.py <tag>
"""
import os, sys, time, hashlib, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
BIT = os.path.join(HERE, 'display_test_wrapper.bit')
tag = sys.argv[1] if len(sys.argv) > 1 else 'r1'

CSR_BASE = 0x43C10000
EXP_ID = 0x594F4C32
EXP_VERSION = 0x0300
A_VERSION, A_CAP0, A_CAP1, A_STATUS = 0x004, 0x008, 0x00C, 0x014
A_ERROR_STATUS, A_MODEL_ID, A_SCHED_STATUS = 0x018, 0x020, 0x128
A_BUF_WIN = 0x3000

results = {}

def emit(m):
    line = '[%s %s %s]' % (tag, m, time.strftime('%H:%M:%S'))
    print(line, flush=True)
    try:
        with open('/dev/console', 'a') as c:
            c.write(line + '\n'); c.flush()
    except Exception as e:
        print('[console-fail %r]' % e, flush=True)

def lock_count():
    out = subprocess.run(['dmesg'], capture_output=True, text=True).stdout
    return sum(1 for l in out.splitlines() if 'locked, ref=1' in l)

def main():
    emit('CK1a start bit_sha=%s' %
         hashlib.sha256(open(BIT, 'rb').read()).hexdigest()[:16])
    os.environ['XILINX_XRT'] = '/usr'
    from pynq import Overlay, MMIO
    ol = Overlay(BIT, download=False)
    ips = sorted(ol.ip_dict.keys())
    emit('CK1b ip_dict=%s' % ips)
    phys = None
    if 'u_yolo_csr' in ol.ip_dict:
        # PYNQ 3.0.1 key is 'phys_addr' (int); 'addr_range' is the aperture
        phys = ol.ip_dict['u_yolo_csr'].get('phys_addr')
    results['CK1'] = (phys == CSR_BASE)
    emit('CK1c u_yolo_csr phys=%s range=%s expect=0x%x -> %s'
         % (hex(phys) if phys is not None else None,
            ol.ip_dict.get('u_yolo_csr', {}).get('addr_range'),
            CSR_BASE, 'PASS' if results['CK1'] else 'FAIL'))
    if not results['CK1']:
        emit('CK7 BOARD_CSR_FAIL hwh_contract'); return 1

    pre = lock_count()
    emit('CK2a pre_locks=%d download_begin' % pre)
    ol.download()
    emit('CK2b download_returned')

    st = open('/sys/class/fpga_manager/fpga0/state').read().strip()
    emit('CK3 state=%s' % st)
    post = lock_count()
    results['CK4'] = (st == 'operating') and (post == pre + 1)
    emit('CK4 lock_delta=%d -> %s' % (post - pre,
         'PASS' if results['CK4'] else 'FAIL'))

    # ---- L1: read-only identity (safe class) ----
    m = MMIO(CSR_BASE, 0x10000)
    rid, rver = m.read(0x000), m.read(A_VERSION)
    cap0, cap1, rst = m.read(A_CAP0), m.read(A_CAP1), m.read(A_STATUS)
    erst, sst = m.read(A_ERROR_STATUS), m.read(A_SCHED_STATUS)
    emit('CK5a ID=0x%08X VERSION=0x%08X' % (rid, rver))
    emit('CK5b CAP0=0x%08X CAP1=0x%08X STATUS=0x%08X' % (cap0, cap1, rst))
    emit('CK5c ERR_STATUS=0x%08X SCHED_STATUS=0x%08X' % (erst, sst))
    results['CK5'] = (rid == EXP_ID) and (rver == EXP_VERSION)
    emit('CK5d identity -> %s' % ('PASS' if results['CK5'] else 'FAIL'))

    # ---- L2: first-write moment (kill-class on the old fabric) ----
    # L2a: fixed RW scratch register
    emit('CK6a MODEL_ID_write_begin')
    m.write(A_MODEL_ID, 0xA5A51234)
    emit('CK6b MODEL_ID_write_done readback_begin')
    rb = m.read(A_MODEL_ID)
    emit('CK6c MODEL_ID_readback=0x%08X expect=0xA5A51234 -> %s'
         % (rb, 'PASS' if rb == 0xA5A51234 else 'FAIL'))
    m.write(A_MODEL_ID, 0x00000000)
    emit('CK6d MODEL_ID_restored')
    results['CK6a'] = (rb == 0xA5A51234)

    # L2b: table window write path (BMG port A via window decode)
    emit('CK6e BUFWIN_write_begin')
    m.write(A_BUF_WIN, 0x11223344)
    emit('CK6f BUFWIN_write_done readback_begin')
    rb2 = m.read(A_BUF_WIN)
    emit('CK6g BUFWIN_readback=0x%08X expect=0x11223344 -> %s'
         % (rb2, 'PASS' if rb2 == 0x11223344 else 'FAIL'))
    results['CK6b'] = (rb2 == 0x11223344)

    ok = all(results.get(k) for k in ('CK1', 'CK4', 'CK5', 'CK6a', 'CK6b'))
    emit('CK7 %s' % ('BOARD_CSR_PASS' if ok else 'BOARD_CSR_FAIL'))
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main())
