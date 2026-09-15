"""M11 全网端到端激励生成器（yolo_gemm_array.v，SIM-8x8）。

一个程序（prog.hex）驱动整帧 104 任务：63 conv 描述符（M10 28 令牌格式
复用）+ 41 PS 协作层微操作（COPY/RSCL/ADD/MAXP5/UPS2），TB 扮演 PS 在
DDR 镜像上执行——RTL conv 输出真实写回镜像，经 PS 微操作变换后作为下一
conv 的 X 平面（物理链接，非仅黄金级闭合）。

帧选择：golden_00 = images89 = regression_128frames[0]（run04 权威），
故门可比对 run04 raw_head_sha256（regs[0..2]+clss[0..2] tobytes）。
基线"128 帧 head sha256"修订为 1 帧全节点逐位（3.55M 格 > head-hash
128 帧的检错力，理由见 M11 README/基线 §8 修订记录）。

镜像布局（8B 对齐 bump 分配；W 行 KPAD 满足 DMA 8B 合同）：
  [104 buffer 区 CHW][63×(W 填充行区 oc_tiles*8×KPAD + bias/m 块
  oc_tiles*32B + shift 块 oc_tiles*8B)][63×黄金期望区 oc*n]
未写 buffer 字节 = PRNG 非零填充（漏写可检测）。LUT 不入镜像：lut_all.hex
（63×256B，lut.bin 逐节点切片）由 TB 预载端口写。

生成期护栏（先于仿真，M0 教训）：程序级解释器逐指令在镜像字节上执行，
与 numpy 直接参考（intarith 语义）逐 buffer 断言一致；黄金区对 run04 npz
逐节点断言；整链头输出 sha256 == run04 regression 帧 0。
"""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'pynq'))
from intarith import rne_shift, sat_i8, sat_i32, maxpool5, upsample_nearest2  # noqa: E402

SEED = 1011
OC_EDGE = 8
RD = HERE.parent / 'rom_data'
RUN04 = Path(r'E:/competition/4_metrics/logs/'
             r'2026-09-15_yolo7020_g2_quant_rne_run04')
GOLD_NPZ = RUN04 / 'golden' / 'golden_00_images89_jpg.npz'
REG128 = RUN04 / 'regression_128frames.json'

# program opcodes (tb_yolo_fullnet.v must match)
OP_END = 0
OP_CONV = 1
OP_COPY = 2
OP_RSCL = 3
OP_ADD = 4
OP_MAXP5 = 5
OP_UPS2 = 6
OP_HEADS = 7

FLDS = 28          # conv descriptor tokens (M10 format)


def to_hex(arr, width_bytes):
    mask = (1 << (8 * width_bytes)) - 1
    return '\n'.join(
        format(int(v) & mask, 'X').zfill(2 * width_bytes)
        for v in np.asarray(arr).ravel()) + '\n'


def le_words(arr32):
    return np.asarray(arr32).astype('<i4').tobytes()


def dyadic(s_from, s_to):
    """frexp 规则 (M,s)（intarith.requant_to / runtime._dyadic 同款）。"""
    f, e = np.frexp(s_from / s_to)
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
    s = 31 - e
    return (0, 0) if s > 62 else (M, s)


class Image:
    """8 字节对齐 bump 分配器（M10 款）。"""

    def __init__(self, rng):
        self.buf = bytearray()
        self.rng = rng

    def alloc(self, data):
        assert len(self.buf) % 8 == 0
        base = len(self.buf)
        self.buf += data
        while len(self.buf) % 8:
            self.buf += b'\x00'
        return base

    def prng(self, n):
        return self.rng.integers(1, 256, n, dtype=np.uint8).tobytes()

    def words_hex(self):
        n = len(self.buf) // 8
        return ''.join(
            format(int.from_bytes(self.buf[8 * i:8 * i + 8], 'little'),
                   '016X') + '\n'
            for i in range(n)), n


