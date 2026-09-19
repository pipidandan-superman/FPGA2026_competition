#!/usr/bin/env python3
"""gemm_golden_replay.py - G0 equivalence: PE oracle arithmetic vs the
software-side quantized-inference golden.

REUSE CHAIN (user directive: the software golden stays the sole authority):
  rom_data (weights/bias/lut/quant/schedule = the exported computation graph)
  + golden frame canvas_u8
  -> replay every schedule task with pe_oracle integer arithmetic
  -> bit-compare each node tensor against golden int8_<node> from the
     G2 source run (the very tensors the hardware must reproduce).

The replay does NOT invent semantics: conv/add/concat/view/pool/upsample
arithmetic is transcribed verbatim from intref_yolov8.py (the int reference
that produced the golden), with req pairs taken from schedule.json instead
of being recomputed.

Usage: python gemm_golden_replay.py <outdir>
"""
import json, hashlib, os, sys
import numpy as np

G2 = 'E:/competition/4_metrics/logs/2026-09-15_yolo7020_g2_quant_rne_run04'
ROM = 'E:/competition/2_fpga/3_yolo_zynq/rom_data'

def rne_shift(n, s):
    """verbatim intref rne_shift (incl. s<0 shift-left branch)"""
    s = int(s)
    if s <= 0:
        if s == 0:
            return n.astype(np.int64)
        v = n.astype(np.int64) << (-s)
        assert np.abs(v).max(initial=0) < 2**63, 'shift-left overflow'
        return v
    q = n >> s
    rem = n - (q << s)
    twice = rem * 2
    full = 1 << s
    q = q + np.where(twice > full, 1, 0) + np.where(twice < -full, -1, 0)
    tie = (twice == full) | (twice == -full)
    q = q + np.where(tie & ((q & 1) == 1), np.where(twice > 0, 1, -1), 0)
    return q

def sat_i8(x):
    return np.clip(x, -128, 127).astype(np.int8)

def req_pair(r):
    """verbatim intref req_pair (normalized M in [2^30,2^31), dead-channel
    guard shift>62 -> (0,0))"""
    assert r > 0
    f, e = np.frexp(r)
    while f < 0.5:
        f *= 2
        e -= 1
    while f >= 1.0:
        f /= 2
        e += 1
    M = int(np.round(f * (1 << 31)))
    if M >= (1 << 31):
        M >>= 1
        e += 1
    shift = 31 - e
    if shift > 62:
        return 0, 0
    return M, shift

