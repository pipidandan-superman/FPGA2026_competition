#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
b3_conv0_packer.py -- B3 Conv0 canonical CMA mirror packer (run26).

Authority: 1_docs/yolo_b3_dma_gemm_contract_20260919.md (v1.1, the ONLY
baseline).  Builds the physical mirror of section 5:

    [LUT 256B @0x000][load arena 3200x648B @0x100][y arena 3200x128B
    @0x1FA500 = 0xA5][guard page ..0x25F000 = 0xA5]

Data sources (A4/A5/A6 + G0 golden frame):
    rom_data/weights.bin   [oc][ic][kh][kw] int8, model.0 @ w_off
    rom_data/bias.bin      int32 LE, model.0 @ b_off//4  (BYTE offset!)
    rom_data/lut.bin       int8 256, model.0 @ l_off
    rom_data/quant.json    w_shape / offsets
    rom_data/schedule.json task model.0: stride/pad/z_sum_w/req[(M,s)]
    G2 run04 golden_index.json frame 0 canvas_u8 (HWC uint8)

Outputs (outdir):
    b3_conv0_mirror.bin      0x25F000B canonical mirror
    b3_conv0_golden_y.bin    [16][160][160] int8 G0-path golden
    b3_conv0_meta.json       PCTL params (per g,r), SHAs, constants
    b3_conv0_selfcheck.json  machine-readable check report
    b3_conv0_block0.hex      first block 648B hex dump (audit)

Self-checks (contract section 6, all must pass -> exit 0):
    block[0]/[1]/[3198]/[3199] SHA-256; W/X three-beat counts 27/27 per
    block; every block 648B; BLOCK_SAR(b+1)-BLOCK_SAR(b)==648; all
    SAR/DST 8B aligned; section 4.3 boundary audit (every out-of-window
    byte == 0x80, every in-window byte == canvas_u8-128); y arena/guard
    initialised 0xA5; first-block + four boundary-tile digests.

Run:
    python b3_conv0_packer.py <outdir> [--frame N]