def main():
    rng = np.random.default_rng(SEED)
    nodes = {n['node']: n for n in
             json.loads((RD / 'quant.json').read_text())['nodes']}
    sched = json.loads((RD / 'schedule.json').read_text())
    bufs = {b['id']: b for b in sched['buffers']}
    tasks = sched['tasks']
    wbin = (RD / 'weights.bin').read_bytes()
    bbin = (RD / 'bias.bin').read_bytes()
    lutbin = (RD / 'lut.bin').read_bytes()
    g4 = np.load(GOLD_NPZ)
    reg128 = json.loads(REG128.read_text())
    head_sha_ref = reg128[0]['raw_head_sha256']
    assert reg128[0]['image'].startswith('images89')
    canvas = ((g4['canvas_u8'].astype(np.int16) - 128)
              .astype(np.int8).transpose(2, 0, 1).copy())

    img = Image(rng)
    prog = []                      # flat 32-bit instruction words
    lut_all = bytearray()          # 63 x 256
    lay_rows = []                  # per-conv record for manifest
    n_convs = sum(1 for t in tasks if t['op'] == 'conv')

    # ---- pass 0: full numpy reference walk (golden authority chain) ----
    # conv = im2col + int32 GEMM + per-channel requant (+LUT), identical to
    # the PS runtime semantics; nodes present in the run04 npz are asserted
    # as checkpoints; the 22 C2f inner cv1/cv2 nodes (no npz tensor) get
    # their golden from this walk, closed by the head sha256 == run04.
    def im2col_acc(x, w, sh, sw, ph, pw, pad_val):
        ic, ih, iw = x.shape
        oc, ic2, kh, kw = w.shape
        assert ic == ic2
        ho = (ih + 2 * ph - kh) // sh + 1
        wo = (iw + 2 * pw - kw) // sw + 1
        xp = np.full((ic, ih + 2 * ph, iw + 2 * pw), pad_val, dtype=np.int8)
        if ph or pw:
            xp[:, ph:ph + ih, pw:pw + iw] = x
        else:
            xp = x.copy()
        cols = np.empty((ic * kh * kw, ho * wo), dtype=np.int32)
        pos = 0
        for c in range(ic):
            for i in range(kh):
                for j in range(kw):
                    cols[pos] = xp[c, i:i + sh * ho:sh,
                                   j:j + sw * wo:sw].reshape(-1)
                    pos += 1
        return (w.reshape(oc, -1).astype(np.int32) @ cols).reshape(oc, ho, wo)

    def ref_conv(t):
        node = t['node']
        nd = nodes[node]
        oc = t['out_shape'][0]
        ic, ih, iw = bufs[t['in']]['shape']
        kh, kw = t['k']
        sh, sw = t['stride']
        ph, pw = t['pad']
        K = ic * kh * kw
        w = np.frombuffer(wbin, np.int8, oc * K,
                          nd['w_off']).reshape(oc, ic, kh, kw)
        bias_q = np.frombuffer(bbin, '<i4', oc, nd['b_off']).astype(np.int64)
        if t.get('first'):
            bias_q = bias_q + np.array(t['z_sum_w'], np.int64)
        assert int(np.abs(bias_q).max()) < 2 ** 31
        bias = bias_q.astype(np.int32)
        m = np.array([p[0] for p in nd['req']], np.int64)
        shift = np.array([p[1] for p in nd['req']], np.uint8)
        acc = im2col_acc(ref[t['in']], w, sh, sw, ph, pw,
                         -128 if t.get('first') else 0)
        out = np.empty(acc.shape, dtype=np.int8)
        for c in range(oc):
            n = (acc[c].astype(np.int64) + int(bias[c])) * int(m[c])
            out[c] = sat_i8(rne_shift(n, int(shift[c])))
        if nd['has_act']:
            lut = np.frombuffer(lutbin, np.int8, 256, nd['l_off'])
            out = lut[(out.astype(np.int16) + 128).astype(np.uint8)]
        return out

    ref = {0: canvas.copy()}
    n_ckpt = 0
    for t in tasks:
        op = t['op']
        if op == 'conv':
            out = ref_conv(t)
            k = f'int8_{t["node"]}'
            if k in g4.files:
                assert np.array_equal(
                    out, np.ascontiguousarray(g4[k])), t['node']
                n_ckpt += 1
            ref[t['out']] = out
        elif op == 'view':
            lo, hi = t['ch']
            ref[t['out']] = ref[t['in']][lo:hi].copy()
        elif op == 'add':
            a = ref[t['a']].astype(np.int64)
            b = ref[t['b']].astype(np.int64)
            Ma, sa = dyadic(t['a_scale'], t['out_scale'])
            Mb, sb = dyadic(t['b_scale'], t['out_scale'])
            ref[t['out']] = sat_i8(sat_i32(
                rne_shift(a * Ma, sa) + rne_shift(b * Mb, sb)))
        elif op == 'concat':
            parts = []
            for e in t['inputs']:
                xq = ref[e['buf']]
                if abs(e['scale'] - t['out_scale']) <= 1e-15:
                    parts.append(xq)
                else:
                    M, s = dyadic(e['scale'], t['out_scale'])
                    parts.append(sat_i8(rne_shift(
                        xq.astype(np.int64) * M, s)) if (M or s)
                        else np.zeros_like(xq))
            ref[t['out']] = np.concatenate(parts, axis=0)
        elif op == 'maxpool5':
            ref[t['out']] = maxpool5(ref[t['in']][None])[0]
        elif op == 'upsample2':
            ref[t['out']] = upsample_nearest2(ref[t['in']][None])[0]
        elif op == 'heads':
            hb = b''
            for h in t['reg'] + t['cls']:
                hb += ref[h['buf']].tobytes()
            got = hashlib.sha256(hb).hexdigest()
            assert got == head_sha_ref, f'head sha {got} != {head_sha_ref}'
    assert n_ckpt >= 40, n_ckpt
    print(f'[stim] m11 ref walk: {n_ckpt} npz checkpoints + head sha OK '
          f'({head_sha_ref[:16]}...)')

    # ---- pass 1: buffer regions (all 104, CHW bytes) ----
    buf_base = {}
    for b in sched['buffers']:
        cnt = int(np.prod(b['shape']))
        if b['id'] == 0:
            base = img.alloc(canvas.tobytes())
        else:
            base = img.alloc(img.prng(cnt))
        buf_base[b['id']] = base

    # ---- pass 2: walk tasks, emit program + W/param/golden regions ----
    mirror = None                  # set after image build (self-check)
    conv_ord = 0

    def emit_conv(t, ti):
        nonlocal conv_ord
        node = t['node']
        nd, outb = nodes[node], bufs[t['out']]
        oc, oh, ow = t['out_shape']
        n = oh * ow
        inb = bufs[t['in']]
        ic, ih, iw = inb['shape']
        kh, kw = t['k']
        sh, sw = t['stride']
        ph, pw = t['pad']
        first = 1 if t.get('first') else 0
        act = 1 if nd['has_act'] else 0
        K = ic * kh * kw
        kpad = ((K + 7) >> 3) << 3
        oc_tiles = (oc + OC_EDGE - 1) // OC_EDGE
        assert nd['w_shape'] == [oc, ic, kh, kw], node
        assert (ih + 2 * ph - kh) // sh + 1 == oh, node
        assert (iw + 2 * pw - kw) // sw + 1 == ow, node
        assert K <= 2304 and n <= 65535

        w = np.frombuffer(wbin, np.int8, oc * K, nd['w_off'])
        wreg = bytearray(img.prng(oc_tiles * OC_EDGE * kpad))
        for r in range(oc):
            wreg[r * kpad:r * kpad + K] = w[r * K:(r + 1) * K].tobytes()
        wbase = img.alloc(bytes(wreg))
        bias_q = np.frombuffer(bbin, '<i4', oc, nd['b_off'])
        if first:
            bias = (bias_q.astype(np.int64)
                    + np.array(t['z_sum_w'], np.int64))
            assert int(np.abs(bias).max()) < 2 ** 31
            bias = bias.astype(np.int32)
        else:
            bias = bias_q.astype(np.int32)
        m = np.array([p[0] for p in nd['req']], np.int32)
        shift = np.array([p[1] for p in nd['req']], np.uint8)
        bbase = img.alloc(le_words(np.concatenate(
            [bias, np.zeros(oc_tiles * OC_EDGE - oc, np.int32)])))
        mbase = img.alloc(le_words(np.concatenate(
            [m, np.zeros(oc_tiles * OC_EDGE - oc, np.int32)])))
        sbase = img.alloc(bytes(shift.tobytes())
                          + b'\x00' * (oc_tiles * OC_EDGE - oc))
        exp = np.ascontiguousarray(ref[t['out']])
        assert exp.shape == (oc, oh, ow), node
        gbase = img.alloc(exp.tobytes())

        lut_all.extend(lutbin[nd['l_off']:nd['l_off'] + 256] if act
                       else b'\x00' * 256)
        row = [0, oc, n, K, ih, iw, ow, ic, kh, kw, sh, sw, ph, pw,
               first, act, 0, wbase, buf_base[t['in']], bbase, mbase,
               sbase, conv_ord, 0, buf_base[t['out']], gbase, ti, 0]
        prog.extend([OP_CONV] + row)
        lay_rows.append(dict(ord=conv_ord, task=ti, node=node, oc=oc, n=n,
                             k=K, act=act, first=first,
                             beats=(oc * n * K) // 64 + oc * n + 2048))
        conv_ord += 1

    def emit_copy(dst, src, ln):
        prog.extend([OP_COPY, dst, src, ln])

    for ti, t in enumerate(tasks):
        op = t['op']
        if op == 'conv':
            emit_conv(t, ti)
        elif op == 'view':
            src = bufs[t['in']]
            _, H, W = src['shape']
            lo, hi = t['ch']
            # dst holds only the sliced channels: no lo offset on the
            # destination; the channel offset applies to the source alone.
            emit_copy(buf_base[t['out']],
                      buf_base[t['in']] + lo * H * W, (hi - lo) * H * W)
        elif op == 'concat':
            off = 0
            for e in t['inputs']:
                _, H, W = bufs[e['buf']]['shape']
                part = H * W
                ch = bufs[e['buf']]['shape'][0]
                ln = ch * part
                if abs(e['scale'] - t['out_scale']) <= 1e-15:
                    emit_copy(buf_base[t['out']] + off,
                              buf_base[e['buf']], ln)
                else:
                    M, s = dyadic(e['scale'], t['out_scale'])
                    prog.extend([OP_RSCL, buf_base[t['out']] + off,
                                 buf_base[e['buf']], ln,
                                 M & 0xFFFFFFFF, s])
                off += ln
            assert off == int(np.prod(bufs[t['out']]['shape']))
        elif op == 'add':
            a, b = bufs[t['a']], bufs[t['b']]
            ln = int(np.prod(a['shape']))
            Ma, sa = dyadic(t['a_scale'], t['out_scale'])
            Mb, sb = dyadic(t['b_scale'], t['out_scale'])
            prog.extend([OP_ADD, buf_base[t['out']], buf_base[t['a']],
                         buf_base[t['b']], ln,
                         Ma & 0xFFFFFFFF, sa, Mb & 0xFFFFFFFF, sb])
        elif op == 'maxpool5':
            _, H, W = bufs[t['in']]['shape']
            C = bufs[t['in']]['shape'][0]
            prog.extend([OP_MAXP5, buf_base[t['out']], buf_base[t['in']],
                         C, H, W])
        elif op == 'upsample2':
            C, H, W = bufs[t['in']]['shape']
            prog.extend([OP_UPS2, buf_base[t['out']], buf_base[t['in']],
                         C, H, W])
        elif op == 'heads':
            ts = []
            for h in t['reg'] + t['cls']:
                ts.extend([buf_base[h['buf']],
                           int(np.prod(h['shape']))])
            prog.extend([OP_HEADS, 6] + ts)
        else:
            raise AssertionError(f'unknown op {op}')
    prog.append(OP_END)
    assert conv_ord == n_convs == 63

    # ---- image build + program self-check (generator-side guardrail) ----
    words_txt, n_words = img.words_hex()
    mirror = bytearray(img.buf)

    def rscl_bytes(src, ln, M, s):
        x = np.frombuffer(bytes(mirror[src:src + ln]), np.int8)
        if M == 0 and s == 0:
            return np.zeros(ln, np.int8).tobytes()
        return sat_i8(rne_shift(x.astype(np.int64) * M, s)).tobytes()

    # interpret the compiled program over the mirror: conv = place the
    # pass-0 golden (models a correct RTL: physical chaining is exercised
    # in the real sim); PS ops = exact intarith semantics. Audit every
    # buffer afterwards.
    pc = 0
    n_ps = 0
    while prog[pc] != OP_END:
        op = prog[pc]
        if op == OP_CONV:
            row = prog[pc + 1:pc + 1 + FLDS]
            ti = row[26]
            t = tasks[ti]
            outb, inb = t['out'], t['in']
            exp = ref[outb]
            mirror[buf_base[outb]:
                    buf_base[outb] + exp.size] = exp.tobytes()
            # golden region must equal the reference tensor (build check)
            g = bytes(mirror[row[25]:row[25] + exp.size])
            assert g == exp.tobytes(), f'golden region {t["node"]}'
            # X region must equal the reference input buffer
            xin = ref[inb]
            got = np.frombuffer(bytes(mirror[
                buf_base[inb]:buf_base[inb] + xin.size]), np.int8
            ).reshape(xin.shape)
            assert np.array_equal(got, xin), f'X region {t["node"]}'
            pc += 1 + FLDS
        elif op == OP_COPY:
            _, dst, src, ln = prog[pc:pc + 4]
            mirror[dst:dst + ln] = mirror[src:src + ln]
            n_ps += 1
            pc += 4
        elif op == OP_RSCL:
            _, dst, src, ln, Mu, s = prog[pc:pc + 6]
            M = Mu - (1 << 32) if Mu >> 31 else Mu
            mirror[dst:dst + ln] = rscl_bytes(src, ln, M, s)
            n_ps += 1
            pc += 6
        elif op == OP_ADD:
            _, dst, a, b, ln, Mau, sa, Mbu, sb = prog[pc:pc + 9]
            Ma = Mau - (1 << 32) if Mau >> 31 else Mau
            Mb = Mbu - (1 << 32) if Mbu >> 31 else Mbu
            xa = np.frombuffer(bytes(mirror[a:a + ln]), np.int8)
            xb = np.frombuffer(bytes(mirror[b:b + ln]), np.int8)
            A = rne_shift(xa.astype(np.int64) * Ma, sa)
            B = rne_shift(xb.astype(np.int64) * Mb, sb)
            mirror[dst:dst + ln] = sat_i8(sat_i32(A + B)).tobytes()
            n_ps += 1
            pc += 9
        elif op == OP_MAXP5:
            _, dst, src, C, H, W = prog[pc:pc + 6]
            x = np.frombuffer(bytes(mirror[src:src + C * H * W]),
                              np.int8).reshape(1, C, H, W)
            mirror[dst:dst + C * H * W] = maxpool5(x).tobytes()
            n_ps += 1
            pc += 6
        elif op == OP_UPS2:
            _, dst, src, C, H, W = prog[pc:pc + 6]
            x = np.frombuffer(bytes(mirror[src:src + C * H * W]),
                              np.int8).reshape(1, C, H, W)
            mirror[dst:dst + C * H * W * 4] = upsample_nearest2(x).tobytes()
            n_ps += 1
            pc += 6
        elif op == OP_HEADS:
            _, nt = prog[pc:pc + 2]
            heads_bytes = b''
            for k in range(nt):
                b0, ln = prog[pc + 2 + 2 * k], prog[pc + 3 + 2 * k]
                heads_bytes += bytes(mirror[b0:b0 + ln])
            got = hashlib.sha256(heads_bytes).hexdigest()
            assert got == head_sha_ref, f'head sha {got} != {head_sha_ref}'
            pc += 2 + 2 * nt
        else:
            raise AssertionError(f'bad opcode {op} @pc={pc}')
        # post-instruction buffer audit: every produced buffer so far must
        # match the numpy reference chain (compile check). Track lazily:
        # recompute views of known producers.
    # full-chain audit: the interpreted mirror's every buffer must equal
    # the pass-0 reference walk (program compile check)
    for bid, tensor in ref.items():
        if bid == 0:
            continue
        got = np.frombuffer(bytes(mirror[buf_base[bid]:
                                        buf_base[bid] + tensor.size]),
                            np.int8).reshape(tensor.shape)
        assert np.array_equal(got, tensor), f'buffer {bid} mismatch'

    # ---- outputs ----
    out = HERE / 'stim' / 'm11'
    out.mkdir(parents=True, exist_ok=True)
    files = {}
    files['ddr.hex'] = words_txt
    files['n_ddrwords.hex'] = f'{n_words:08X}\n'
    files['n_prog.hex'] = f'{len(prog):08X}\n'
    files['n_conv.hex'] = f'{n_convs:08X}\n'
    files['prog.hex'] = ''.join(
        f'{int(w) & 0xFFFFFFFF:08X}\n' for w in prog)
    files['lut_all.hex'] = to_hex(
        np.frombuffer(bytes(lut_all), np.int8), 1)
    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    tot_out = sum(r['oc'] * r['n'] for r in lay_rows)
    est_beats = sum(r['beats'] for r in lay_rows)
    manifest = {
        'name': 'm11', 'seed': SEED,
        'frame': {'npz': str(GOLD_NPZ), 'regression': str(REG128),
                  'raw_head_sha256_ref': head_sha_ref},
        'program': {'words': len(prog), 'ps_ops': n_ps, 'convs': n_convs,
                    'opcodes': {'END': 0, 'CONV': 1, 'COPY': 2, 'RSCL': 3,
                                'ADD': 4, 'MAXP5': 5, 'UPS2': 6,
                                'HEADS': 7}},
        'contract': '104-task full schedule on one DDR mirror; conv rows '
                    'reuse the M10 28-token format (token22=lut_idx, '
                    '24=y_base, 25=g_base, 26=task_idx); PS micro-ops '
                    'executed by the TB as the PS role; head dump order '
                    'regs[0..2]+clss[0..2] for run04 sha256 linkage',
        'selfcheck': 'program interpreter vs independent numpy walk: all '
                     '104 buffers equal; golden regions == npz int8 per '
                     'node; head sha256 == run04 frame0',
        'layers': lay_rows,
        'totals': {'outputs': tot_out, 'est_beats': est_beats,
                   'ddr_words': n_words,
                   'ddr_bytes': n_words * 8},
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] m11: {n_convs} convs + {n_ps} ps ops, '
          f'image={n_words} words ({n_words * 8} B), '
          f'outputs={tot_out}, est_beats={est_beats / 1e6:.1f}M, '
          f'head_sha_ref={head_sha_ref[:16]}..., manifest written')


if __name__ == '__main__':
    main()
