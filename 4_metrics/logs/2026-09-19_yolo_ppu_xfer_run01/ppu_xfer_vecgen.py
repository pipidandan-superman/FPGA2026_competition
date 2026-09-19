#!/usr/bin/env python3
"""ppu_xfer_vecgen.py - P2e vector generator for yolo_ppu_xfer.

golden_xfer.hex layout (one line each):
    task header : "NSEG"             decimal (terminator "0")
    NSEG lines  : "len M s"          decimal (segment table, task order)
    N_tot lines : input byte         hex  (segments concatenated)
    N_tot lines : output byte        hex

Golden computes po.requant_seg(x, m, s) for EVERY segment INCLUDING
identity segments (M=2^30, s=30) -- the DUT shortcuts identity segments
to a byte copy, so DUT==golden on these vectors pins the manual-2.1
equivalence (same-scale requant is exact identity) empirically.

Anti-degenerate classes (task = segment list):
  R1  13 real concat tasks: real segment COUNT and per-input profiles
      (schedule.json in_scale/out_scale), synthetic small lengths
  R2  heads task: 6 identity segments (manual 5.2 layout family)
  M   mixed identity/non-identity at first/middle/last positions
  S1  single-segment tasks (N_seg=1) incl. identity-only
  L1  len=1 segments (boundary every byte), mixed profiles
  T   tie segments: s in {1,2,3} with odd M (every crafted byte ties),
      plus larger-s single-tie segments
  X   adversarial segments: s=0 M=2^31-1 saturation rails, dead M=0,
       M=1 s=0 full-datapath copy (contrast to identity shortcut),
       all-min/all-max fills, s=39..62 rails
  SF  s-fill single-seg tasks guaranteeing s coverage 0..62
  H   random tasks (seg count/profile/len seeded)

Generation-time quota assertions: tie bytes, sat-i8 hits, identity
segments, dead segments, len-1 segments, s coverage 0..62.

Usage: python ppu_xfer_vecgen.py <out_dir>
Marker: PPU_XFER_VECGEN_PASS
"""
import hashlib
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))) + os.sep + '3_oracle')
import ppu_oracle as po          # noqa: E402

ROM = 'E:/competition/2_fpga/3_yolo_zynq/rom_data'
M_MAX = (1 << 31) - 1
IDENT = (po.IDENT_M, po.IDENT_S)
LENS = [7, 11, 3, 19, 5, 13, 2, 23, 17, 9, 4, 31]


def odd_tie_bytes(s, rng):
    """Bytes x with x*m ≡ 2^(s-1) (mod 2^s) for ODD m (all tie)."""
    x0 = 1 << (s - 1)              # x0 odd-safe: m odd -> x = x0 + k*2^s
    sols = [x for x in range(-128, 128)
            if (x & ((1 << s) - 1)) == x0 % (1 << s)]
    return sols


def build_cases(rng):
    cases = []          # each: list of (name, len, m, s)

    def task(segs):
        cases.append(segs)

    sched = json.load(open(os.path.join(ROM, 'schedule.json')))

    # R1: real concat structure (count + profiles), synthetic lens
    for t in sched['tasks']:
        if t['op'] != 'concat':
            continue
        assert len(t['inputs']) <= 8, 'segment count > MAXSEG'
        segs = []
        for k, it in enumerate(t['inputs']):
            m, s = po.req_pair(it['scale'] / t['out_scale'])
            segs.append(('rand', LENS[k % len(LENS)], m, s))
        task(segs)

    # R2: heads-like: 6 identity segments
    task([('ident', LENS[i % len(LENS)], IDENT[0], IDENT[1])
          for i in range(6)])

    # M: mixed identity / non-identity at first/mid/last
    rm = [(m, s) for (m, s) in
          {po.req_pair(t['a_scale'] / t['out_scale'])
           for t in sched['tasks'] if t['op'] == 'add'}]
    task([('ident', 9, IDENT[0], IDENT[1]),
          ('rand', 12, rm[0][0], rm[0][1]),
          ('ident', 5, IDENT[0], IDENT[1]),
          ('rand', 8, rm[1 % len(rm)][0], rm[1 % len(rm)][1]),
          ('ident', 6, IDENT[0], IDENT[1])])
    task([('rand', 6, rm[2 % len(rm)][0], rm[2 % len(rm)][1]),
          ('ident', 15, IDENT[0], IDENT[1]),
          ('allmin', 7, M_MAX, 0)])

    # S1: single-segment
    task([('rand', 40, rm[3 % len(rm)][0], rm[3 % len(rm)][1])])
    task([('ident', 33, IDENT[0], IDENT[1])])
    task([('s0m1', 21, 1, 0)])
    task([('dead', 8, 0, 0)])

    # L1: len=1 segments, mixed profiles
    task([('rand', 1, rm[4 % len(rm)][0], rm[4 % len(rm)][1]),
          ('ident', 1, IDENT[0], IDENT[1]),
          ('tie1', 1, (1 << 30) + 1, 1),
          ('rand', 1, rm[5 % len(rm)][0], rm[5 % len(rm)][1]),
          ('s0m1', 1, 1, 0),
          ('tie2', 1, (1 << 30) | 3, 2),
          ('ident', 1, IDENT[0], IDENT[1]),
          ('sat', 1, M_MAX, 0)])

    # T: tie segments (odd M, small s -> every byte ties)
    for s in (1, 2, 3):
        task([('tie%d' % s, 24, (1 << 30) + (1 if s == 1 else 3),
               s)])
    task([('tie1mix', 20, (1 << 30) + 1, 1),
          ('ident', 4, IDENT[0], IDENT[1])])

    # X: adversarial segments
    task([('sat', 24, M_MAX, 0),
          ('sat', 20, M_MAX, 0),
          ('dead', 6, 0, 0),
          ('allmax', 10, (1 << 30) + 5, 29),
          ('allmin', 10, (1 << 30) + 5, 29)])

    # SF: s-fill 0..62（单段轨任务，s 全 63 档确定性覆盖）
    for s in range(0, 63):
        task([('rail', 3, M_MAX, s)])

    # H: random tasks
    for _ in range(12):
        n = int(rng.integers(1, 7))
        segs = []
        for k in range(n):
            kind = ['rand', 'ident', 'rand', 'sat', 'rand', 'dead',
                    'tie1', 'rail'][int(rng.integers(0, 8))]
            ln = int(rng.integers(1, 20))
            if kind == 'ident':
                segs.append((kind, ln, IDENT[0], IDENT[1]))
            elif kind == 'dead':
                segs.append((kind, ln, 0, 0))
            elif kind == 'tie1':
                segs.append((kind, ln, (1 << 30) + 1, 1))
            elif kind in ('sat', 'rail'):
                segs.append((kind, ln, M_MAX,
                             int(rng.integers(0, 63))))
            else:
                segs.append((kind, ln,
                             int(rng.integers(1 << 30, 1 << 31)),
                             int(rng.integers(0, 63))))
        task(segs)
    return cases


