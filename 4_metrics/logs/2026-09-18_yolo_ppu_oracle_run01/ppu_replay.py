#!/usr/bin/env python3
"""ppu_replay.py - P1 gate: replay the FULL schedule graph with
ppu_oracle graph-op kernels (+ the G0-proven conv path, transcribed
verbatim from gemm_golden_replay.py) and bit-compare every node that has
a software-golden tensor, across ALL 5 golden frames.

REUSE CHAIN (software golden stays the sole authority):
  rom_data + golden canvas -> integer replay -> per-node bit-compare
  against golden int8_<node>.

Pass criteria (PPU_ORACLE_PASS): every frame reports ncmp == 53
(G0-consistent), graph-op compared subset == 12, bad == 0; maxpool
pad-model == masked-model on every real instance (manual section 2.2).

Also dumps per-instance requant event statistics (ties / saturation /
identity-path) over all frames: these are the coverage facts the P2
vector generators must reproduce adversarially.

Usage: python ppu_replay.py <evidence_dir>
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ppu_oracle as po

G2 = 'E:/competition/4_metrics/logs/2026-09-15_yolo7020_g2_quant_rne_run04'
ROM = 'E:/competition/2_fpga/3_yolo_zynq/rom_data'

PS_OPS = ('view', 'add', 'concat', 'maxpool5', 'upsample2')


def replay_frame(sched, quant, wblob, bblob, lblob, z):
    """One frame replay.  Returns (rows, stats, pool_equiv_ok).

    rows: (node, op, status) per schedule task with a golden tensor.
    Conv arithmetic is VERBATIM gemm_golden_replay.py (G0-proven).
    Graph-op arithmetic goes through ppu_oracle kernels only.
    """
    bufs = {0: (z['canvas_u8'].transpose(2, 0, 1).astype(np.int16) - 128)
            .astype(np.int8)}
    rows, stats, pool_equiv_ok = [], [], True

    for t in sched['tasks']:
        op, node = t['op'], t['node']

        if op == 'view':
            bufs[t['out']] = po.view_q(bufs[t['in']], *t['ch'])
        elif op == 'conv':
            qn = quant[node]
            oc, ic, kh, kw = qn['w_shape']
            sh, sw = t['stride']
            ph, pw = t['pad']
            first = t.get('first', False)
            x = bufs[t['in']]
            c, h, wd = x.shape
            padv = -128 if first else 0
            xp = np.full((c, h + 2 * ph, wd + 2 * pw), padv, dtype=np.int8)
            if ph or pw:
                xp[:, ph:ph + h, pw:pw + wd] = x
            else:
                xp = x.copy()
            ho = (h + 2 * ph - kh) // sh + 1
            wo = (wd + 2 * pw - kw) // sw + 1
            cols = np.empty((c * kh * kw, ho * wo), dtype=np.int32)
            pos = 0
            for cc in range(c):
                for i in range(kh):
                    for j in range(kw):
                        cols[pos] = xp[cc, i:i + sh * ho:sh,
                                       j:j + sw * wo:sw].reshape(-1)
                        pos += 1
            w_q = wblob[qn['w_off']:qn['w_off'] + oc * ic * kh * kw] \
                .reshape(oc, -1).astype(np.int32)
            b_q = bblob[qn['b_off'] // 4:qn['b_off'] // 4 + oc] \
                .astype(np.int64)
            if first:
                b_q = b_q + np.array(t['z_sum_w'], dtype=np.int64)
            acc = w_q @ cols
            reqs = t['req']
            out = np.empty((oc, ho * wo), dtype=np.int8)
            for cc in range(oc):
                m, s = reqs[cc]
                n = (acc[cc].astype(np.int64) + b_q[cc]) * m
                out[cc] = po.sat_i8(po.rne_shift(n, s))
            if t.get('has_act'):
                lut = lblob[qn['l_off']:qn['l_off'] + 256]
                out = lut[(out.astype(np.int16) + 128).astype(np.uint8)]
            bufs[t['out']] = out.reshape(t['out_shape'])
        elif op == 'add':
            ma, sa = po.req_pair(t['a_scale'] / t['out_scale'])
            mb, sb = po.req_pair(t['b_scale'] / t['out_scale'])
            bufs[t['out']] = po.add_q(bufs[t['a']], ma, sa,
                                      bufs[t['b']], mb, sb)
            stats.append(dict(node=node, op='add', side='a',
                              **po.requant_stats(bufs[t['a']], ma, sa)))
            stats.append(dict(node=node, op='add', side='b',
                              **po.requant_stats(bufs[t['b']], mb, sb)))
        elif op == 'concat':
            segs, seg_pairs = [], []
            for it in t['inputs']:
                m, s = po.req_pair(it['scale'] / t['out_scale'])
                segs.append((bufs[it['buf']], m, s))
                seg_pairs.append((m, s))
                stats.append(dict(node=node, op='concat',
                                  **po.requant_stats(bufs[it['buf']], m, s)))
            bufs[t['out']] = po.concat_q(segs)
        elif op == 'maxpool5':
            a = po.maxpool5_padded(bufs[t['in']])
            b = po.maxpool5_masked(bufs[t['in']])
            if not np.array_equal(a, b):
                pool_equiv_ok = False
            bufs[t['out']] = a
        elif op == 'upsample2':
            bufs[t['out']] = po.upsample2_q(bufs[t['in']])
        elif op == 'heads':
            continue        # PS float decode; PL assembly covered by P2/P3
        else:
            raise ValueError('unknown op ' + op)

        key = 'int8_' + node
        if key in z:
            g = z[key]
            mine = bufs[t['out']]
            if mine.shape != g.shape:
                rows.append((node, op, 'SHAPE %s vs %s' % (mine.shape,
                                                           g.shape)))
                continue
            d = np.count_nonzero(mine.astype(np.int16) != g.astype(np.int16))
            rows.append((node, op, 'OK' if d == 0 else 'MISMATCH %d' % d))

    return rows, stats, pool_equiv_ok


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(outdir, exist_ok=True)

    sched = json.load(open(os.path.join(ROM, 'schedule.json')))
    quant = {n['node']: n for n in json.load(
        open(os.path.join(ROM, 'quant.json')))['nodes']}
    wblob = np.fromfile(os.path.join(ROM, 'weights.bin'), dtype=np.int8)
    bblob = np.fromfile(os.path.join(ROM, 'bias.bin'), dtype=np.int32)
    lblob = np.fromfile(os.path.join(ROM, 'lut.bin'), dtype=np.int8)
    gi = json.load(open(os.path.join(G2, 'golden_index.json')))

    frames, all_stats = [], []
    pool_equiv_all = True
    for fidx, ent in enumerate(gi):
        z = np.load(os.path.join(G2, ent['file']))
        rows, stats, pool_ok = replay_frame(sched, quant, wblob, bblob,
                                            lblob, z)
        pool_equiv_all &= pool_ok
        all_stats += [dict(frame=fidx, **s) for s in stats]
        bad = [r for r in rows if r[2] != 'OK']
        ps_rows = [r for r in rows if r[1] in PS_OPS]
        fres = {'frame': ent['image'], 'fidx': fidx,
                'nodes_compared': len(rows), 'nodes_bad': len(bad),
                'ps_cmp': len(ps_rows), 'ps_bad': len(ps_rows) - sum(
                    1 for r in ps_rows if r[2] == 'OK'),
                'maxpool_equiv': pool_ok}
        frames.append(fres)
        json.dump(fres, open(os.path.join(
            outdir, 'replay_result_f%d.json' % fidx), 'w'), indent=2)
        print('frame %d: compared %d (ps %d), bad %d, pool_equiv %s'
              % (fidx, len(rows), len(ps_rows), len(bad), pool_ok))
        for r in bad:
            print('   BAD %s [%s] %s' % r)

    ok = (len(frames) == 5
          and all(f['nodes_compared'] == 53 and f['nodes_bad'] == 0
                  and f['ps_cmp'] == 12 and f['ps_bad'] == 0
                  and f['maxpool_equiv'] for f in frames))
    verdict = 'PPU_ORACLE_PASS' if ok else 'PPU_ORACLE_FAIL'
    res = {'verdict': verdict, 'frames': frames,
           'total_compared': sum(f['nodes_compared'] for f in frames),
           'total_bad': sum(f['nodes_bad'] for f in frames)}
    json.dump(res, open(os.path.join(outdir, 'replay_result.json'), 'w'),
              indent=2)
    json.dump(all_stats, open(os.path.join(
        outdir, 'requant_stats.json'), 'w'), indent=1)
    print('%s (%d frames, %d compared, %d bad)'
          % (verdict, len(frames), res['total_compared'],
             res['total_bad']))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
