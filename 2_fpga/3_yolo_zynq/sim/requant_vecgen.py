"""M5 requant 激励生成器 + Python 黄金（pynq/intarith.py 为参照）。

合同（rtl/yolo_requant.v）：
  sum_b = acc + bias_eff（33b）；n = sum_b * m（int64 精确，|n| < 2^63）；
  y_pre = sat_i8(rne_shift(n, shift))，shift ∈ [0,62]，m ≠ INT32_MIN；
  en=0 保持 y_pre（期望 = 上一拍值）；vld_o = en 打一拍。

反退化纪律（M0 v2 模板）——本门核心风险是 RNE 平局/饱和轨测不到：
  T 平局构造：n = q·2^s ± 2^(s-1)，因式分解 m=2^k（k=min(30,s-1)）+
    sum_b=n>>k 落到合法 (acc,bias) 对；q 奇/偶、rem 正/负全覆盖，
    s ∈ {1,2,3,5,30,31,32,40,53,62}；
  S 饱和轨：m=1 定向 n=k·2^s（k 绕 ±127/±128 环带）+ RNE 恰好滚入轨
    （127·2^s+2^(s-1) 平局→128→截 127 等）+ m=±(2^31-1) 大乘积轨；
  C 角点：acc/bias ∈ {±MIN,±MAX,0} 组合 × m 七种 × s ∈ {0,31,62}；
  R 真实回归：golden00/02（真实 x/w/bias_eff/m/shift/lut/y）重算真实
    acc，intarith 得 y_pre，并断言 LUT[y_pre+128] == 真实 y_exp（真实
    链闭合证据）；两 golden × 16 oc × 64 像素 = 2048 点；
  X 随机 20000：全域 acc/bias，m 七成现实域 [2^30,2^31)，shift 加权，
    5% en=0 保持。
生成器内覆盖断言：tie(q 奇/偶 × rem 正/负) 各≥4、饱和事件≥16、
  y_pre ∈ {127,-128} 各≥8、y_pre distinct≥64、hold≥200、
  全向量 |n| < 2^63 且 m ≠ INT32_MIN 且 shift ≤ 62。
"""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'pynq'))
import intarith                      # noqa: E402  (G2 位级合同参照)

SEED = 505
INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1
N_RANDOM = 20000
GOLDENS = ['conv0_golden00', 'conv0_golden02']
PIX_PER_OC = 64

TIE_SHIFTS = [1, 2, 3, 5, 30, 31, 32, 40, 53, 62]
TIE_QS = [-128, -127, -3, -2, -1, 0, 1, 2, 3, 126, 127]
RAIL_KS = [0, 1, -1, 126, -126, 127, -127, 128, -128, 129, -129,
           254, -254, 255, -255, 256, -256, 257, -257]
CORNER_ACCS = [INT32_MIN, INT32_MAX, INT32_MIN, INT32_MAX, 0]
CORNER_BIASES = [INT32_MIN, INT32_MAX, INT32_MAX, INT32_MIN, 0]
CORNER_MS = [1, -1, INT32_MAX, -INT32_MAX, 1 << 30, 123456789, -987654321]
CORNER_SS = [0, 31, 62]


def split_pair(sum_b):
    """33b 和拆成两个合法 int32（acc 吃满幅，bias 补余）。"""
    if sum_b > INT32_MAX:
        return INT32_MAX, sum_b - INT32_MAX
    if sum_b < INT32_MIN:
        return INT32_MIN, sum_b - INT32_MIN
    return sum_b, 0


def rne_parts(n, s):
    """精确 (q, rem)：与 intarith 同式，供平局覆盖统计。"""
    q = n >> s
    return q, n - (q << s)


def golden_batch(vecs):
    """对 en=1 向量批量求 y_pre（intarith.rne_shift/sat_i8 逐唯一 shift）。"""
    n_arr = np.array([v['n'] for v in vecs], dtype=np.int64)
    s_arr = np.array([v['shift'] for v in vecs], dtype=np.int64)
    out = np.zeros(len(vecs), dtype=np.int64)
    for s in np.unique(s_arr):
        idx = np.nonzero(s_arr == s)[0]
        out[idx] = intarith.rne_shift(n_arr[idx], int(s))
    return intarith.sat_i8(out)


_LUT_CACHE = {}
_Y_CACHE = {}


def _lut(gdir):
    if gdir not in _LUT_CACHE:
        _LUT_CACHE[gdir] = np.fromfile(HERE / 'stim' / gdir / 'lut_i8.bin',
                                       dtype=np.int8).astype(np.int64)
    return _LUT_CACHE[gdir]


