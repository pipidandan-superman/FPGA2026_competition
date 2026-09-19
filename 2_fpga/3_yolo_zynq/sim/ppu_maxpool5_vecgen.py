#!/usr/bin/env python3
"""ppu_maxpool5_vecgen.py - P2c vector generator for yolo_ppu_maxpool5.

golden_maxpool5.hex layout (one line each):
    case header : "C H W"           decimal (terminator "0 0 0")
    C*H*W lines : input byte        hex (CHW linear order)
    C*H*W lines : output byte       hex (CHW linear order)

Expected outputs come from ppu_oracle.maxpool5_padded (pad -128 model,
P1-gate proven bit-equal to the software golden).  The DUT implements
the VALID-POSITION MASK structure, so DUT==golden on these vectors IS
the pad-vs-masked dual-model cross-check demanded by manual section 7
(P2c).  The vecgen additionally asserts padded == masked per case in
python (section 2.2 equivalence pinned on every crafted tensor).

Adversarial content (anti-degenerate): all--128 tensor (pad value ==
data value -- the equivalence edge), all-+127, border--128-interior-
random, border+127-interior--128 (pad can never win), ramp, row/col
stripes, checkerboard, extreme +-rails random, seeded full-domain
random.  Shapes include the package-real (128,10,10) and synthetic
H/W < 5 (heavy masking), 1x1x1, W=9 H=2, W=1.

Usage: python ppu_maxpool5_vecgen.py <out_dir>
Marker: PPU_MAXPOOL5_VECGEN_PASS
"""
import hashlib
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(
    os.path.abspath(__file__)))          #ppu_oracle.py 平铺于 sim/
import ppu_oracle as po          # noqa: E402

SHAPES = [
    (128, 10, 10),               # package real: SPPF pool chain
    (1, 10, 10),
    (1, 5, 5),
    (1, 3, 3),                   # H=W=3 < k：重掩码
    (1, 1, 1),
    (1, 1, 7),                   # H=1
    (1, 2, 9),                   # H=2
    (2, 4, 7),
    (3, 6, 3),                   # W=3
    (1, 16, 16),
    (1, 9, 1),                   # W=1
]


def build_tensor(kind, c, h, w, rng):
    if kind == 'all_min':
        return np.full((c, h, w), -128, dtype=np.int8)
    if kind == 'all_max':
        return np.full((c, h, w), 127, dtype=np.int8)
    if kind == 'border_min':
        x = rng.integers(-128, 128, size=(c, h, w)).astype(np.int8)
        x[:, 0, :] = -128
        x[:, -1, :] = -128
        x[:, :, 0] = -128
        x[:, :, -1] = -128
        return x
    if kind == 'border_max':
        x = np.full((c, h, w), -128, dtype=np.int8)
        x[:, 1:-1, 1:-1] = rng.integers(-128, 128,
                                        size=(c, max(h-2, 0), max(w-2, 0))
                                        ).astype(np.int8)
        return x
    if kind == 'ramp':
        return (np.arange(c*h*w).reshape(c, h, w) % 256 - 128)\
            .astype(np.int8)
    if kind == 'row_stripe':
        return np.tile((np.arange(h) % 2 * 255 - 128).astype(np.int8)
                       .reshape(1, h, 1), (c, 1, w))
    if kind == 'col_stripe':
        return np.tile((np.arange(w) % 2 * 255 - 128).astype(np.int8)
                       .reshape(1, 1, w), (c, h, 1))
    if kind == 'checker':
        yy, xx = np.meshgrid(np.arange(h), np.arange(w), indexing='ij')
        return np.tile((((yy + xx) % 2) * 255 - 128).astype(np.int8)
                       .reshape(1, h, w), (c, 1, 1))
    if kind == 'rails':
        return rng.choice([-128, 127], size=(c, h, w)).astype(np.int8)
    return rng.integers(-128, 128, size=(c, h, w)).astype(np.int8)


KINDS = ['random', 'all_min', 'all_max', 'border_min', 'border_max',
         'ramp', 'row_stripe', 'col_stripe', 'checker', 'rails',
         'random2']


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(outdir, exist_ok=True)
    rng = np.random.default_rng(20260919)

    hexpath = os.path.join(outdir, 'golden_maxpool5.hex')
    cases, ok = [], True
    with open(hexpath, 'w') as f:
        for (shape, kind) in zip(SHAPES, KINDS):
            c, h, w = shape
            kr = 'random' if kind == 'random2' else kind
            x_q = build_tensor(kr, c, h, w, rng)
            pad = po.maxpool5_padded(x_q)     #golden：pad 模型
            msk = po.maxpool5_masked(x_q)     #交叉：有效位掩码模型
            equiv = np.array_equal(pad, msk)
            if not equiv:
                ok = False
                print('CASE %s %s padded!=masked FAIL' % (shape, kind))
            f.write('%d %d %d\n' % (c, h, w))
            for b in x_q.reshape(-1):
                f.write('%02x\n' % (int(b) & 0xFF))
            for b in pad.reshape(-1):
                f.write('%02x\n' % (int(b) & 0xFF))
            cases.append(dict(C=c, H=h, W=w, kind=kr, bytes=int(c*h*w),
                              pad_eq_masked=bool(equiv)))

    res = dict(verdict='PPU_MAXPOOL5_VECGEN_PASS' if ok
               else 'PPU_MAXPOOL5_VECGEN_FAIL',
               cases=cases, cases_total=len(cases),
               bytes_total=sum(m['bytes'] for m in cases),
               hex_sha256=hashlib.sha256(
                   open(hexpath, 'rb').read()).hexdigest())
    json.dump(res, open(os.path.join(outdir, 'vecgen_result.json'), 'w'),
              indent=1)
    print('%s cases=%d bytes/case-io=%d -> %s'
          % (res['verdict'], res['cases_total'],
             res['bytes_total'] * 2, hexpath))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
