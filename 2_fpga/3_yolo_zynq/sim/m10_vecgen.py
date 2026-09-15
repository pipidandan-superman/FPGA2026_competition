"""M10 阵列集成激励生成器（yolo_gemm_array.v 门）。

单一 DDR 字节镜像（ddr.hex，64b LE 字）+ 层描述表（layers.hex）+ 真实层
期望（yexp1/2.hex）+ 合成层 M0 黄金服务区（gw/gb/gm/gs{L}.hex）。

层计划（S=合成、R=真实；顺序即运行顺序）：
  L0 S1 ic3 /k3/s1/p1/ih7  -> n49  oc7   K27   act1 first0 —— oc 尾 7、ic3
  L1 R1 model.0            -> n25600 oc16 K27   act1 first1 —— 真实回归 1
  L2 S2 ic64/k3/s2/p1/ih10 -> n25  oc16  K576  act1 first0 —— 双维多 tile
  L3 S3 ic16/k2/s1/p0/ih17 -> n256 oc9   K64   act0 first0 —— act 旁路、k2
  L4 R2 model.16           -> n400 oc64  K576  act1 first0 —— 真实回归 2
  L5 S4 ic256/k3/s1/p1/ih5 -> n25  oc8   K2304 act1 first1 last1 —— 最深 K
      + first=1 合成 pad=-128 + last 层 all_done。

真实层数据权威链（2026-09-15 冻结）：rom_data = G2 run04 部署源导出；
run04 npz 黄金。python 重组链已对 run04 双层逐位复现（R1 0/409600、
R2 0/25600）——本生成器写出的期望即该链路的产物。

图像布局（全部 8 字节对齐分配器；W 行按 KPAD=ceil(K/8)*8 填充行距，
满足 M9 DMA cmd_addr 8 对齐合同）：
  [W 填充行区 oc_tiles*8 x KPAD][bias 块 oc_tiles*32][m 块 oc_tiles*32]
  [shift 块 oc_tiles*8] [M0 镜像 W oc*K 连续][gb/gm/gs oc 项] [X 平面
  ic*ih*iw CHW][LUT 256B（lut.bin 真实表切片）]
"""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'pynq'))
from intarith import rne_shift, sat_i8  # noqa: E402

SEED = 1010
OC_EDGE = 8
N_EDGE = 8
K_MAX = 2304
RD = HERE.parent / 'rom_data'
GOLD_NPZ = (r'E:/competition/4_metrics/logs/'
            r'2026-09-15_yolo7020_g2_quant_rne_run04/golden/'
            r'golden_00_images89_jpg.npz')

# ---- synstim v2 反退化配方（照搬，见 synstim_gen.py 归档教训） ----
TIE_DELTAS = [1, -1, 3, 5]
TIE_SHIFT = 31


def to_hex(arr, width_bytes):
    mask = (1 << (8 * width_bytes)) - 1
    return '\n'.join(
        format(int(v) & mask, 'X').zfill(2 * width_bytes)
        for v in np.asarray(arr).ravel()) + '\n'


def im2col_acc(x, w, sh, sw, ph, pw, pad_val):
    """acc int32 [oc,ho,wo]（im2col k 序 = c*(kh*kw)+i*kw+j，与 RTL/M0 一致）。"""
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


def channel_plan(oc):
    if oc == 2:
        return ['tie0', 'real']
    if oc == 3:
        return ['tie0', 'tie1', 'real']
    plan = (['tie0', 'tie1', 'real', 'tie2', 'tie3'] + ['real'] * oc)[:oc]
    if oc >= 6:
        plan[oc - 1] = 'sat'
    return plan


