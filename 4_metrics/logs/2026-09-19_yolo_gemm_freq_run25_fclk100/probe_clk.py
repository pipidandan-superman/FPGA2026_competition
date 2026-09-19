#!/usr/bin/env python3
"""run25 CK_F recon (read-only): pynq 3.0.1 clock field offsets vs UG585 truth.

No Overlay download, no SLCR writes. Dumps raw SLCR + pynq accessor view so the
FPGA0_CLK_CTRL bit-layout mismatch can be adjudicated from evidence.
"""
from pynq import MMIO, Clocks

SLCR = MMIO(0xF8000000, 0x200)


def dump(name, off):
    v = SLCR.read(off)
    print('%-14s off=0x%03x raw=0x%08X' % (name, off, v))
    return v


print('== SLCR raw ==')
arm_pll = dump('ARM_PLL_CTRL', 0x100)
ddr_pll = dump('DDR_PLL_CTRL', 0x104)
io_pll = dump('IO_PLL_CTRL', 0x108)
dump('ARM_CLK_CTRL', 0x120)
f0 = dump('FPGA0_CLK_CTRL', 0x170)
dump('FPGA1_CLK_CTRL', 0x180)
dump('FPGA2_CLK_CTRL', 0x190)
dump('FPGA3_CLK_CTRL', 0x1A0)


def fb12(v):  # UG585 PLL_CTRL FBDIV candidate [17:12]
    return (v >> 12) & 0x3F


def fb14(v):  # alternate candidate [19:14]
    return (v >> 14) & 0x3F


print()
print('PLL FBDIV [17:12]: ARM=%d DDR=%d IO=%d' % (fb12(arm_pll), fb12(ddr_pll), fb12(io_pll)))
print('PLL FBDIV [19:14]: ARM=%d DDR=%d IO=%d' % (fb14(arm_pll), fb14(ddr_pll), fb14(io_pll)))
for tag, ref in (('ref=33.3333', 33.3333), ('ref=50.0', 50.0)):
    print('%s -> IO PLL=%.1f MHz (FBDIV[17:12] basis)' % (tag, ref * fb12(io_pll)))

src = (f0 >> 20) & 0xF
d1 = (f0 >> 8) & 0x3F
d0 = f0 & 0x1F
print()
print('FPGA0 UG585 decode: srcsel=%d div0=%d div1=%d' % (src, d0, d1))
pllmap = {0: 33.3333 * fb12(io_pll), 1: 33.3333 * fb12(io_pll),
          2: 33.3333 * fb12(arm_pll), 3: 33.3333 * fb12(ddr_pll)}
if src in pllmap and d1:
    print('true FCLK0 = %.2f MHz (div0=0 counted as /1)' % (pllmap[src] / (max(d0, 1) * d1)))

print()
print('== pynq accessor view (its own masks) ==')
try:
    print('Clocks.fclk0_mhz =', Clocks.fclk0_mhz)
except Exception as e:
    print('Clocks.fclk0_mhz raised:', repr(e))
try:
    c = Clocks._instance
    print('ref_clk_mhz =', c._ref_clk_mhz)
    reg = c.PL_CLK_CTRLS[0]
    print('pynq DIVISOR0=%s DIVISOR1=%s' % (reg.DIVISOR0, reg.DIVISOR1))
    for idx in range(3):
        try:
            print('pynq get_pll_mhz(%d) = %s' % (idx, c.get_pll_mhz(idx)))
        except Exception as e:
            print('pynq get_pll_mhz(%d) raised: %r' % (idx, e))
except Exception as e:
    print('pynq internals err:', repr(e))
