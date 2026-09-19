#!/usr/bin/env python3
"""run25 CK_F recon v2 (read-only): raw SLCR via /dev/mem, no pynq Device needed.

Purpose: pin down true PLL frequencies (FBDIV [18:12], ref 33.3333 MHz),
FPGA0_CLK_CTRL current (post pynq-write) state, and FPGA1-3 boot residuals
to adjudicate the pynq 3.0.1 field-offset bug vs UG585 hardware truth.
"""
import mmap
import os
import struct

fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, offset=0xF8000000)


def r(off):
    return struct.unpack('<I', m[off:off + 4])[0]


REF = 1000.0 / 30.0  # 33.3333 MHz crystal

print('== PLL_CTRL raw (FBDIV=[18:12]) ==')
plls = {}
for name, off in (('ARM', 0x100), ('DDR', 0x104), ('IO', 0x108)):
    v = r(off)
    fb = (v >> 12) & 0x7F
    plls[name] = fb
    print('%-4s off=0x%03x raw=0x%08X FBDIV=%d -> %.2f MHz (ref 33.3333)'
          % (name, off, v, fb, fb * REF))

print()
print('== CPU + FPGA clk ctrl raw (UG585: srcsel[25:20] div1[13:8] div0[4:0]) ==')
ac = r(0x120)
print('ARM_CLK_CTRL 0x120 raw=0x%08X  div[13:8]=%d src[5:4]=%d'
      % (ac, (ac >> 8) & 0x3F, (ac >> 4) & 0x3))
for i, off in enumerate((0x170, 0x180, 0x190, 0x1A0)):
    v = r(off)
    src, d1, d0 = (v >> 20) & 0xF, (v >> 8) & 0x3F, v & 0x1F
    srcname = {0: 'IO', 1: 'IO', 2: 'ARM', 3: 'DDR'}.get(src, 'RESERVED(%d)' % src)
    pll_hz = {0: plls['IO'], 1: plls['IO'], 2: plls['ARM'], 3: plls['DDR']}.get(src)
    freq = ('%.2f' % (pll_hz * REF / (max(d0, 1) * d1))) if (pll_hz and d1) else '?'
    print('FPGA%d_CLK_CTRL 0x%03X raw=0x%08X  src=%s div0=%d div1=%d -> true=%s MHz'
          % (i, off, v, srcname, d0, d1, freq))
print()
print('(FPGA0 = post pynq-write state this session; FPGA1-3 = untouched boot residual)')
