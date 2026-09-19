#!/usr/bin/env python3
"""ppu_add_vecgen.py - P2d vector generator for yolo_ppu_add.

golden_add.hex layout (one line each):
    task header : "N Ma sa Mb sb"    decimal (terminator "0 0 0 0 0")
    N lines     : "a b"              hex (lane bytes, same linear order)
    N lines     : "y"                hex (expected output byte)

Expected outputs come ONLY from ppu_oracle.add_q (P1-gate proven vs the
software golden): A=rne_shift(a*Ma,sa), B=rne_shift(b*Mb,sb) int64,
y=sat_i8(sat_i32(A+B)).  The DUT implements the same contract with
shift+mask RNE structure; the TB model re-derives expectations with a
structurally different truncate-division construction.

Anti-degenerate discipline (manual section 7 / lesson 4): real-data
statistics show 0 RNE tie events in 10.82M elements, so ties, i8
saturation rails, int32 contract-clip hits, dead channels and identity
lanes MUST be constructed.  Generation-time quota assertions below.

Classes:
  A  6 real add-task profile PAIRS (schedule.json a/b vs out) x
     extremal cross (a,b in {-128,-127,-1,0,1,126,127})
  B  full-x sweeps, b=-a (cancellation) and b=a (doubling), on
     ident x ident / ident x real-min-ratio / real-max x ident
  C  constructed RNE ties per lane (other lane = tame identity),
     s = 1..37 coverage, q odd (round up) and q even (stay),
     negative products; plus both-lane tie pairs
  D  constructed int32 contract-clip hits (s=0, M=2^31-1 lanes:
     |A+B| up to ~2^39 >> 2^31; single-side and both-side, +- signs)
  E  dead channels M=0 (a-dead / b-dead / both-dead)
  F  s=0 direct lanes incl. M=1 raw passthrough (y=sat(a+b))
  G  s=39..62 rails (M=2^31-1; ties impossible there -- s<=37 fact --
     but near-zero outputs must still be exact)
  H  seeded full-domain random (M mostly [2^30,2^31), s 0..62)

Usage: python ppu_add_vecgen.py <out_dir>
Marker: PPU_ADD_VECGEN_PASS
"""
import hashlib
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(
    os.path.abspath(__file__)))          #ppu_oracle.py 平铺于 sim/
import ppu_oracle as po          # noqa: E402

ROM = 'E:/competition/2_fpga/3_yolo_zynq/rom_data'
M_MAX = (1 << 31) - 1
EXT = [-128, -127, -1, 0, 1, 126, 127]


def real_task_pairs():
    """The 6 real add-task (Ma,sa,Mb,sb) quads from schedule.json."""
    sched = json.load(open(os.path.join(ROM, 'schedule.json')))
    quads = []
    for t in sched['tasks']:
        if t['op'] == 'add':
            ma, sa = po.req_pair(t['a_scale'] / t['out_scale'])
            mb, sb = po.req_pair(t['b_scale'] / t['out_scale'])
            quads.append((ma, sa, mb, sb))
    return quads