def gen_req_params(rng, oc, acc, ho, wo):
    """bias_eff/m/shift：平局 + 饱和 + 现实域通道（synstim v2 原配方）。"""
    plan = channel_plan(oc)
    bias = np.zeros(oc, dtype=np.int64)
    m = np.zeros(oc, dtype=np.int64)
    shift = np.zeros(oc, dtype=np.int64)
    acc_abs_typ = max(1, int(np.abs(acc).mean()))
    first_real = plan.index('real')
    for c, role in enumerate(plan):
        if role.startswith('tie'):
            idx = int(role[3:])
            py, px = (idx * 7) % ho, (idx * 11) % wo
            shift[c] = TIE_SHIFT
            m[c] = 1 << 30
            bias[c] = TIE_DELTAS[idx] - int(acc[c, py, px])
            n_t = (int(acc[c, py, px]) + int(bias[c])) * int(m[c])
            assert (n_t & ((1 << TIE_SHIFT) - 1)) == (1 << (TIE_SHIFT - 1)), \
                f'tie construction broken ch{c}: n={n_t}'
        elif role == 'sat':
            shift[c] = 36
            m[c] = (1 << 31) - 1 if c % 2 == 0 else -((1 << 31) - 1)
            bias[c] = int(rng.integers(1, 2**20 + 1)) \
                * (1 - 2 * int(rng.integers(0, 2)))
        else:
            if c == first_real:
                target = int(rng.integers(80, 121))
            else:
                target = int(rng.integers(4, 121))
            bias[c] = int(rng.integers(-acc_abs_typ, acc_abs_typ + 1))
            m_mag = int(rng.integers(1 << 28, 1 << 31))
            m[c] = m_mag if rng.integers(0, 2) else -m_mag
            denom = acc_abs_typ + abs(int(bias[c]))
            s_ideal = int(round(np.log2(denom * m_mag / target)))
            shift[c] = min(62, max(4, s_ideal))
    assert int(np.abs(bias).max()) < 2**31
    assert int(np.abs(m).max()) < 2**31
    assert shift.max() <= 62
    return (bias.astype(np.int32), m.astype(np.int32),
            shift.astype(np.uint8), plan)


def requant_full(acc, bias, m, shift, lut, has_act):
    """返回 (y, y_pre)：y_pre 为 LUT 前饱和 int8（反退化检查对象——
    LUT 负半轴近平坦，检查应落在 requant 输出上，LUT 保真属 M4 门）。"""
    oc = acc.shape[0]
    y_pre = np.empty(acc.shape, dtype=np.int8)
    for c in range(oc):
        n = (acc[c].astype(np.int64) + np.int64(bias[c])) * np.int64(m[c])
        y_pre[c] = sat_i8(rne_shift(n, int(shift[c])))
    if has_act:
        y = lut[(y_pre.astype(np.int16) + 128).astype(np.uint8)]
    else:
        y = y_pre
    return y, y_pre


class Image:
    """8 字节对齐 bump 分配器。"""

    def __init__(self):
        self.buf = bytearray()

    def alloc(self, data):
        assert len(self.buf) % 8 == 0
        base = len(self.buf)
        assert base % 8 == 0
        self.buf += data
        while len(self.buf) % 8:
            self.buf += b'\x00'
        return base

    def words_hex(self):
        n = len(self.buf) // 8
        return ''.join(
            format(int.from_bytes(self.buf[8 * i:8 * i + 8], 'little'),
                   '016X') + '\n'
            for i in range(n)), n


def le_words(arr32):
    return np.asarray(arr32).astype('<i4').tobytes()


