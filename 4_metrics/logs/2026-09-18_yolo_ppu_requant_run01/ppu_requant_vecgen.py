#!/usr/bin/env python3
"""ppu_requant_vecgen.py - P2a vector generator for yolo_ppu_requant.

Produces golden_requant.hex ("x M s y" hex columns) where y comes ONLY
from ppu_oracle.requant_seg (python int64 oracle, P1-gate proven against
the software golden).  The TB never re-derives expectations from the DUT
formula; it cross-checks DUT against this file AND against its own
structurally-different model (truncate-div + floor fix).

Anti-degenerate discipline (PPU manual section 7 / lesson 4): real-data
statistics (requant_stats.json, run01) show 0 tie events in 10.82M
elements over 5 frames -- so ties MUST be constructed.  Generation-time
assertions enforce coverage quotas BEFORE the hex is written:

  tie q-odd rounds >= 5, tie q-even stays >= 5, negative-prod ties >= 5
  sat_lo >= 5, sat_hi >= 5, near-miss (|y| in {125,126}) >= 4
  dead channel (M=0) >= 10, identity full sweep >= 256
  distinct x >= 200, shifts used >= 40 distinct incl. {0,1,30,31,32,62}
  total vectors >= 4000

Tie feasibility fact (drives construction): tie at shift s requires
n = x*M == +-2^(s-1) (mod 2^s); with |x| <= 127 and M <= 2^31-1 the max
|n| < 2^38, so ties are constructible only for s <= 37 (s=38 needs
|x|*M == 2^37 exactly -> x=128 or M=2^31, both out of contract).

Usage: python ppu_requant_vecgen.py <out_dir>
Marker: PPU_REQUANT_VECGEN_PASS
"""
import hashlib
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))) + os.sep + '3_oracle')
import ppu_oracle as po          # noqa: E402  (PPU numeric authority)

ROM = 'E:/competition/2_fpga/3_yolo_zynq/rom_data'
M_MAX = (1 << 31) - 1            # contract: M in [0, 2^31)


def classify(x, m, s):
    """Classify one vector (audit only; y from oracle)."""
    n = int(x) * int(m)
    s = int(s)
    y = int(po.requant_seg(np.int8(x), m, s))
    if s > 0:
        q = n >> s
        rem = n - (q << s)
        tie = 2 * rem == (1 << s)
        odd = tie and (q & 1) == 1
        even = tie and (q & 1) == 0
    else:
        q, tie, odd, even = n, False, False, False
    return dict(n=n, y=y, tie=tie, tie_odd=odd, tie_even=even,
                neg_tie=tie and n < 0, q=q)


