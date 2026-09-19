#!/usr/bin/env python3
"""ppu_upsample2_vecgen.py - P2b vector generator for yolo_ppu_upsample2.

golden_upsample2.hex layout (all hex, one line each):
    case header  : "C H W"           (terminator case "0 0 0")
    C*H*W lines  : input byte        (CHW linear order)
    4*C*H*W lines: "addr data"       (output beats in engine emission order)

Expected outputs come ONLY from ppu_oracle.upsample2_q (P1-gate proven)
plus the DIRECT address formula addr = c*4HW + (2y+dy)*2W + 2x+dx,
emitted in the DUT emission order (per input byte: dy,dx = 00,01,10,11).

Anti-overfit (manual 5.4/5.5): the case list includes BOTH package-real
shapes ((256,10,10)->20x20, (128,20,20)->40x40) and synthetic edge
shapes outside the package: W=1, H=1, C=1, odd W/H, 1x1x1.

Generation-time structural assertions:
  - per case: sorted(addr) == range(4*C*H*W) exactly (address permutation)
  - per case: every output data == its source input byte (via oracle tensor)
  - file totals + sha256 recorded in vecgen_result.json

Usage: python ppu_upsample2_vecgen.py <out_dir>
Marker: PPU_UPSAMPLE2_VECGEN_PASS
"""
import hashlib
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(
    os.path.abspath(__file__)))          #ppu_oracle.py 平铺于 sim/
import ppu_oracle as po          # noqa: E402

CASES = [
    (256, 10, 10),               # package real: model.30.upsample
    (128, 20, 20),               # package real: model.40.upsample
    (16, 10, 10),                # real-domain scaled down
    (1, 1, 1),                   # degenerate: single byte -> 4
    (1, 1, 7),                   # H=C=1, odd W
    (1, 2, 3),                   # thin C=1
    (3, 5, 4),
    (5, 3, 7),                   # odd H/W mix
    (2, 7, 1),                   # W=1 (row pair degenerates)
    (17, 4, 9),
    (1, 16, 16),
]


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(outdir, exist_ok=True)
    rng = np.random.default_rng(20260919)

    hexpath = os.path.join(outdir, 'golden_upsample2.hex')
    cases_meta = []
    ok = True
    with open(hexpath, 'w') as f:
        for (c, h, w) in CASES:
            x_q = rng.integers(-128, 128, size=(c, h, w)).astype(np.int8)
            out = po.upsample2_q(x_q)                    # oracle tensor
            c2, h2, w2 = c, 2 * h, 2 * w
            assert out.shape == (c2, h2, w2)
            f.write('%d %d %d\n' % (c, h, w))   #header 十进制（TB %d 解析）
            for b in x_q.reshape(-1):
                f.write('%02x\n' % (int(b) & 0xFF))
            # engine emission order: per input byte, dy/dx 00,01,10,11
            addrs = np.empty(4 * c * h * w, dtype=np.int64)
            datas = np.empty(4 * c * h * w, dtype=np.int8)
            k = 0
            for cc in range(c):
                for yy in range(h):
                    base_row = cc * (4 * h * w) + (2 * yy) * (2 * w)
                    for xx in range(w):
                        a0 = base_row + 2 * xx
                        for off in (0, 1, 2 * w, 2 * w + 1):
                            addrs[k] = a0 + off
                            datas[k] = x_q[cc, yy, xx]
                            k += 1
            # structural checks: exact address permutation + data source
            perm_ok = np.array_equal(np.sort(addrs),
                                     np.arange(4 * c * h * w))
            # beat carrying address a must carry the oracle byte out.flat[a]
            data_ok = np.array_equal(out.reshape(-1)[addrs], datas)
            if not perm_ok or not data_ok:
                ok = False
                print('CASE (%d,%d,%d) perm_ok=%s data_ok=%s FAIL'
                      % (c, h, w, perm_ok, data_ok))
            for a, d in zip(addrs, datas):
                f.write('%08x %02x\n' % (a, int(d) & 0xFF))
            cases_meta.append(dict(C=c, H=h, W=w, in_bytes=c * h * w,
                                   out_bytes=4 * c * h * w,
                                   perm_ok=bool(perm_ok),
                                   data_ok=bool(data_ok)))
        f.write('0 0 0\n')

    res = dict(verdict='PPU_UPSAMPLE2_VECGEN_PASS' if ok
               else 'PPU_UPSAMPLE2_VECGEN_FAIL',
               cases=cases_meta,
               cases_total=len(cases_meta),
               in_bytes_total=sum(m['in_bytes'] for m in cases_meta),
               out_bytes_total=sum(m['out_bytes'] for m in cases_meta),
               hex_sha256=hashlib.sha256(
                   open(hexpath, 'rb').read()).hexdigest())
    json.dump(res, open(os.path.join(outdir, 'vecgen_result.json'), 'w'),
              indent=1)
    print('%s cases=%d in=%d out=%d -> %s'
          % (res['verdict'], res['cases_total'], res['in_bytes_total'],
             res['out_bytes_total'], hexpath))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