def tie_xm(s):
    """Construct (x, M) with n=x*M = ±(q0*2^s + 2^(s-1)) (a tie),
    mixing q0 parities and product signs; M in [1, 2^31) (engine
    contract domain -- req_pair normalisation is NOT assumed here,
    same construction domain as the P2a requant vecgen)."""
    out = []
    for x in (1, -1, 3, -3, 5, -5, 7, -7, 9, 15, 31, 63, 64, 127, -128,
              2, -2, 4, -4, 8, 16, 32):
        for q0 in range(0, 4):
            tgt = q0 * (1 << s) + (1 << (s - 1))
            for tgt_s in (tgt, -tgt):
                if tgt_s % x:
                    continue
                m = tgt_s // x
                if 1 <= m <= M_MAX:
                    out.append((x, m))
        if len(out) >= 6:
            break
    return out


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(outdir, exist_ok=True)
    rng = np.random.default_rng(20260919)

    vecs = []          # (a, b, ma, sa, mb, sb)

    def push(a, b, ma, sa, mb, sb):
        assert -128 <= a <= 127 and -128 <= b <= 127
        for m in (ma, mb):
            assert 0 <= m <= M_MAX
        for s in (sa, sb):
            assert 0 <= s <= 62
        vecs.append((int(a), int(b), int(ma), int(sa), int(mb), int(sb)))

    ident = (po.IDENT_M, po.IDENT_S)

    # A: real task pairs x extremal cross
    quads = real_task_pairs()
    for (ma, sa, mb, sb) in quads:
        for a in EXT:
            for b in EXT:
                push(a, b, ma, sa, mb, sb)

    # B: full-x sweeps (cancellation / doubling)
    pairs_b = [(ident, ident), (ident, (M_MAX, 0)), ((M_MAX, 0), ident)]
    for (pa, pb) in pairs_b:
        for x in range(-127, 128):                    #b=-a（−128 无 Neg）
            push(x, -x, pa[0], pa[1], pb[0], pb[1])
        for x in range(-128, 128):
            push(x, x, pa[0], pa[1], pb[0], pb[1])    #b=a

    # C: constructed ties per lane + both-lane
    for s in range(1, 38):
        for (x, m) in tie_xm(s)[:4]:
            push(x, 0, m, s, ident[0], ident[1])       # lane-A tie
            push(0, x, ident[0], ident[1], m, s)       # lane-B tie
    s_mid = 20
    for (xa, ma) in tie_xm(s_mid)[:2]:
        for (xb, mb) in tie_xm(s_mid)[:2]:
            push(xa, xb, ma, s_mid, mb, s_mid)         # both-lane ties

    # D: int32 contract-clip constructions (s=0 lanes, big M)
    big = (M_MAX, 0)
    for a in (127, -128, 126, -127, 100, -100):
        for b in (127, -128, 1, -1, 0, 50):
            push(a, b, big[0], big[1], big[0], big[1])
    push(127, 127, M_MAX, 0, 1, 0)                     # single-side huge
    push(-128, -128, 1, 0, M_MAX, 0)

    # E: dead channels
    for (a, b) in ((64, -64), (-3, 120), (0, 0), (127, -128), (51, 51)):
        push(a, b, 0, 0, ident[0], ident[1])           # a dead
        push(a, b, ident[0], ident[1], 0, 0)           # b dead
        push(a, b, 0, 0, 0, 0)                         # both dead

    # F: s=0 direct lanes incl. raw passthrough M=1
    for (a, b) in ((100, 27), (-100, -27), (127, 1), (-128, -1)):
        push(a, b, 1, 0, 1, 0)
        push(a, b, 1, 0, ident[0], ident[1])

    # G: s=39..62 rails
    for s in range(39, 63):
        for (a, b) in ((127, -128), (-1, 1), (123, 45)):
            push(a, b, M_MAX, s, M_MAX, s)

    # G2: s 填充 1..38（不依赖平局构造成败，保证全档覆盖）
    for s in range(1, 39):
        push(127, -128, M_MAX, s, 1 << 30, s)

    # H: seeded random full-domain, 8 fixed quads (task-level profiles)
    hquads = []
    for _ in range(8):
        ma = (int(rng.integers(0, M_MAX + 1))
              if rng.integers(0, 8) == 0
              else int(rng.integers(1 << 30, 1 << 31)))
        hquads.append((ma, int(rng.integers(0, 63)),
                       int(rng.integers(1 << 30, 1 << 31)),
                       int(rng.integers(0, 63))))
    for (ma, sa, mb, sb) in hquads:
        for _ in range(500):
            push(int(rng.integers(-128, 128)), int(rng.integers(-128, 128)),
                 ma, sa, mb, sb)

    # ---- golden + coverage audit ----
    hexpath = os.path.join(outdir, 'golden_add.hex')
    av = np.array([v[0] for v in vecs], dtype=np.int8)
    bv = np.array([v[1] for v in vecs], dtype=np.int8)
    mav = [v[2] for v in vecs]
    sav = [v[3] for v in vecs]
    mbv = [v[4] for v in vecs]
    sbv = [v[5] for v in vecs]
    yv = np.empty(len(vecs), dtype=np.int8)
    for i, (a, b, ma, sa, mb, sb) in enumerate(vecs):
        yv[i] = po.add_q(np.int8(a), ma, sa, np.int8(b), mb, sb)

    # 按 profile 分组为多任务（每任务独立 (Ma,sa,Mb,sb) 头——引擎
    # profile 是任务级的，单头混装多 profile 向量会假错）
    groups = {}
    order = []
    for i, (a, b, ma, sa, mb, sb) in enumerate(vecs):
        key = (ma, sa, mb, sb)
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(i)
    with open(hexpath, 'w') as f:
        for key in order:
            idxs = groups[key]
            f.write('%d %d %d %d %d\n'
                    % (len(idxs), key[0], key[1], key[2], key[3]))
            for i in idxs:
                f.write('%02x %02x\n'
                        % (vecs[i][0] & 0xFF, vecs[i][1] & 0xFF))
            for i in idxs:
                f.write('%02x\n' % (int(yv[i]) & 0xFF))
        f.write('0 0 0 0 0\n')

    # ---- quota assertions (generation time, lesson 4) ----
    ties = {'a': 0, 'b': 0}
    sat8 = 0
    clip32 = 0
    for i, (a, b, ma, sa, mb, sb) in enumerate(vecs):
        for lane, x, m, s in (('a', a, ma, sa), ('b', b, mb, sb)):
            n = x * m
            if s > 0 and (n & ((1 << s) - 1)) == (1 << (s - 1)):
                ties[lane] += 1
        A = po.rne_shift(av[i].astype(np.int64) * mav[i], sav[i])
        B = po.rne_shift(bv[i].astype(np.int64) * mbv[i], sbv[i])
        if A + B > (1 << 31) - 1 or A + B < -(1 << 31):
            clip32 += 1
        if yv[i] in (-128, 127):
            sat8 += 1
    s_cov = sorted(set(sav) | set(sbv))
    n_ident = sum(1 for i in range(len(vecs))
                  if (mav[i], sav[i]) == ident or (mbv[i], sbv[i]) == ident)
    n_dead = sum(1 for i in range(len(vecs))
                 if mav[i] == 0 or mbv[i] == 0)

    assert ties['a'] > 60 and ties['b'] > 60, ties
    assert sat8 > 500, sat8
    assert clip32 > 30, clip32
    assert n_ident > 300, n_ident
    assert n_dead >= 15, n_dead
    assert s_cov == list(range(63)), 's coverage broken'

    res = dict(verdict='PPU_ADD_VECGEN_PASS', vectors=len(vecs),
               tasks=len(order),
               ties_a=ties['a'], ties_b=ties['b'], sat_i8_hits=sat8,
               i32_clip_hits=clip32, identity_lane=n_ident,
               dead_channel=n_dead, s_coverage='%d..%d'
               % (s_cov[0], s_cov[-1]),
               hex_sha256=hashlib.sha256(
                   open(hexpath, 'rb').read()).hexdigest())
    json.dump(res, open(os.path.join(outdir, 'vecgen_result.json'), 'w'),
              indent=1)
    print('%s vectors=%d ties_a=%d ties_b=%d sat8=%d clip32=%d -> %s'
          % (res['verdict'], res['vectors'], ties['a'], ties['b'],
             sat8, clip32, hexpath))
    return 0


if __name__ == '__main__':
    sys.exit(main())