def _y(gdir):
    if gdir not in _Y_CACHE:
        _Y_CACHE[gdir] = np.fromfile(HERE / 'stim' / gdir / 'y_exp_i8.bin',
                                     dtype=np.int8).reshape(16, 160, 160)
    return _Y_CACHE[gdir]


def build_real(rng):
    """真实回归：golden00/02 真实 x/w 重算 acc + 真实 requant 参数。"""
    vecs = []
    n_pts = 0
    for gdir in GOLDENS:
        base = HERE / 'stim' / gdir
        x = np.fromfile(base / 'x_i8.bin', dtype=np.int8).astype(np.int64)
        x = x.reshape(3, 320, 320)
        w = np.fromfile(base / 'w_i8.bin', dtype=np.int8).astype(np.int64)
        w = w.reshape(16, 3, 3, 3)
        bias = np.fromfile(base / 'bias_eff_i32.bin', dtype=np.int32)
        m = np.fromfile(base / 'm_i32.bin', dtype=np.int32)
        sh = np.fromfile(base / 'shift_u8.bin', dtype=np.uint8)
        xp = np.full((3, 322, 322), -128, dtype=np.int64)
        xp[:, 1:321, 1:321] = x
        for oc in range(16):
            for oy, ox in rng.integers(0, 160, size=(PIX_PER_OC, 2)):
                acc = int(np.sum(xp[:, 2*oy:2*oy+3, 2*ox:2*ox+3]
                                 * w[oc].reshape(3, 3, 3)))
                vecs.append({'acc': acc, 'bias': int(bias[oc]),
                             'm': int(m[oc]), 'shift': int(sh[oc]),
                             'en': 1, 'src': gdir,
                             'loc': (int(oc), int(oy), int(ox))})
                n_pts += 1
    for v in vecs:
        v['n'] = (v['acc'] + v['bias']) * v['m']
    ypre = golden_batch(vecs)
    for v, yp in zip(vecs, ypre):
        oc, oy, ox = v['loc']
        assert int(_lut(v['src'])[int(yp) + 128]) == int(_y(v['src'])[oc, oy, ox]), \
            f'real-chain closure broke: {v["src"]}{v["loc"]} yp={yp}'
    return vecs, n_pts