def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(outdir, exist_ok=True)
    sched = json.load(open(os.path.join(ROM, 'schedule.json')))
    quant = {n['node']: n for n in json.load(open(
        os.path.join(ROM, 'quant.json')))['nodes']}
    W = np.fromfile(os.path.join(ROM, 'weights.bin'), dtype=np.int8)
    B = np.fromfile(os.path.join(ROM, 'bias.bin'), dtype=np.int32)
    L = np.fromfile(os.path.join(ROM, 'lut.bin'), dtype=np.int8)

    gi = json.load(open(os.path.join(G2, 'golden_index.json')))
    fidx = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    z = np.load(os.path.join(G2, gi[fidx]['file']))
    frame = gi[fidx]['image']

    # buffer 0: canvas HWC uint8 -> NCHW int8 stored u-128
    bufs = {0: (z['canvas_u8'].transpose(2, 0, 1).astype(np.int16) - 128)
            .astype(np.int8)}

    rows, ncmp = [], 0
    for t in sched['tasks']:
        op, node = t['op'], t['node']
        if op == 'view':
            c0, c1 = t['ch']
            bufs[t['out']] = bufs[t['in']][c0:c1]
        elif op == 'conv':
            qn = quant[node]
            oc, ic, kh, kw = qn['w_shape']
            sh, sw = t['stride']
            ph, pw = t['pad']
            first = t.get('first', False)
            x = bufs[t['in']]
            C, H, Wd = x.shape
            padv = -128 if first else 0
            xp = np.full((C, H + 2 * ph, Wd + 2 * pw), padv, dtype=np.int8)
            if ph or pw:
                xp[:, ph:ph + H, pw:pw + Wd] = x
            else:
                xp = x.copy()
            Ho = (H + 2 * ph - kh) // sh + 1
            Wo = (Wd + 2 * pw - kw) // sw + 1
            cols = np.empty((C * kh * kw, Ho * Wo), dtype=np.int32)
            pos = 0
            for c in range(C):
                for i in range(kh):
                    for j in range(kw):
                        cols[pos] = xp[c, i:i + sh * Ho:sh,
                                         j:j + sw * Wo:sw].reshape(-1)
                        pos += 1
            w_q = W[qn['w_off']:qn['w_off'] + oc * ic * kh * kw] \
                    .reshape(oc, -1).astype(np.int32)
            # b_off is a BYTE offset into the int32 bias blob
            b_q = B[qn['b_off'] // 4:qn['b_off'] // 4 + oc].astype(np.int64)
            if first:
                b_q = b_q + np.array(t['z_sum_w'], dtype=np.int64)
            acc = w_q @ cols                                  # int32 [oc, N]
            reqs = t['req']
            out = np.empty((oc, Ho * Wo), dtype=np.int8)
            for c in range(oc):
                M, s = reqs[c]
                n = (acc[c].astype(np.int64) + b_q[c]) * M
                out[c] = sat_i8(rne_shift(n, s))
            if t.get('has_act'):
                lut = L[qn['l_off']:qn['l_off'] + 256]
                out = lut[(out.astype(np.int16) + 128).astype(np.uint8)]
            bufs[t['out']] = out.reshape(t['out_shape'])
        elif op == 'add':
            Ma, sa = req_pair(t['a_scale'] / t['out_scale'])
            Mb, sb = req_pair(t['b_scale'] / t['out_scale'])
            A = rne_shift(bufs[t['a']].astype(np.int64) * Ma, sa)
            Bv = rne_shift(bufs[t['b']].astype(np.int64) * Mb, sb)
            bufs[t['out']] = sat_i8(np.clip(A + Bv, -2**31, 2**31 - 1))
        elif op == 'concat':
            parts = []
            for it in t['inputs']:
                M, s = req_pair(it['scale'] / t['out_scale'])
                parts.append(sat_i8(rne_shift(
                    bufs[it['buf']].astype(np.int64) * M, s)))
            bufs[t['out']] = np.concatenate(parts, axis=0)
        elif op == 'maxpool5':
            x = bufs[t['in']]
            C, H, Wd = x.shape
            p = 2
            xp = np.full((C, H + 4, Wd + 4), -128, dtype=np.int8)
            xp[:, p:p + H, p:p + Wd] = x
            o = np.full((C, H, Wd), -128, dtype=np.int8)
            for i in range(5):
                for j in range(5):
                    np.maximum(o, xp[:, i:i + H, j:j + Wd], out=o)
            bufs[t['out']] = o
        elif op == 'upsample2':
            bufs[t['out']] = bufs[t['in']].repeat(2, axis=1).repeat(2, axis=2)
        elif op == 'heads':
            continue        # PS-side float decode, not PE/GEMM scope
        else:
            raise ValueError('unknown op ' + op)
        # ---- bit-compare against the software golden where it exists ----
        key = 'int8_' + node
        if key in z:
            g = z[key]
            mine = bufs[t['out']]
            if mine.shape != g.shape:
                rows.append((node, 'SHAPE %s vs %s' % (mine.shape, g.shape)))
                continue
            d = np.count_nonzero(mine.astype(np.int16) != g.astype(np.int16))
            ncmp += 1
            rows.append((node, 'OK' if d == 0 else 'MISMATCH %d' % d))

    bad = [r for r in rows if r[1] != 'OK']
    for node, st in rows:
        print('%-22s %s' % (node, st))
    res = {'frame': frame, 'nodes_compared': ncmp, 'nodes_bad': len(bad),
           'verdict': 'G0_REPLAY_PASS' if not bad and ncmp >= 50
                      else 'G0_REPLAY_FAIL'}
    json.dump(res, open(os.path.join(outdir, 'replay_result_f%d.json' % fidx),
              'w'), indent=2)
    print('compared %d nodes, bad %d -> %s' % (ncmp, len(bad), res['verdict']))
    return 0 if res['verdict'] == 'G0_REPLAY_PASS' else 1

if __name__ == '__main__':
    sys.exit(main())
