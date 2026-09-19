#!/usr/bin/env python3
"""run25: restore FPGA0_CLK_CTRL = 0x00200500 (IO_PLL, div0=5, div1=2 -> 100 MHz).

Attempt-2's repair write (0x205) landed in the wrong bits per the now-adjudicated
hardware layout (DIVISOR0[13:8] / DIVISOR1[25:20] / SRCSEL[5:4], bits [3:0]
reserved write-ignored), leaving div1=0 -> undefined fabric clock. This puts the
board back to the state Overlay.download() itself programs (which is correct).
"""
import mmap
import os
import struct

fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, offset=0xF8000000)


def r(off):
    return struct.unpack('<I', m[off:off + 4])[0]


def w(off, val):
    m[off:off + 4] = struct.pack('<I', val)


before = r(0x170)
w(0x170, 0x00200500)
after = r(0x170)
print('restore FPGA0_CLK_CTRL: before=0x%08X wrote=0x00200500 readback=0x%08X'
      % (before, after))
d0, d1, src = (after >> 8) & 0x3F, (after >> 20) & 0x3F, (after >> 4) & 0x3
io = ((r(0x108) >> 12) & 0x7F) * (1000.0 / 30.0)
print('layout DIV0[13:8]=%d DIV1[25:20]=%d SRCSEL[5:4]=%d IO_PLL=%.2f -> true=%.3f MHz'
      % (d0, d1, src, io, io / (d0 * d1) if d0 and d1 else -1))
assert after == 0x00200500, 'restore failed'
print('RESTORED_100MHZ_OK')