def build():
    rng = np.random.default_rng(SEED)
    vecs = []

    def add(acc, bias, m, shift, en=1):
        assert INT32_MIN <= acc <= INT32_MAX
        assert INT32_MIN <= bias <= INT32_MAX
        assert m != INT32_MIN
        assert 0 <= shift <= 62
        vecs.append({'acc': int(acc), 'bias': int(bias), 'm': int(m),
                     'shift': int(shift), 'en': int(en)})

    # ---- T：平局构造（q 奇/偶 × rem 正/负 × s 宽域）----
    for s in TIE_SHIFTS:
        for q in TIE_QS:
            for rs in (1, -1):
                n = (q << s) + rs * (1 << (s - 1))
                k = min(30, s - 1)
                if abs(n >> k) > (1 << 32):
                    continue
                if n % (1 << k) != 0:
                    continue
                acc, bias = split_pair(n >> k)
                add(acc, bias, 1 << k, s)

    # ---- S：饱和轨 ----
    for s in (0, 1, 5, 31):
        for k in RAIL_KS:
            n = k << s
            if abs(n) <= INT32_MAX:
                add(n, 0, 1, s)
                add(n, 0, -1, s)             # 负乘子翻轨
    for s in (1, 5, 31):                     # RNE 恰好滚入轨
        for n in (127 << s) + (1 << (s-1)), (127 << s) + (1 << (s-1)) - 1, \
                 (127 << s) + (1 << (s-1)) + 1, \
                 -(129 << s) - (1 << (s-1)), -(129 << s) - (1 << (s-1)) + 1:
            if abs(n) <= INT32_MAX:
                add(n, 0, 1, s)
    for s in (0, 1):                         # 大乘积轨
        for acc in (INT32_MAX, -INT32_MAX, INT32_MIN):
            add(acc, 0, INT32_MAX, s)
            add(acc, 0, -INT32_MAX, s)

    # ---- C：参数角点 ----
    for acc, bias in zip(CORNER_ACCS, CORNER_BIASES):
        for m in CORNER_MS:
            for s in CORNER_SS:
                add(acc, bias, m, s)

    # ---- R：真实回归 ----
    real_vecs, n_real = build_real(rng)
    vecs.extend(real_vecs)

    # ---- X：全域随机 + 保持 ----
    for _ in range(N_RANDOM):
        acc = int(rng.integers(INT32_MIN, INT32_MAX + 1, dtype=np.int64))
        bias = int(rng.integers(INT32_MIN, INT32_MAX + 1, dtype=np.int64))
        r = rng.random()
        if r < 0.70:
            m = int(rng.integers(1 << 30, 1 << 31, dtype=np.int64))
        elif r < 0.80:
            m = int(rng.choice([INT32_MAX, -INT32_MAX]))
        else:
            m = int(rng.integers(INT32_MIN + 1, INT32_MAX + 1,
                                 dtype=np.int64))
        if rng.random() < 0.60:
            shift = int(rng.integers(28, 46))
        else:
            shift = int(rng.integers(0, 63))
        en = 1 if rng.random() < 0.95 else 0
        add(acc, bias, m, shift, en)

    vecs[0]['en'] = 1                        # 首拍不得保持（复位值无意义）

    # ---- 黄金 + 保持后处理 ----
    for v in vecs:
        v['n'] = (v['acc'] + v['bias']) * v['m']
    assert all(abs(v['n']) < (1 << 63) for v in vecs)
    en_idx = [i for i, v in enumerate(vecs) if v['en']]
    ypre = golden_batch([vecs[i] for i in en_idx])
    for i, yp in zip(en_idx, ypre):
        vecs[i]['yp'] = int(yp)
    for i, v in enumerate(vecs):
        if not v['en']:
            v['yp'] = vecs[i - 1]['yp']

    # ---- 覆盖统计与断言 ----
    # 注：q = n>>s 为 floor，rem = n - q·2^s 恒 ∈ [0, 2^s)（intarith 的
    # twice < -full 分支为死代码）——平局分类按 q 奇偶（round 方向）计。
    tie_q_odd = tie_q_even = 0
    sat_evt = 0
    yp127 = ypm128 = 0
    for i in en_idx:
        v = vecs[i]
        q, rem = rne_parts(v['n'], v['shift'])
        full = 1 << v['shift']
        if 2 * rem == full:
            if q & 1:
                tie_q_odd += 1
            else:
                tie_q_even += 1
        pre = q + (1 if 2 * rem > full else 0)
        if not (-128 <= pre <= 127):
            sat_evt += 1
        if v['yp'] == 127:
            yp127 += 1
        if v['yp'] == -128:
            ypm128 += 1
    n_hold = sum(1 for v in vecs if not v['en'])
    n_distinct = len({vecs[i]['yp'] for i in en_idx})
    cov = {'total': len(vecs), 'n_en': len(en_idx), 'n_hold': n_hold,
           'tie_q_odd': tie_q_odd, 'tie_q_even': tie_q_even,
           'sat_events': sat_evt, 'yp_eq_127': yp127, 'yp_eq_m128': ypm128,
           'yp_distinct': n_distinct, 'real_points': n_real,
           'real_chain_closure': 'PASS'}
    assert tie_q_odd >= 8 and tie_q_even >= 8, cov
    assert sat_evt >= 16 and yp127 >= 8 and ypm128 >= 8, cov
    assert n_distinct >= 64, cov
    assert n_hold >= 200, cov
    return vecs, cov


def main():
    vecs, cov = build()
    out = HERE / 'stim' / 'requant'
    out.mkdir(parents=True, exist_ok=True)

    def h32(v):
        return f'{v & 0xFFFFFFFF:08X}\n'

    files = {
        'n_cycles.hex': f'{len(vecs):08X}\n',
        'en.hex': ''.join(f'{v["en"]:01X}\n' for v in vecs),
        'acc_i32.hex': ''.join(h32(v['acc']) for v in vecs),
        'bias_i32.hex': ''.join(h32(v['bias']) for v in vecs),
        'm_i32.hex': ''.join(h32(v['m']) for v in vecs),
        'shift_u8.hex': ''.join(f'{v["shift"]:02X}\n' for v in vecs),
        'ypre_exp_i8.hex': ''.join(f'{v["yp"] & 0xFF:02X}\n' for v in vecs),
    }
    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    manifest = {
        'name': 'requant', 'seed': SEED,
        'contract': 'y_pre = sat_i8(rne_shift((acc+bias)*m, shift)); '
                    'shift in [0,62]; m != INT32_MIN; en=0 holds',
        'gold_ref': 'pynq/intarith.py rne_shift+sat_i8 (G2 bit-exact)',
        'segments': 'T ties / S sat rails / C corners / R real goldens / '
                    f'X random {N_RANDOM} (5% hold)',
        'coverage': cov,
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] requant: {cov["total"]} vectors '
          f'(en={cov["n_en"]} hold={cov["n_hold"]}), '
          f'ties(q_odd/q_even)={cov["tie_q_odd"]}/{cov["tie_q_even"]}, '
          f'sat={cov["sat_events"]}, '
          f'yp_distinct={cov["yp_distinct"]}, real={cov["real_points"]}, '
          f'manifest written')


if __name__ == '__main__':
    main()