def synth_rng_x(rng, size):
    """随机 int8 + 定量极值注入（±127 边界覆盖）。"""
    x = rng.integers(-128, 128, size).astype(np.int8)
    flat = x.reshape(-1)
    n_ext = max(8, size // 16)
    idx = rng.choice(size, size=n_ext, replace=False)
    flat[idx] = np.where(rng.integers(0, 2, n_ext) == 0, -128, 127)
    return x


def main():
    rng = np.random.default_rng(SEED)
    nodes = {n['node']: n for n in
             json.loads((RD / 'quant.json').read_text())['nodes']}
    tasks = {t['node']: t for t in
             json.loads((RD / 'schedule.json').read_text())['tasks']}
    wbin = (RD / 'weights.bin').read_bytes()
    bbin = (RD / 'bias.bin').read_bytes()
    lutbin = np.frombuffer((RD / 'lut.bin').read_bytes(), np.int8)
    g4 = np.load(GOLD_NPZ)

    img = Image()
    layers = []
    files = {}
    cov = {'layers': [], 'tie_ch': 0, 'sat_ch': 0, 'real_ch': 0,
           'shifts': set(), 'k_tiers': set(), 'n_tiers': set(),
           'act_modes': set(), 'first_modes': set()}
    gaps = [4, 0, 3, 0, 6, 2]
    assert any(g == 0 for g in gaps) and any(g > 0 for g in gaps)

    def add_layer(tag, geom, *, real=None):
        """geom: ic,kh,kw,sh,sw,ph,pw,ih,iw,oc,act,first,lut_off。
        real: ('model.0'|'model.16', xbytes, expected flat int8|None)。"""
        ic, kh, kw = geom['ic'], geom['kh'], geom['kw']
        sh, sw, ph, pw = geom['sh'], geom['sw'], geom['ph'], geom['pw']
        ih, iw, oc, act, first = (geom['ih'], geom['iw'], geom['oc'],
                                  geom['act'], geom['first'])
        K = ic * kh * kw
        kpad = ((K + 7) >> 3) << 3
        oh = (ih + 2 * ph - kh) // sh + 1
        ow = (iw + 2 * pw - kw) // sw + 1
        n = oh * ow
        oc_tiles = (oc + OC_EDGE - 1) // OC_EDGE
        last = 1 if tag == 'S4' else 0
        L = len(layers)
        assert K <= K_MAX and n <= 65535

        # ---- 数据源 ----
        if real is None:
            w = rng.integers(-128, 128, (oc, ic, kh, kw)).astype(np.int8)
            x = synth_rng_x(rng, ic * ih * iw).reshape(ic, ih, iw)
            acc = im2col_acc(x, w, sh, sw, ph, pw, -128 if first else 0)
            bias, m, shift, plan = gen_req_params(rng, oc, acc, oh, ow)
            y, y_pre = requant_full(
                acc, bias, m, shift,
                lutbin[geom['lut_off']:geom['lut_off'] + 256], act)
            # 反退化覆盖断言：tie/sat 存在、现实通道 y 非退化
            cov['tie_ch'] += sum(r.startswith('tie') for r in plan)
            cov['sat_ch'] += sum(r == 'sat' for r in plan)
            cov['shifts'].update(int(shift[c]) for c, r in enumerate(plan)
                                 if r != 'real')
            cov['real_ch'] += sum(r == 'real' for r in plan)
            for c, r in enumerate(plan):
                if r == 'real':
                    assert len(np.unique(y_pre[c])) >= 8, (tag, c)
                    cov['shifts'].add(int(shift[c]))
            assert any(r.startswith('tie') for r in plan)
            w_bytes = w.tobytes()
            x_bytes = x.tobytes()
            expsel = 0
            expected = None
        else:
            node = real[0]
            nd, tk = nodes[node], tasks[node]
            assert nd['w_shape'] == [oc, ic, kh, kw]
            w = np.frombuffer(wbin, np.int8, oc * K, nd['w_off'])
            w_bytes = w.tobytes()
            bias_q = np.frombuffer(bbin, '<i4', oc, nd['b_off'])
            if tk['first']:
                zsw = np.array(tk['z_sum_w'], np.int64)
                bias = (bias_q.astype(np.int64) + zsw)
                assert int(np.abs(bias).max()) < 2**31
                bias = bias.astype(np.int32)
            else:
                bias = bias_q.astype(np.int32)
            m = np.array([p[0] for p in nd['req']], np.int32)
            shift = np.array([p[1] for p in nd['req']], np.uint8)
            x_bytes = real[1]
            expected = real[2]
            expsel = 1 if node == 'model.0' else 2
            assert len(x_bytes) == ic * ih * iw
            assert expected.size == oc * n

        # ---- DDR 区块 ----
        wreg = bytearray(rng.integers(
            0, 256, oc_tiles * OC_EDGE * kpad, dtype=np.uint8).tobytes())
        for r in range(oc):
            wreg[r * kpad:r * kpad + K] = w_bytes[r * K:(r + 1) * K]
        wbase = img.alloc(bytes(wreg))
        bbase = img.alloc(le_words(
            np.concatenate([bias, np.zeros(oc_tiles * OC_EDGE - oc,
                                           np.int32)])))
        mbase = img.alloc(le_words(
            np.concatenate([m, np.zeros(oc_tiles * OC_EDGE - oc, np.int32)])))
        sbase = img.alloc(bytes(shift.tobytes()) +
                          b'\x00' * (oc_tiles * OC_EDGE - oc))
        if real is None:                       # M0 黄金服务区（连续 W + 参数）
            gwbase = img.alloc(w_bytes)
            gbbase = img.alloc(le_words(bias))
            gmbase = img.alloc(le_words(m))
            gsbase = img.alloc(shift.tobytes())
        else:
            gwbase = gbbase = gmbase = gsbase = 0
        xbase = img.alloc(x_bytes)
        lutbase = img.alloc(lutbin[geom['lut_off']:geom['lut_off'] + 256]
                            .tobytes())

        row = [gaps[L], oc, n, K, ih, iw, ow, ic, kh, kw, sh, sw, ph, pw,
               first, act, last, wbase, xbase, bbase, mbase, sbase, lutbase,
               expsel, gwbase, gbbase, gmbase, gsbase]
        layers.append(row)
        cov['layers'].append(dict(
            idx=L, tag=tag, oc=oc, n=n, k=K, kpad=kpad, oh=oh, ow=ow,
            ic=ic, ih=ih, iw=iw, act=act, first=first, last=last,
            expsel=expsel, wbase=wbase, xbase=xbase, gap=gaps[L]))
        cov['k_tiers'].add(K)
        cov['n_tiers'].add(n)
        cov['act_modes'].add(act)
        cov['first_modes'].add(first)

        # ---- 期望文件（真实层） / M0 服务区（合成层） ----
        if real is not None:
            files[f'yexp{expsel}.hex'] = to_hex(expected, 1)
        else:
            files[f'gw{L}.hex'] = to_hex(
                np.frombuffer(w_bytes, np.int8), 1)
            files[f'gb{L}.hex'] = to_hex(bias, 4)
            files[f'gm{L}.hex'] = to_hex(m, 4)
            files[f'gs{L}.hex'] = to_hex(shift, 1)

    # L0 S1 —— oc 尾 7 / ic3 / p1 / act
    add_layer('S1', dict(ic=3, kh=3, kw=3, sh=1, sw=1, ph=1, pw=1,
                         ih=7, iw=7, oc=7, act=1, first=0, lut_off=0))
    # L1 R1 —— model.0（部署源黄金 npz：输入 canvas、期望 int8_model.0）
    x_r1 = ((g4['canvas_u8'].astype(np.int16) - 128) & 0xFF) \
        .astype(np.uint8).transpose(2, 0, 1).tobytes()
    add_layer('R1', dict(ic=3, kh=3, kw=3, sh=2, sw=2, ph=1, pw=1,
                         ih=320, iw=320, oc=16, act=1, first=1, lut_off=0),
              real=('model.0', x_r1, g4['int8_model.0'].ravel()))
    # L2 S2 —— 双维多 tile / s2 / K576
    add_layer('S2', dict(ic=64, kh=3, kw=3, sh=2, sw=2, ph=1, pw=1,
                         ih=10, iw=10, oc=16, act=1, first=0, lut_off=2560))
    # L3 S3 —— act 旁路 / k2 / p0 / oc 尾 1
    add_layer('S3', dict(ic=16, kh=2, kw=2, sh=1, sw=1, ph=0, pw=0,
                         ih=17, iw=17, oc=9, act=0, first=0, lut_off=0))
    # L4 R2 —— model.16（输入 int8_model.15.cv2、期望 int8_model.16）
    add_layer('R2', dict(ic=64, kh=3, kw=3, sh=2, sw=2, ph=1, pw=1,
                         ih=40, iw=40, oc=64, act=1, first=0, lut_off=2560),
              real=('model.16', g4['int8_model.15.cv2'].tobytes(),
                    g4['int8_model.16'].ravel()))
    # L5 S4 —— K2304 / first=1 合成 pad-128 / last / 单 oc tile
    add_layer('S4', dict(ic=256, kh=3, kw=3, sh=1, sw=1, ph=1, pw=1,
                         ih=5, iw=5, oc=8, act=1, first=1, lut_off=5120))

    assert len(layers) == 6

    # ---- 覆盖断言（层维度） ----
    assert cov['k_tiers'] >= {27, 64, 576, 2304}, cov['k_tiers']
    assert cov['act_modes'] == {0, 1} and cov['first_modes'] == {0, 1}
    assert len(cov['shifts']) >= 8, sorted(cov['shifts'])
    assert cov['tie_ch'] >= 6 and cov['sat_ch'] >= 3 and cov['real_ch'] >= 17
    assert any(L['expsel'] for L in cov['layers'] if L['tag'] == 'R1')
    oc_tails = {L['oc'] % 8 for L in cov['layers'] if L['oc'] % 8}
    n_tails = {L['n'] % 8 for L in cov['layers'] if L['n'] % 8}
    assert {7, 1}.issubset(oc_tails) and 1 in n_tails, (oc_tails, n_tails)
    assert cov['layers'][-1]['last'] == 1

    # ---- 输出 ----
    out = HERE / 'stim' / 'm10'
    out.mkdir(parents=True, exist_ok=True)
    words_txt, n_words = img.words_hex()
    files['ddr.hex'] = words_txt
    files['n_ddrwords.hex'] = f'{n_words:08X}\n'
    files['n_layers.hex'] = f'{len(layers):08X}\n'
    lay_txt = []
    for row in layers:
        lay_txt.append(' '.join(f'{v:06X}' for v in row[:4]))
        lay_txt.append(' '.join(f'{v:06X}' for v in row[4:12]))
        lay_txt.append(' '.join(f'{v:06X}' for v in row[12:20]))
        lay_txt.append(' '.join(f'{v:06X}' for v in row[20:28]))
    files['layers.hex'] = '\n'.join(lay_txt) + '\n'

    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    manifest = {
        'name': 'm10', 'seed': SEED,
        'contract': 'yolo_gemm_array 6-layer plan S1/R1/S2/S3/R2/S4; '
                    'single DDR byte image (ddr.hex 64b LE words), W rows '
                    'KPAD-padded (DMA 8B alignment), per-layer tile-padded '
                    'bias/m/shift blocks, M0-golden mirror regions for '
                    'synthetic layers, real LUT slices from lut.bin',
        'golden': {
            'real_layers': 'rom_data (G2 run04 deployment export) + '
                           'run04 golden npz; python chain reproduced '
                           'run04 npz bit-exact (R1 0/409600, R2 0/25600)',
            'synthetic_layers': 'in-sim yolo_conv_core static instances',
            'npz': GOLD_NPZ,
        },
        'layer_plan': [f"L{L['idx']} {L['tag']} oc{L['oc']} n{L['n']} "
                       f"k{L['k']} ih{L['ih']} act{L['act']} "
                       f"first{L['first']} gap{L['gap']}"
                       for L in cov['layers']],
        'coverage': {k: (sorted(v) if isinstance(v, set) else v)
                     for k, v in cov.items() if k != 'layers'},
        'layers': cov['layers'],
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] m10: 6 layers (S1/R1/S2/S3/R2/S4) image={n_words} words '
          f'({n_words * 8} B), files={len(files)}, '
          f'k_tiers={sorted(cov["k_tiers"])}, tie/sat/real='
          f'{cov["tie_ch"]}/{cov["sat_ch"]}/{cov["real_ch"]}, '
          f'distinct_shifts={len(cov["shifts"])}, manifest written')


if __name__ == '__main__':
    main()
