"""M1 PE 双打包激励生成器 + Python 逐位黄金模型 + 全域穷举证明。

合同：架构基线 §3.2——单 DSP48E1 承载 w·x[n] 与 w·x[n+1] 两路独立
int8 乘积，乘积经位域分离后与逐路直乘逐位一致（数值合同不变）。

本生成器做三件事：
  1) **全域穷举证明（2^24 = 16777216 组，numpy 分块向量化）**：对三种
     布局各建独立位模型（按位拼 A/B、整数乘、按位提取 lane），与 w*x
     直乘比对：
       - doc_literal：基线 §3.2 字面（低字节=原码 x0、间隔 0、无借位
         回补）——负 x0 低通道误差 256*w，w<0 且 x0≠0 时高通道借位
         误差 1，穷举失败计数如实记录（方案缺陷证据）；
       - sext_gap：低字节符号扩展进间隔的直觉修正——低通道精确，但
         负 x0 的 17 位补码作为低位域按正权计入，高通道被污染
         w*[x0<0]，仍失败（本 run 试错记录）；
       - bias（采纳）：x0b=x0+128（MSB 翻转）无符号入低字节、间隔 0；
         lane0=$signed(P[16:0])−(w<<7)（解偏置）、
         lane1=$signed(P[33:17])+P[16]（借位回补）——全域 0 失败。
  2) TB 激励：定向角点（x0/x1/w ∈ {−128,−127,−1,0,1,127} 全交叉 216 组）
     + 随机 10^4 组（种子落盘），期望值取自 bias 位模型（已与直乘穷举
     等价）。
  3) manifest：形状/seed/三布局穷举结论/sha256。

产物（--out 目录，默认 sim/stim/pe_pack）：x0/x1/w（8 位 2 hex）与
p0_exp/p1_exp（17 位 5 hex）.hex + stim_manifest.json。
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent

N_RANDOM = 10000
SEED = 202
DIRECTED_POOL = [-128, -127, -1, 0, 1, 127]


def _signed_field(u, width):
    """无符号位型 -> 有符号值（numpy 向量化）。"""
    u = np.asarray(u, dtype=np.int64)
    sign = 1 << (width - 1)
    return np.where(u & sign, u - (1 << width), u)


def lanes_np(x0, x1, w, layout):
    """独立位模型（向量化）：拼 A/B -> 整数乘 -> 按位提取。

    layout: 'doc_literal' | 'sext_gap' | 'bias'
    """
    x0 = np.asarray(x0, dtype=np.int64)
    x1 = np.asarray(x1, dtype=np.int64)
    w = np.asarray(w, dtype=np.int64)
    x0b_raw = x0 & 0xFF
    if layout == 'doc_literal':
        low17 = x0b_raw                                  # 低字节原码
    elif layout == 'sext_gap':
        low17 = x0b_raw | np.where(x0b_raw & 0x80, 0x1FF00, 0)
    elif layout == 'bias':
        low17 = ((x0 + 128) & 0xFF)                      # 偏置无符号字节
    else:
        raise ValueError(layout)
    a = ((x1 & 0xFF) << 17) | low17                      # 25b 位型
    a_val = _signed_field(a, 25)                         # 位型 -> 有符号值
    benc = w & 0x3FFFF                                   # 18b 位型
    b_val = _signed_field(benc, 18)
    p_enc = (a_val * b_val) & ((1 << 43) - 1)
    p = _signed_field(p_enc, 43)
    if layout == 'doc_literal':
        lane0 = _signed_field(p & 0xFFFF, 16)
        lane1 = _signed_field((p >> 17) & 0x1FFFF, 17)
    elif layout == 'sext_gap':
        lane0 = _signed_field(p & 0x1FFFF, 17)
        lane1 = _signed_field((p >> 17) & 0x1FFFF, 17) \
            + ((p >> 16) & 1)
    else:                                                 # bias
        lane0 = _signed_field(p & 0x1FFFF, 17) - w * 128
        lane1 = _signed_field((p >> 17) & 0x1FFFF, 17) \
            + ((p >> 16) & 1)
    return lane0, lane1


def exhaustive_scan():
    """2^24 全域穷举三布局，返回 {layout: fails/total/first}。"""
    out = {}
    for layout in ('doc_literal', 'sext_gap', 'bias'):
        fails = 0
        first = None
        for x0 in range(-128, 128):                      # 按 x0 分块向量化
            x1 = np.arange(-128, 128, dtype=np.int64)
            w = np.arange(-128, 128, dtype=np.int64)
            x1g, wg = np.meshgrid(x1, w, indexing='ij')
            x0g = np.full_like(x1g, x0)
            l0, l1 = lanes_np(x0g, x1g, wg, layout)
            bad = (l0 != x0g * wg) | (l1 != x1g * wg)
            n = int(np.count_nonzero(bad))
            if n and first is None:
                idx = np.argwhere(bad)[0]
                i, j = int(idx[0]), int(idx[1])
                first = (x0, i - 128, j - 128,
                         int(l0[i, j]), x0 * (j - 128),
                         int(l1[i, j]), (i - 128) * (j - 128))
            fails += n
        out[layout] = {'fails': fails, 'total': 256 ** 3,
                       'first_fail': first}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out-root', type=Path, default=HERE / 'stim')
    args = ap.parse_args()

    print('[proof] exhaustive 2^24 scan (three layouts)...')
    proof = exhaustive_scan()
    for k, v in proof.items():
        ff = v['first_fail']
        ffs = ('x0=%d x1=%d w=%d lane0=%d(exp %d) lane1=%d(exp %d)' % ff
               if ff else 'none')
        print(f'[proof] {k}: fails={v["fails"]}/{v["total"]} first={ffs}')
    assert proof['bias']['fails'] == 0, \
        'bias layout must be exact over the full domain'
    assert proof['doc_literal']['fails'] > 0, \
        'doc-literal layout was expected to fail (evidence)'
    assert proof['sext_gap']['fails'] > 0, \
        'sext-gap layout was expected to fail (evidence)'

    rng = np.random.default_rng(SEED)
    x0v, x1v, wv = [], [], []
    for a in DIRECTED_POOL:
        for b in DIRECTED_POOL:
            for c in DIRECTED_POOL:
                x0v.append(a)
                x1v.append(b)
                wv.append(c)
    n_dir = len(x0v)
    x0v += rng.integers(-128, 128, size=N_RANDOM).tolist()
    x1v += rng.integers(-128, 128, size=N_RANDOM).tolist()
    wv += rng.integers(-128, 128, size=N_RANDOM).tolist()

    l0, l1 = lanes_np(x0v, x1v, wv, 'bias')
    assert np.array_equal(l0, np.asarray(x0v) * np.asarray(wv))
    assert np.array_equal(l1, np.asarray(x1v) * np.asarray(wv))

    def hex8(vals):
        return ''.join(f'{int(v) & 0xFF:02X}\n' for v in vals)

    def hex17(vals):
        return ''.join(f'{int(v) & 0x1FFFF:05X}\n' for v in vals)

    out = args.out_root / 'pe_pack'
    out.mkdir(parents=True, exist_ok=True)
    files = {
        'x0_i8.hex': hex8(x0v),
        'x1_i8.hex': hex8(x1v),
        'w_i8.hex': hex8(wv),
        'p0_exp_i17.hex': hex17(l0.tolist()),
        'p1_exp_i17.hex': hex17(l1.tolist()),
    }
    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    manifest = {
        'name': 'pe_pack',
        'seed': SEED,
        'vectors': {
            'directed': n_dir,
            'directed_pool': DIRECTED_POOL,
            'random': N_RANDOM,
            'total': n_dir + N_RANDOM,
        },
        'layout_adopted': 'bias: A={x1,9b0,x0+128}, B=sext(w), '
                          'lane0=$signed(P[16:0])-(w<<7), '
                          'lane1=$signed(P[33:17])+P[16]',
        'exhaustive_proof_2p24': proof,
        'gold_ref': 'lanes_np independent bit model == direct w*x, '
                    'exhaustively equated over 2^24',
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] pe_pack: {n_dir} directed + {N_RANDOM} random, '
          f'5 hex files, manifest written')


if __name__ == '__main__':
    main()
