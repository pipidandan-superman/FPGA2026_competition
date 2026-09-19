#!/usr/bin/env python3
"""postcheck_p0b.py - P0-B run02 restoration/final-state read (verify-only).

After the driver process exits (zocl client released), prove the P0 baseline
overlay is still mounted and responsive via raw /dev/mem reads only:
  GEMM_ID @0x43C00000 must be 0x20260919
  CSR_ID  @0x43C10000 must be 0x594F4C32
  FPGA0_CLK_CTRL @0xF8000170 must be 0x00200500 (true 100 MHz intent)
No writes of any kind. Run as root (bare user gets PermissionError on /dev/mem).
"""
import mmap
import os
import sys
import time

PAGE = 0x1000


def rd(phys):
    base = phys & ~(PAGE - 1)
    off = phys - base
    fd = os.open('/dev/mem', os.O_RDONLY)
    try:
        m = mmap.mmap(fd, PAGE, mmap.MAP_SHARED, mmap.PROT_READ, offset=base)
        try:
            return int.from_bytes(m[off:off + 4], 'little')
        finally:
            m.close()
    finally:
        os.close(fd)


def main():
    print('[p0b.post %s] begin' % time.strftime('%H:%M:%S'), flush=True)
    g = rd(0x43C00000)
    c = rd(0x43C10000)
    f = rd(0xF8000170)
    print('[p0b.post] GEMM_ID=0x%08X (exp 0x20260919)' % g)
    print('[p0b.post] CSR_ID =0x%08X (exp 0x594F4C32)' % c)
    print('[p0b.post] FPGA0_CLK_CTRL=0x%08X (exp 0x00200500)' % f)
    ok = (g == 0x20260919) and (c == 0x594F4C32) and (f == 0x00200500)
    print('[p0b.post] %s' % ('P0B_POSTCHECK_PASS' if ok else 'P0B_POSTCHECK_FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
