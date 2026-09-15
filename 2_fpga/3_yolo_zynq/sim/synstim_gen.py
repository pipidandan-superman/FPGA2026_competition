"""M0 合成激励生成器 v2：任意形状 conv 的 DUT 仿真激励 + Python 黄金期望。

合同唯一权威：pynq/intarith.py（rne_shift/sat_i8），语义对齐
yolo_runtime._conv（pad_val = first ? -128 : 0；K 序 = ic*(KH*KW)+kh*KW+kw；
acc int32；n int64 = (acc+bias_eff)*M；sat_i8(rne_shift(n,s))；可选 LUT）。

v2 教训（run01，重要）：v1 用 shift∈{1,2,7,...}+全幅 bias+31 位 M，n/2^s
必然巨饱和或趋零，requant 输出退化为常数，把 RTL 的 k 分解 bug 完全掩盖
（合成 9 例全"PASS"而真实 conv0 FAIL）。v2 反退化三原则：
  1) 通道输出必须"活着"：q 中心 ≤ ~170 且 q 散布 ≥ 数十 LSB（bias 幅值
     取 ~acc_abs_typ，denom ≤ 2·typ，随机填充下 acc 散布/typ ≈ 8 →
     q 散布 ≈ 5×q 中心，天然远超 8 个 LSB 档）；
  2) 平局通道 n_tie=min(4,OC−1) 个（OC≥3；OC=2 时 1 个）：s=31、M=+2^30、
     bias=δ−acc[p*]，δ∈{+1,−1,+3,+5} → 该像素 n=δ·2^30 精确落在
     q=+0.5/−0.5/+1.5/+2.5 的非饱和 RNE 平局点，分别暴露 half-up（+0.5→1）、
     截断（−0.5→−1、+1.5→1）、偶保持缺失（+2.5→3）四类错误舍入；
     构造后在生成器内反验 n mod 2^s == 2^(s-1)；
  3) 饱和通道紧随平局通道：M=±(2^31−1)、s=36、bias ~±2^20 → |q|≫127，
     保证饱和事件 ≥1；其余现实域通道 M∈[2^28,2^31)、
     s=round(log2(denom·M/target))，target=|q中心|∈[4,120]——与真实量化
     从 M/标度导出 shift 的方向一致，而非独立随机。
逐通道退化断言：sat_i8(q) 不同值数 ≥8（zero 填充/平局/饱和通道豁免）。

产物（--out 目录，默认 sim/stim/<name>）：与 conv0_goldenNN 同构的
x_i8/w_i8/bias_eff_i32/m_i32/shift_u8/lut_i8/y_exp_i8 的 .bin + .hex
+ stim_manifest.json（形状/seed/fill/sha256/统计与自检结果）。

自检：numpy im2col 参考与纯 Python naive 参考（独立 im2col 路径）随机抽点
一致才落盘。
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'pynq'))
from intarith import rne_shift, sat_i8  # noqa: E402

TIE_DELTAS = [1, -1, 3, 5]   # q = ±0.5 / +1.5 / +2.5 平局四类
TIE_SHIFT = 31


def to_hex(arr, width_bytes):
    mask = (1 << (8 * width_bytes)) - 1
    return '\n'.join(
        format(int(v) & mask, 'X').zfill(2 * width_bytes) for v in arr.ravel()
    ) + '\n'


def im2col_acc(x, w, sh, sw, ph, pw, pad_val):
    """返回 acc int32 [oc,ho,wo]（不依赖 requant 参数）。"""
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
                cols[pos] = xp[c, i:i + sh * ho:sh, j:j + sw * wo:sw].reshape(-1)
                pos += 1
    return (w.reshape(oc, -1).astype(np.int32) @ cols).reshape(oc, ho, wo)


def requant(acc, bias_eff, m, shift, lut, has_act):
    """返回 (y int8, q_pre_sat int64, n int64)。"""
    oc, ho, wo = acc.shape
    y = np.empty((oc, ho, wo), dtype=np.int8)
    q_all = np.empty((oc, ho, wo), dtype=np.int64)
    n_all = np.empty((oc, ho, wo), dtype=np.int64)
    for c in range(oc):
        n = (acc[c].astype(np.int64) + np.int64(bias_eff[c])) * np.int64(m[c])
        q = rne_shift(n, int(shift[c]))
        n_all[c] = n
        q_all[c] = q
        y[c] = sat_i8(q)
    if has_act:
        y = lut[(y.astype(np.int16) + 128).astype(np.uint8)]
    return y, q_all, n_all


def naive_ref(x, w, bias_eff, m, shift, lut, sh, sw, ph, pw, pad_val, has_act,
              points):
    """纯 Python 三重循环参考，只在抽点上计算（独立 im2col 路径）。"""
    ic, ih, iw = x.shape
    oc, _, kh, kw = w.shape
    ho = (ih + 2 * ph - kh) // sh + 1
    wo = (iw + 2 * pw - kw) // sw + 1
    out = {}
    for oc_i, oy, ox in points:
        acc = 0
        for kk in range(ic * kh * kw):
            c, r = divmod(kk, kh * kw)
            i, j = divmod(r, kw)
            y_i = oy * sh + i - ph
            x_j = ox * sw + j - pw
            xv = int(x[c, y_i, x_j]) if (0 <= y_i < ih and 0 <= x_j < iw) \
                else pad_val
            acc += int(w[oc_i, c, i, j]) * xv
        n = (acc + int(bias_eff[oc_i])) * int(m[oc_i])
        q = int(sat_i8(rne_shift(np.int64(n), int(shift[oc_i]))))
        if has_act:
            q = int(lut[(q + 128) & 0xFF])
        out[(oc_i, oy, ox)] = q
    return out


def channel_plan(oc):
    """通道角色分配：任意 OC≥2 必含 ≥1 平局 + ≥1 现实域通道（小 OC 时
    现实域优先于多余平局/饱和通道，否则整例 y 退化成常数——genD 教训）；
    OC≥4 起补足 4 类平局，OC≥6 起末通道为确定性饱和通道。"""
    if oc == 2:
        return ['tie0', 'real']
    if oc == 3:
        return ['tie0', 'tie1', 'real']
    plan = (['tie0', 'tie1', 'real', 'tie2', 'tie3'] + ['real'] * oc)[:oc]
    if oc >= 6:
        plan[oc - 1] = 'sat'
    return plan


def gen_req_params(rng, oc, acc, ho, wo):
    """构造 bias_eff/m/shift：平局通道 + 饱和通道 + 现实域通道。

    现实域通道的反退化条件（v2 核心教训）：若 |q_center| ≫ acc 动态范围
    投影到 q 轴的散布，整通道饱和成常数、失去检出力。因此 bias 幅值取
    ~acc_abs_typ（denom ≤ 2·typ），shift 由 s=round(log2(denom·M/target))
    导出而非独立随机——M 保持真实幅值 [2^28,2^31)。首个现实域通道强制
    target∈[80,120]（高中心 → q 散布 ≈5×中心 → 确定性覆盖饱和沿 + 富值）。
    返回 (bias, m, shift, 专门通道集合)。
    """
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
            # 构造反验：n = δ·2^30 必须精确半幅平局
            n_t = (int(acc[c, py, px]) + int(bias[c])) * int(m[c])
            assert (n_t & ((1 << TIE_SHIFT) - 1)) == (1 << (TIE_SHIFT - 1)), \
                f'tie construction broken ch{c}: n={n_t}'
        elif role == 'sat':
            # 确定性饱和通道：M=±(2^31-1)、s=36、bias ~±2^20 → |q| ≫ 127
            shift[c] = 36
            m[c] = (1 << 31) - 1 if c % 2 == 0 else -((1 << 31) - 1)
            bias[c] = int(rng.integers(1, 2**20 + 1)) \
                * (1 - 2 * int(rng.integers(0, 2)))
        else:
            # 现实域：target = |q 中心|，shift 从 M/标度导出
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
    spec = sorted(c for c, r in enumerate(plan) if r != 'real')
    return (bias.astype(np.int32), m.astype(np.int32),
            shift.astype(np.uint8), spec, plan)


def make_case(name, ic, oc, kh, kw, ih, iw, sh, sw, ph, pw, pad_val, has_act,
              fill, seed, out_root):
    rng = np.random.default_rng(seed)
    kp = ic * kh * kw
    ho = (ih + 2 * ph - kh) // sh + 1
    wo = (iw + 2 * pw - kw) // sw + 1

    if fill == 'random':
        x = rng.integers(-128, 128, size=(ic, ih, iw), dtype=np.int8)
        w = rng.integers(-128, 128, size=(oc, ic, kh, kw), dtype=np.int8)
    elif fill == 'zero':
        x = np.zeros((ic, ih, iw), dtype=np.int8)
        w = rng.integers(-128, 128, size=(oc, ic, kh, kw), dtype=np.int8)
    elif fill == 'extreme':
        pool = np.array([-128, 127, -1, 0, 1], dtype=np.int8)
        x = rng.choice(pool, size=(ic, ih, iw)).astype(np.int8)
        w = rng.choice(pool, size=(oc, ic, kh, kw)).astype(np.int8)
    else:
        raise ValueError(fill)

    acc = im2col_acc(x, w, sh, sw, ph, pw, pad_val)
    bias_eff, m, shift, spec_ch, plan = gen_req_params(rng, oc, acc, ho, wo)
    lut = rng.integers(-128, 128, size=256, dtype=np.int8)
    y, q_all, n_all = requant(acc, bias_eff, m, shift, lut, has_act)

    # ---- 覆盖/退化统计与断言 ----
    stats = {'tie': 0, 'sat': 0}
    for c in range(oc):
        s = int(shift[c])
        rem = n_all[c] & ((1 << s) - 1)
        stats['tie'] += int(np.count_nonzero(rem == (1 << (s - 1))))
        stats['sat'] += int(np.count_nonzero(np.abs(q_all[c]) > 127))
    assert stats['tie'] >= 1, f'{name}: no RNE tie covered'
    assert stats['sat'] >= 1, f'{name}: no saturation covered'
    if fill != 'zero':
        for c in range(oc):
            if c in spec_ch:
                continue          # 平局/饱和专门通道（大幅 q，天然少值）
            distinct = len(np.unique(sat_i8(q_all[c])))
            assert distinct >= 8, \
                f'{name}: ch{c} requant degenerate ({distinct} values)'
        assert len(np.unique(y)) >= 8, f'{name}: y degenerate'

    # ---- 抽点自检：naive 参考复算 ----
    pts = set()
    for c in range(oc):
        pts.add((c, 0, 0))
        pts.add((c, ho - 1, wo - 1))
    while len(pts) < min(4 * oc + 8, oc * ho * wo):
        pts.add((int(rng.integers(0, oc)), int(rng.integers(0, ho)),
                 int(rng.integers(0, wo))))
    naive = naive_ref(x, w, bias_eff, m, shift, lut, sh, sw, ph, pw, pad_val,
                      has_act, sorted(pts))
    for p, v in naive.items():
        assert int(y[p]) == v, f'{name}: naive mismatch at {p}: ' \
                               f'vec={y[p]} naive={v}'

    out_dir = Path(out_root) / name
    out_dir.mkdir(parents=True, exist_ok=True)
    files = {
        'x_i8.bin': x.tobytes(),
        'w_i8.bin': w.tobytes(),
        'bias_eff_i32.bin': bias_eff.tobytes(),
        'm_i32.bin': m.tobytes(),
        'shift_u8.bin': shift.tobytes(),
        'lut_i8.bin': lut.tobytes(),
        'y_exp_i8.bin': y.tobytes(),
    }
    hexes = {
        'x_i8.hex': to_hex(x, 1),
        'w_i8.hex': to_hex(w, 1),
        'bias_eff_i32.hex': to_hex(bias_eff, 4),
        'm_i32.hex': to_hex(m, 4),
        'shift_u8.hex': to_hex(shift.astype(np.uint8), 1),
        'lut_i8.hex': to_hex(lut, 1),
        'y_exp_i8.hex': to_hex(y, 1),
    }
    for fn, data in files.items():
        (out_dir / fn).write_bytes(data)
    for fn, text in hexes.items():
        (out_dir / fn).write_text(text, encoding='ascii')

    manifest = {
        'name': name,
        'seed': seed,
        'fill': fill,
        'shape': {
            'ic': ic, 'oc': oc, 'kh': kh, 'kw': kw, 'ih': ih, 'iw': iw,
            'sh': sh, 'sw': sw, 'ph': ph, 'pw': pw,
            'pad_val': pad_val, 'has_act': has_act,
            'kp': kp, 'oh': ho, 'ow': wo, 'ny': oc * ho * wo,
        },
        'k_layout': 'K = ic*(KH*KW) + kh*KW + kw  (w stored [oc][ic][kh][kw])',
        'shift_list': shift.tolist(),
        'm_list': m.tolist(),
        'bias_list': bias_eff.tolist(),
        'req_param_domain': 'v2: tie ch delta +1/-1/+3/+5 (s=31, M=+2^30); '
                            'sat ch M=+-(2^31-1) s=36; realistic M in '
                            '[2^28,2^31), s=round(log2((typ+|bias|)*M/target)),'
                            ' first real ch target in [80,120]',
        'channel_plan': plan,
        'specialized_channels': spec_ch,
        'coverage_stats': stats,
        'y_distinct': int(len(np.unique(y))),
        'sha256': {fn: hashlib.sha256(d).hexdigest()
                   for fn, d in files.items()},
        'selfcheck_vec_vs_naive': 'PASS',
        'ref': 'intarith.rne_shift/sat_i8 (unique authority)',
    }
    (out_dir / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] {name}: IC={ic} OC={oc} K={kh}x{kw}x{ic}={kp} '
          f'{ih}x{iw}->s{sh},p{ph} {ho}x{wo} pad={pad_val} act={has_act} '
          f'fill={fill} seed={seed} tie={stats["tie"]} sat={stats["sat"]} '
          f'y_distinct={len(np.unique(y))} self-check PASS')


CASES = [
    # name, ic, oc, kh, kw, ih, iw, sh, sw, ph, pw, pad, act, fill, seed
    ('genA_k27_s2p1_rand',   3, 16, 3, 3, 96, 96, 2, 2, 1, 1, -128, 1, 'random', 101),
    ('genA_k27_s2p1_ext',    3, 16, 3, 3, 96, 96, 2, 2, 1, 1, -128, 1, 'extreme', 102),
    ('genB_k576_s1p1_rand', 64,  8, 3, 3, 40, 40, 1, 1, 1, 1,    0, 1, 'random', 103),
    ('genC_k256_1x1_noact_rand', 256, 7, 1, 1, 10, 10, 1, 1, 0, 0, 0, 0, 'random', 104),
    ('genC_k256_1x1_noact_zero', 256, 7, 1, 1, 10, 10, 1, 1, 0, 0, 0, 0, 'zero', 105),
    ('genD_k2304_s1p1_rand', 256, 4, 3, 3, 12, 12, 1, 1, 1, 1,    0, 1, 'random', 106),
    ('genE_k45_n49_rand',    5,  5, 3, 3,  9,  9, 1, 1, 0, 0,    0, 1, 'random', 107),
    ('genF_k32_1x1_s2p0_ext', 32, 3, 1, 1, 13, 13, 2, 2, 0, 0,   0, 1, 'extreme', 108),
    ('genG_k64_1x1_rand',   64,  2, 1, 1,  8,  8, 1, 1, 0, 0,    0, 1, 'random', 109),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out-root', type=Path, default=HERE / 'stim')
    ap.add_argument('--only', type=str, default=None,
                    help='只生成指定 name（逗号分隔），默认全部')
    args = ap.parse_args()
    names = set(args.only.split(',')) if args.only else None
    for c in CASES:
        if names and c[0] not in names:
            continue
        make_case(c[0], *c[1:15], args.out_root)


if __name__ == '__main__':
    main()