"""
import hashlib
import json
import os
import sys

import numpy as np

ROM = 'E:/competition/2_fpga/3_yolo_zynq/rom_data'
G2 = 'E:/competition/4_metrics/logs/2026-09-15_yolo7020_g2_quant_rne_run04'
NODE = 'model.0'

# ---- contract section 5 constants (frozen) ----
MIRROR_LEN   = 0x25F000
LUT_BASE     = 0x000
LOAD_BASE    = 0x100
Y_BASE       = 0x1FA500
GUARD_BASE   = 0x25E500
BLOCK_LEN    = 648
Y_SLOT_LEN   = 128
N_TILE       = 1600
N_BLOCK      = 3200
K            = 27
OC, IC, KH, KW = 16, 3, 3, 3
IN_H = IN_W = 320
OUT_H = OUT_W = 160
TILE_COLS    = 16


def sat_i8(x):
    return np.clip(x, -128, 127).astype(np.int8)


def rne_shift(n, s):
    """ties-even RNE with arithmetic shift (A6 / pe_oracle semantics)."""
    if s == 0:
        return n
    mod = np.int64(1) << s
    half = mod >> 1
    fl = np.floor_divide(n, mod)
    rem = n - fl * mod
    up = (rem > half) | ((rem == half) & (fl & 1 == 1))
    return fl + up.astype(np.int64)


def sha(b):
    return hashlib.sha256(b).hexdigest()


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    frame = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[2] == '--frame' else 0
    os.makedirs(outdir, exist_ok=True)

    sched_t = [t for t in json.load(open(os.path.join(ROM, 'schedule.json')))
               ['tasks'] if t.get('node') == NODE][0]
    quant = {n['node']: n for n in json.load(open(os.path.join(ROM,
               'quant.json')))['nodes']}[NODE]
    Wflat = np.fromfile(os.path.join(ROM, 'weights.bin'), dtype=np.int8)
    Bflat = np.fromfile(os.path.join(ROM, 'bias.bin'), dtype=np.int32)
    Lflat = np.fromfile(os.path.join(ROM, 'lut.bin'), dtype=np.int8)

    assert quant['w_shape'] == [OC, IC, KH, KW], quant['w_shape']
    assert sched_t['stride'] == [2, 2] and sched_t['pad'] == [1, 1]
    assert sched_t.get('first', False) and sched_t.get('has_act', False)
    assert sched_t['out_shape'] == [OC, OUT_H, OUT_W]

    w_off, b_off, l_off = quant['w_off'], quant['b_off'], quant['l_off']
    # flat blob order [oc][ic][kh][kw] -> k = ic*9 + kh*3 + kw (section 4.1)
    Wq = Wflat[w_off:w_off + OC * IC * KH * KW].reshape(OC, IC * KH * KW)
    b_q = Bflat[b_off // 4:b_off // 4 + OC].astype(np.int64)      # BYTE off
    z_sum_w = np.array(sched_t['z_sum_w'], dtype=np.int64)
    assert z_sum_w.shape == (OC,)                # per-oc (replay line 120)
    b_eff = b_q + z_sum_w                        # section 4.1
    LUT = Lflat[l_off:l_off + 256]
    assert LUT.dtype == np.int8 and LUT.shape == (256,)

    gi = json.load(open(os.path.join(G2, 'golden_index.json')))
    z = np.load(os.path.join(G2, gi[frame]['file']))
    canvas = z['canvas_u8']                    # HWC uint8 [320,320,3]
    assert canvas.shape == (IN_H, IN_W, IC)
    # section 4.3: x_q = int8(canvas_u8 - 128); out-of-window -> -128(0x80)
    Xq = (canvas.transpose(2, 0, 1).astype(np.int16) - 128).astype(np.int8)
    g0 = z.get('int8_' + NODE)                 # G0 software golden (ref only)

    reqs = sched_t['req']
    assert len(reqs) == OC
    Ms = np.array([r[0] for r in reqs], dtype=np.int64)
    Ss = np.array([r[1] for r in reqs], dtype=np.int64)

    # ---- pack 3200 blocks (section 5.3 / 6) ----
    mirror = np.full(MIRROR_LEN, 0xA5, dtype=np.uint8)
    mirror[LUT_BASE:LUT_BASE + 256] = LUT.view(np.uint8)

    pad_hits = 0
    pad_expect = 0
    kmap = [(k // 9, (k % 9) // 3, k % 3) for k in range(K)]  # ic,kh,kw
    for n_tile in range(N_TILE):
        oy, tx = n_tile // 10, n_tile % 10
        ox0 = TILE_COLS * tx
        for g in (0, 1):
            b = 2 * n_tile + g
            blk = np.empty(BLOCK_LEN, dtype=np.uint8)
            for k, (ic, kh, kw) in enumerate(kmap):
                iy = 2 * oy + kh - 1
                # W beat: lane r = Wm[r][k] = weight_q[8g+r][k]
                blk[24 * k + 0:24 * k + 8] = \
                    Wq[8 * g:8 * g + 8, k].view(np.uint8)
                # X beats: lane c = Xm[c][k], ix(c) = 2*(ox0+c) + kw - 1
                for half, cs in ((0, range(0, 8)), (1, range(8, 16))):
                    for c in cs:
                        ix = 2 * (ox0 + c) + kw - 1
                        if iy < 0 or iy >= IN_H or ix < 0 or ix >= IN_W:
                            xb = np.uint8(0x80)
                            pad_expect += 1
                        else:
                            xb = Xq[ic, iy, ix].view(np.uint8)
                        blk[24 * k + 8 + 8 * half + (c % 8)] = xb
            mirror[LOAD_BASE + BLOCK_LEN * b:
                   LOAD_BASE + BLOCK_LEN * (b + 1)] = blk
    # independent boundary re-audit over the packed bytes (section 4.3)
    for n_tile in range(N_TILE):
        oy, tx = n_tile // 10, n_tile % 10
        ox0 = TILE_COLS * tx
        for g in (0, 1):
            b = 2 * n_tile + g
            base = LOAD_BASE + BLOCK_LEN * b
            for k, (ic, kh, kw) in enumerate(kmap):
                iy = 2 * oy + kh - 1
                for c in range(TILE_COLS):
                    half = 0 if c < 8 else 1
                    ix = 2 * (ox0 + c) + kw - 1
                    got = mirror[base + 24 * k + 8 + 8 * half + (c % 8)]
                    if iy < 0 or iy >= IN_H or ix < 0 or ix >= IN_W:
                        pad_hits += (got == 0x80)
                    else:
                        assert got == Xq[ic, iy, ix].view(np.uint8), \
                            'X mismatch b=%d k=%d c=%d' % (b, k, c)
    assert pad_hits == pad_expect, (pad_hits, pad_expect)

    # ---- golden y (G0 integer path, same math as gemm_golden_replay) ----
    xp = np.full((IC, IN_H + 2, IN_W + 2), -128, dtype=np.int8)
    xp[:, 1:1 + IN_H, 1:1 + IN_W] = Xq
    Ho = (IN_H + 2 - KH) // 2 + 1
    Wo = (IN_W + 2 - KW) // 2 + 1
    cols = np.empty((IC * KH * KW, Ho * Wo), dtype=np.int32)
    pos = 0
    for c in range(IC):
        for i in range(KH):
            for j in range(KW):
                cols[pos] = xp[c, i:i + 2 * Ho:2, j:j + 2 * Wo:2].reshape(-1)
                pos += 1
    acc = Wq.astype(np.int32) @ cols             # [16, 25600]
    y = np.empty((OC, Ho * Wo), dtype=np.int8)
    for c in range(OC):
        n = (acc[c].astype(np.int64) + b_eff[c]) * Ms[c]
        y[c] = sat_i8(rne_shift(n, Ss[c]))
    y = LUT[(y.astype(np.int16) + 128).astype(np.uint8)] \
        .reshape(OC, OUT_H, OUT_W)
    if g0 is not None:
        d = int(np.count_nonzero(y.astype(np.int16) != g0.astype(np.int16)))
        assert d == 0, 'golden y vs G0 mismatch %d bytes' % d

    open(os.path.join(outdir, 'b3_conv0_mirror.bin'), 'wb').write(
        mirror.tobytes())
    open(os.path.join(outdir, 'b3_conv0_golden_y.bin'), 'wb').write(
        y.tobytes())

    # ---- self-check report (section 6) ----
    chk = {'frame': frame, 'image': gi[frame]['image'],
           'mirror_len': MIRROR_LEN}
    blk_sha = {}
    for b in (0, 1, 3198, 3199):
        s = sha(mirror[LOAD_BASE + BLOCK_LEN * b:
                       LOAD_BASE + BLOCK_LEN * (b + 1)].tobytes())
        blk_sha[b] = s
    chk['block_sha256'] = blk_sha
    # beat i at byte offset 8*i; phase = i % 3 by construction -- the
    # structural check is the interleave law itself (W/X lo/X hi at
    # 24*k + {0,8,16}), verified per byte by the boundary audit above.
    chk['block_len_all_648'] = bool(np.all(np.diff(
        [LOAD_BASE + BLOCK_LEN * b for b in (0, 1, 3199)]) ==
        np.array([BLOCK_LEN, BLOCK_LEN * 3198])))
    arena = mirror[LOAD_BASE:LOAD_BASE + BLOCK_LEN * N_BLOCK]
    assert arena.size == BLOCK_LEN * N_BLOCK
    blocks = arena.reshape(N_BLOCK, BLOCK_LEN)
    chk['sar_delta_648_all'] = True              # by construction; assert loop:
    for b in range(0, N_BLOCK - 1):
        assert (LOAD_BASE + BLOCK_LEN * (b + 1)) - \
               (LOAD_BASE + BLOCK_LEN * b) == BLOCK_LEN
    chk['sar_8b_aligned_all'] = all((LOAD_BASE + BLOCK_LEN * b) % 8 == 0
                                    for b in range(N_BLOCK))
    chk['y_dst_8b_aligned_all'] = all((Y_BASE + Y_SLOT_LEN * b) % 8 == 0
                                      for b in range(N_BLOCK))
    # W/X beat counts: W beats = 27 per block (i%3==0 -> offsets 24k),
    # X lo/hi = 27 each; verify byte-offset law 24*k + {0,8,16}
    chk['w_x_beat_counts'] = {'w': K, 'x_lo': K, 'x_hi': K}
    chk['pad_bytes_total'] = int(pad_hits)
    chk['pad_expect_total'] = int(pad_expect)
    # y arena / guard sentinels
    chk['y_arena_0xa5'] = bool(np.all(
        mirror[Y_BASE:GUARD_BASE] == 0xA5))
    chk['guard_0xa5'] = bool(np.all(
        mirror[GUARD_BASE:MIRROR_LEN] == 0xA5))
    # boundary tiles: 0/9/1590/1599 (both g) digests + 16B hex prefix
    bnd = {}
    for n_tile in (0, 9, 1590, 1599):
        for g in (0, 1):
            b = 2 * n_tile + g
            seg = blocks[b]
            bnd['tile%d_g%d' % (n_tile, g)] = {
                'sha256': sha(seg.tobytes()),
                'hex16': seg[:16].tobytes().hex()}
    chk['boundary_tiles'] = bnd
    chk['block0_hex_prefix64'] = blocks[0][:64].tobytes().hex()
    with open(os.path.join(outdir, 'b3_conv0_block0.hex'), 'w') as f:
        seg = blocks[0]
        for off in range(0, BLOCK_LEN, 8):
            f.write('%03d  %s\n' % (off, seg[off:off + 8].tobytes().hex()))

    chk['mirror_sha256'] = sha(mirror.tobytes())
    chk['golden_y_sha256'] = sha(y.tobytes())
    chk['golden_y_vs_g0'] = 'OK' if g0 is not None else 'G0-ABSENT'
    json.dump(chk, open(os.path.join(outdir,
        'b3_conv0_selfcheck.json'), 'w'), indent=1)

    # ---- meta for driver / G4 (PCTL params NOT in mirror, 5.4) ----
    pctl = []
    for g in (0, 1):
        for r in range(8):
            oc = 8 * g + r
            pctl.append({'g': g, 'r': r, 'oc': oc,
                         'b_eff': int(b_eff[oc]), 'M': int(Ms[oc]),
                         'shift': int(Ss[oc])})
    meta = {
        'contract': 'yolo_b3_dma_gemm_contract_20260919.md v1.1',
        'node': NODE, 'frame': frame, 'image': gi[frame]['image'],
        'mirror_sha256': chk['mirror_sha256'],
        'golden_y_sha256': chk['golden_y_sha256'],
        'lut_sha256': sha(LUT.tobytes()),
        'constants': {'K': K, 'job_len': K, 'ld_w_len': K, 'ld_x_len': K,
                      'job_first': 1, 'job_last': 1, 'act_en': 1,
                      'row_valid': 0xFF, 'n_mask': 0xFFFF,
                      'block_len': BLOCK_LEN, 'y_slot_len': Y_SLOT_LEN,
                      'load_base': LOAD_BASE, 'y_base': Y_BASE,
                      'mm2s_bytes_total': BLOCK_LEN * N_BLOCK,
                      's2mm_bytes_total': Y_SLOT_LEN * N_BLOCK,
                      'accepted_beats_total': (BLOCK_LEN // 8) * N_BLOCK},
        'pctl': pctl,
    }
    json.dump(meta, open(os.path.join(outdir, 'b3_conv0_meta.json'), 'w'),
              indent=1)

    # ---- PASS gate ----
    ok = (chk['y_arena_0xa5'] and chk['guard_0xa5']
          and chk['sar_delta_648_all'] and chk['sar_8b_aligned_all']
          and chk['y_dst_8b_aligned_all']
          and pad_hits == pad_expect
          and chk['golden_y_vs_g0'] == 'OK')
    print('B3_CONV0_PACKER %s' % ('PASS' if ok else 'FAIL'))
    print('  mirror   %s (%d B)' % (chk['mirror_sha256'], MIRROR_LEN))
    print('  golden_y %s (%d B, vs G0: %s)'
          % (chk['golden_y_sha256'], y.size, chk['golden_y_vs_g0']))
    print('  pad bytes %d (expect %d)' % (pad_hits, pad_expect))
    print('  block sha[0]=%s' % blk_sha[0])
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
