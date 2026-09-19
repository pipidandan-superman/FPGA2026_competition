#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pl_m11.py 的 PC 端全流程自测（无 /dev/mem，无 PL）。

FakePL 以 stim 自身数据（DDR 镜像里的 W/X/bias_eff/M/shift + lut_all）
重算黄金 conv（语义 = yolo_runtime._conv / RTL 引擎合同），写入假 DDR；
pl_m11.main() 原封不动跑完 63 conv + 65 PS op + heads，判据：
  nerr==0 且 head sha256 == 9ce70525fc1732cd...（与 ModelSim 同一终判）。

自测通过 => 驱动解释器（步长/token 布局/DESC 打包位序无关部分/PS 语义/
head 转储/判据）在 PC 上闭环证毕；板端剩余未知 = 比特流 + HP 实流 +
DDR 一致性。FakePL.conv 亦留作板上单层 mismatch 时的黄金对照器。

用法：python pl_m11_selftest.py [--stim ../sim/stim/m11]
"""
import argparse
import sys
import time

import numpy as np

import pl_m11 as m
from intarith import rne_shift, sat_i8


class FakePL:
    """替身：run_conv = 黄金 im2col GEMM + 重量化(+LUT)，直写假 DDR。"""

    def __init__(self, csr_base, ddr_base, ddr_len):
        self.ddr = bytearray(ddr_len)
        self.ddr_base = 0                 # 假 DDR：物理地址 == 镜像偏移
        self.ldone = 0
        self.all_done = False

    def w32(self, off, v):
        if off == m.O_CTRL and v & 2:     # CLR_STATS
            self.ldone, self.all_done = 0, False

    def r32(self, off):
        return 0x00020000 if off == 0x04 else 0

    def status(self):
        return 0, 1, (1 if self.all_done else 0), 0, self.ldone

    def run_conv(self, tok, last, lut, timeout_s=30.0):
        t0 = time.monotonic()
        g = lambda t: int(t)
        oc, nn, k = g(tok[1]), g(tok[2]), g(tok[3])
        ih, iw, ow, ic = g(tok[4]), g(tok[5]), g(tok[6]), g(tok[7])
        kh, kw, sh, sw = (g(tok[8]), g(tok[9]), g(tok[10]), g(tok[11]))
        ph, pw, first, act = (g(tok[12]), g(tok[13]),
                              g(tok[14]) & 1, g(tok[15]) & 1)
        wbase, xbase, ybase = g(tok[17]), g(tok[18]), g(tok[24])
        bbase, mbase, sbase = g(tok[19]), g(tok[20]), g(tok[21])
        oh = (ih + 2 * ph - kh) // sh + 1
        assert nn == oh * ow, f"n={nn} != oh*ow={oh * ow}"

        x = np.frombuffer(self.ddr[xbase:xbase + ic * ih * iw],
                          dtype=np.int8).reshape(ic, ih, iw)
        # W 行距 = ceil(K/8)*8（m11_vecgen kpad）；区按 oc_tiles*8 行
        # 分配，oc 后的行是 PRNG 垫料从不读（oc=7 时 512/7=73 是除法
        # 伪影，真布局 = 8 行 × 64）。b/m/s 同样零垫到 8 条目。
        wrow = ((ic * kh * kw + 7) >> 3) << 3
        w = np.stack([np.frombuffer(
            self.ddr[wbase + wrow * r: wbase + wrow * r + ic * kh * kw],
            dtype=np.int8) for r in range(oc)])
        b = np.frombuffer(self.ddr[bbase:bbase + 4 * oc],
                          dtype="<i4").astype(np.int64)
        mu = np.frombuffer(self.ddr[mbase:mbase + 4 * oc],
                           dtype="<i4").astype(np.int64)
        s = np.frombuffer(self.ddr[sbase:sbase + oc], dtype=np.uint8)

        pad = -128 if first else 0
        xp = np.full((ic, ih + 2 * ph, iw + 2 * pw), pad, dtype=np.int8)
        xp[:, ph:ph + ih, pw:pw + iw] = x
        cols = np.empty((ic * kh * kw, oh * ow), dtype=np.int32)
        pos = 0
        for c in range(ic):
            for i in range(kh):
                for j in range(kw):
                    cols[pos] = xp[c, i:i + sh * oh:sh,
                                   j:j + sw * ow:sw].reshape(-1)
                    pos += 1
        acc = (w.reshape(oc, -1).astype(np.int32) @ cols)   # [oc, n]
        out = np.empty((oc, nn), dtype=np.int8)
        for c in range(oc):
            nq = (acc[c].astype(np.int64) + b[c]) * mu[c]
            out[c] = sat_i8(rne_shift(nq, int(s[c])))
        if act:
            out = lut[(out.astype(np.int16) + 128).astype(np.uint8)]
        self.ddr[ybase:ybase + oc * nn] = out.tobytes()
        self.ldone += 1
        if last:
            self.all_done = True
        return time.monotonic() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stim", default=m.__file__.rsplit("/", 1)[0])
    args, _ = ap.parse_known_args()
    m.PL = FakePL                                   # 关键替身
    argv = sys.argv
    sys.argv = [argv[0], "--stim", args.stim,
                "--head-out", "head_dump_selftest.bin"]
    try:
        rc = m.main()
    finally:
        sys.argv = argv
    return rc


if __name__ == "__main__":
    sys.exit(main())