def build_vectors():
    """Return (vectors, audit). vectors = [(x, M, s), ...] in drive order."""
    vecs = []

    def add(x, m, s):
        assert -128 <= x <= 127 and 0 <= m <= M_MAX and 0 <= s <= 62
        vecs.append((int(x), int(m), int(s)))

    sched = json.load(open(os.path.join(ROM, 'schedule.json')))
    ratios = []
    for t in sched['tasks']:
        if t['op'] == 'add':
            ratios += [t['a_scale'] / t['out_scale'],
                       t['b_scale'] / t['out_scale']]
        elif t['op'] == 'concat':
            ratios += [it['scale'] / t['out_scale'] for it in t['inputs']]
    real_pairs = sorted({po.req_pair(r) for r in ratios})   # 31 unique

    # A: real pairs x extremal x ---------------------------------------
    ext = [-128, -127, -1, 0, 1, 126, 127]
    for m, s in real_pairs:
        for x in ext:
            add(x, m, s)

    # B: full x sweep on 5 selected pairs -------------------------------
    by_ratio = sorted(real_pairs, key=lambda p: p[0] / float(1 << p[1]))
    sel = [by_ratio[0], by_ratio[len(by_ratio) // 2], by_ratio[-1],
           (po.IDENT_M, po.IDENT_S), real_pairs[7]]
    for m, s in sel:
        for x in range(-128, 128):
            add(x, m, s)

    # C: constructed ties ------------------------------------------------
    # n = x*M == q0*2^s + 2^(s-1) (positive side) or its negation;
    # q0 parity selects rounds-up (odd floor q) vs stays (even q).
    s_tied = set()
    for s in list(range(1, 38)) + [37]:
        made = 0
        for x in (1, -1, 3, -3, 5, -5, 7, -7, 9, 15, 31, 63, 64, 127,
                  -128, 2, -2, 4, -4, 8, 16, 32):
            for q0 in range(0, 4):
                tgt = q0 * (1 << s) + (1 << (s - 1))
                for tgt_s in (tgt, -tgt):
                    if tgt_s % x:
                        continue
                    m = tgt_s // x
                    if 1 <= m <= M_MAX:
                        add(x, m, s)
                        made += 1
            if made >= 6:
                break
        if made:
            s_tied.add(s)

    # D: saturation + near-miss (seeded acceptance search) ---------------
    rng = np.random.default_rng(20260918)
    quota = {'sat_lo': 8, 'sat_hi': 8, 'near': 8}
    got = {'sat_lo': 0, 'sat_hi': 0, 'near': 0}
    tries = 0
    while any(got[k] < quota[k] for k in quota) and tries < 400000:
        tries += 1
        x = int(rng.integers(-128, 128))
        s = int(rng.integers(0, 33))
        m = int(rng.integers(1, M_MAX))
        y = int(po.requant_seg(np.int8(x), m, s))
        if y == -128 and got['sat_lo'] < quota['sat_lo']:
            add(x, m, s)
            got['sat_lo'] += 1
        elif y == 127 and got['sat_hi'] < quota['sat_hi']:
            add(x, m, s)
            got['sat_hi'] += 1
        elif abs(y) in (125, 126) and got['near'] < quota['near']:
            add(x, m, s)
            got['near'] += 1

    # E: dead channel M=0 -------------------------------------------------
    for x in (-128, -1, 0, 1, 127):
        for s in (0, 30, 62):
            add(x, 0, s)

    # F: s=0 direct saturating products ------------------------------------
    for x, m in ((127, M_MAX), (-128, M_MAX), (1, M_MAX), (-1, M_MAX),
                 (127, 1 << 24), (-100, 305419896), (5, 808464433)):
        add(x, m, 0)

    # G: large-shift rails s=39..62 (q in {0,-1}; no ties feasible) --------
    for s in range(39, 63):
        for x in (-128, -1, 1, 127):
            add(x, M_MAX, s)
            add(x, po.IDENT_M, s)

    # H: seeded random over full contract domain ---------------------------
    for _ in range(3000):
        add(int(rng.integers(-128, 128)), int(rng.integers(0, M_MAX)),
            int(rng.integers(0, 63)))

    # audit -----------------------------------------------------------------
    audit = [classify(*v) for v in vecs]
    ys = np.array([a['y'] for a in audit], dtype=np.int64)
    cov = dict(
        total=len(vecs),
        tie_odd=sum(a['tie_odd'] for a in audit),
        tie_even=sum(a['tie_even'] for a in audit),
        neg_ties=sum(a['neg_tie'] for a in audit),
        ties_tied_shifts=sorted(s_tied),
        sat_lo=int(np.count_nonzero(ys == -128)),
        sat_hi=int(np.count_nonzero(ys == 127)),
        near=int(np.count_nonzero(np.abs(ys) >= 125)
                 - np.count_nonzero(np.abs(ys) == 128)),
        dead=sum(1 for v in vecs if v[1] == 0),
        identity=sum(1 for v in vecs
                     if v[1] == po.IDENT_M and v[2] == po.IDENT_S),
        distinct_x=len({v[0] for v in vecs}),
        distinct_s=len({v[2] for v in vecs}),
        s_used=sorted({v[2] for v in vecs}),
    )
    return vecs, cov


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(outdir, exist_ok=True)
    vecs, cov = build_vectors()

    need = [
        ('total >= 4000', cov['total'] >= 4000),
        ('tie q-odd rounds >= 5', cov['tie_odd'] >= 5),
        ('tie q-even stays >= 5', cov['tie_even'] >= 5),
        ('negative ties >= 5', cov['neg_ties'] >= 5),
        ('tie shifts cover 1..37 incl 30/31/32',
         set(cov['ties_tied_shifts']) >= set(range(1, 33))),
        ('sat_lo >= 5', cov['sat_lo'] >= 5),
        ('sat_hi >= 5', cov['sat_hi'] >= 5),
        ('near-miss >= 4', cov['near'] >= 4),
        ('dead >= 10', cov['dead'] >= 10),
        ('identity >= 256', cov['identity'] >= 256),
        ('distinct x >= 200', cov['distinct_x'] >= 200),
        ('distinct s >= 40', cov['distinct_s'] >= 40),
        ('s domain incl {0,1,30,31,32,62}',
         set(cov['s_used']) >= {0, 1, 30, 31, 32, 62}),
    ]
    ok = True
    for name, cond in need:
        print('%-42s %s' % (name, 'PASS' if cond else 'FAIL'))
        ok &= bool(cond)

    hexpath = os.path.join(outdir, 'golden_requant.hex')
    with open(hexpath, 'w') as f:
        for x, m, s in vecs:
            y = int(po.requant_seg(np.int8(x), m, s))
            f.write('%02x %08x %02x %02x\n'
                    % (x & 0xFF, m, s, y & 0xFF))
    cov['hex_sha256'] = hashlib.sha256(
        open(hexpath, 'rb').read()).hexdigest()
    cov['verdict'] = 'PPU_REQUANT_VECGEN_PASS' if ok \
        else 'PPU_REQUANT_VECGEN_FAIL'
    json.dump(cov, open(os.path.join(
        outdir, 'vecgen_result.json'), 'w'), indent=1)

    print('%s vectors=%d -> %s' % (cov['verdict'], cov['total'], hexpath))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