def seg_bytes(kind, ln, m, s, rng):
    if kind == 'ident':
        return [int(b) for b in
                rng.integers(-128, 128, size=ln)]
    if kind == 'rand':
        return [int(b) for b in
                rng.integers(-128, 128, size=ln)]
    if kind in ('tie1', 'tie2', 'tie3'):
        ss = int(kind[3])
        sols = odd_tie_bytes(ss, rng)
        return [sols[i % len(sols)] for i in range(ln)]
    if kind == 'tie1mix':
        sols = odd_tie_bytes(1, rng)
        return [sols[i % len(sols)]
                if i % 2 == 0 else int(rng.integers(-128, 128))
                for i in range(ln)]
    if kind == 'sat':
        return [(-128 if i % 2 else 127) for i in range(ln)]
    if kind == 'allmin':
        return [-128] * ln
    if kind == 'allmax':
        return [127] * ln
    if kind == 'dead':
        return [int(b) for b in
                rng.integers(-128, 128, size=ln)]
    if kind == 's0m1':
        return [int(b) for b in
                rng.integers(-128, 128, size=ln)]
    if kind == 'rail':
        return [127 if i % 3 == 0 else (-128 if i % 3 == 1 else -1)
                for i in range(ln)]
    raise ValueError(kind)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(outdir, exist_ok=True)
    rng = np.random.default_rng(20260919)
    cases = build_cases(rng)

    xs, ys, tmeta = [], [], []
    for segs in cases:
        cin, cout = [], []
        tsegs = []
        for (kind, ln, m, s) in segs:
            bs = seg_bytes(kind, ln, m, s, rng)
            cin += bs
            cout += [int(po.requant_seg(np.int8(b), m, s)) for b in bs]
            tsegs.append(dict(kind=kind, len=ln, M=m, s=s))
        xs.append(cin)
        ys.append(cout)
        tmeta.append(dict(segs=tsegs, bytes=len(cin)))

    hexpath = os.path.join(outdir, 'golden_xfer.hex')
    with open(hexpath, 'w') as f:
        for cin, cout, tm in zip(xs, ys, tmeta):
            f.write('%d\n' % len(tm['segs']))
            for td in tm['segs']:
                f.write('%d %d %d\n' % (td['len'], td['M'], td['s']))
            for b in cin:
                f.write('%02x\n' % (b & 0xFF))
            for b in cout:
                f.write('%02x\n' % (b & 0xFF))
        f.write('0\n')

    # ---- quota assertions (generation time) ----
    tie = sat = ident_seg = dead_seg = len1 = 0
    sset = set()
    for tm, cin, cout in zip(tmeta, xs, ys):
        i = 0
        for td in tm['segs']:
            for k in range(td['len']):
                x, m, s, y = cin[i], td['M'], td['s'], cout[i]
                if s > 0 and (x * m) & ((1 << s) - 1) == (1 << (s - 1)):
                    tie += 1
                if y in (-128, 127):
                    sat += 1
                i += 1
            if td['kind'] == 'ident':
                ident_seg += 1
            if td['kind'] == 'dead':
                dead_seg += 1
            if td['len'] == 1:
                len1 += 1
            sset.add(td['s'])
    assert tie > 60, tie
    assert sat > 60, sat
    assert ident_seg >= 8, ident_seg
    assert dead_seg >= 2, dead_seg
    assert len1 >= 8, len1
    assert sorted(sset) == list(range(63)), 's coverage broken'

    res = dict(verdict='PPU_XFER_VECGEN_PASS', tasks=len(tmeta),
               segments=sum(len(t['segs']) for t in tmeta),
               bytes_total=sum(t['bytes'] for t in tmeta),
               tie_bytes=tie, sat_i8_hits=sat, ident_segs=ident_seg,
               dead_segs=dead_seg, len1_segs=len1,
               s_coverage='0..62',
               hex_sha256=hashlib.sha256(
                   open(hexpath, 'rb').read()).hexdigest())
    json.dump(res, open(os.path.join(outdir, 'vecgen_result.json'), 'w'),
              indent=1)
    print('%s tasks=%d bytes=%d ties=%d sat=%d -> %s'
          % (res['verdict'], res['tasks'], res['bytes_total'],
             tie, sat, hexpath))
    return 0


if __name__ == '__main__':
    sys.exit(main())
