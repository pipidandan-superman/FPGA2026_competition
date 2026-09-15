"""M2 累加器激励生成器 + Python 黄金模型。

合同（rtl/yolo_acc.v）：N_LANES 路独立 int32 累加器；clr 优先于 en；
en=0 保持（K 断点续累）；int32 补码自然回绕（与 numpy int32 位级一致）。

反退化纪律（沿用 M0 v2 / M1 教训）：
  - 定向段覆盖每个合同分支：清零、保持、K=576 断点续累（en 576 → hold 16
    → en 576）、clr&en 同拍（优先级）、±(2^31-1) 极值回绕对、en=0 期间
    巨值 d（保持不得吸收 d）；
  - 随机段混合小值/全幅 d 与稀疏 clr/en；
  - 生成器内覆盖断言：wrap 事件≥1、hold≥16、clr&en≥1、每 lane 最终
    |q| 有分布（非全 0/全同值）。
黄金：numpy int32 逐拍模拟（与 RTL 同优先级/同回绕），每拍每 lane 的
期望 q 落盘，TB 逐拍逐 lane 比对。

产物（--out 目录，默认 sim/stim/acc）：clr/en（1 位）+ d0..d7/q0..q7
（int32 8 hex）.hex + stim_manifest.json。
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent

N_LANES = 8
DATA_W = 32
SEED = 302

INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1


def wrap32(v):
    """int64 -> int32 回绕（与 numpy/RTL 一致）。"""
    v = int(v) & 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


def hex1(vals):
    return ''.join(f'{int(v) & 0xFFFFFFFF:08X}\n' for v in vals)


def hex_bit(vals):
    return ''.join(f'{int(v):01X}\n' for v in vals)


def build():
    rng = np.random.default_rng(SEED)
    clrs, ens, ds = [], [], []          # ds[k] = 8 元组
    marks = []

    def emit(clr, en, d8):
        clrs.append(clr)
        ens.append(en)
        ds.append(tuple(int(v) for v in d8))

    def rand_d8(mode):
        if mode == 'small':             # 典型 MAC 幅值
            return rng.integers(-40000, 40001, size=N_LANES)
        if mode == 'full':              # 全幅 int32
            return rng.integers(INT32_MIN, INT32_MAX + 1, size=N_LANES,
                                dtype=np.int64)
        return rng.integers(-2**31, 2**31, size=N_LANES, dtype=np.int64)

    # ---- A: 复位后清零 + 小值累加 64 拍（含 ramp 定向值）----
    marks.append('A_start')
    emit(1, 1, [0] * N_LANES)                     # clr&en 同拍：优先级证据
    for i in range(64):
        d = [wrap32((l + 1) * 1000 + i) for l in range(N_LANES)]
        emit(0, 1, d)
    marks.append('A_end')

    # ---- B: K=576 断点续累（en 576 → hold 16 → en 576）----
    marks.append('B_start')
    emit(1, 0, rand_d8('full'))                   # tile 清零
    for _ in range(576):
        emit(0, 1, rand_d8('small'))
    for _ in range(16):
        emit(0, 0, rand_d8('full'))               # hold 期间巨值不得吸收
    for _ in range(576):
        emit(0, 1, rand_d8('small'))
    marks.append('B_end')

    # ---- C: 极值回绕对（每 lane 造 |acc+d| ≥ 2^31 事件）----
    marks.append('C_start')
    emit(1, 0, [0] * N_LANES)
    emit(0, 1, [INT32_MAX - 3] * N_LANES)
    emit(0, 1, [7] * N_LANES)                     # MAX-3 +7 → 回绕负
    emit(0, 1, [INT32_MIN] * N_LANES)             # 再加 MIN → 再回绕
    emit(0, 1, [3] * N_LANES)
    emit(1, 0, [0] * N_LANES)
    emit(0, 1, [INT32_MIN + 2] * N_LANES)
    emit(0, 1, [-5] * N_LANES)                    # MIN+2 -5 → 回绕正
    marks.append('C_end')

    # ---- D: 随机 6000 拍（稀疏 clr 3%、en 85%、混合幅值）----
    marks.append('D_start')
    for _ in range(6000):
        clr = 1 if rng.random() < 0.03 else 0
        en = 1 if rng.random() < 0.85 else 0
        mode = rng.choice(['small', 'full'], p=[0.9, 0.1])
        emit(clr, en, rand_d8(mode))
    marks.append('D_end')

    # ---- 黄金模型（逐拍）----
    qs = []
    acc = [0] * N_LANES
    n_wrap = 0
    n_hold = 0
    n_clren = 0
    for clr, en, d8 in zip(clrs, ens, ds):
        if clr:
            acc = [0] * N_LANES
            if en:
                n_clren += 1
        elif en:
            for l in range(N_LANES):
                s = acc[l] + d8[l]
                if not (INT32_MIN <= s <= INT32_MAX):
                    n_wrap += 1
                acc[l] = wrap32(s)
        else:
            n_hold += 1
        qs.append(tuple(acc))

    # ---- 覆盖断言 ----
    assert n_wrap >= 4, f'wrap events {n_wrap}'
    assert n_hold >= 100, f'hold cycles {n_hold}'
    assert n_clren >= 1, 'clr&en priority case missing'
    for l in range(N_LANES):
        col = np.array([q[l] for q in qs])
        assert np.count_nonzero(col == 0) < len(col) * 0.9
        assert len(np.unique(col)) > 100
    return clrs, ens, ds, qs, {
        'wrap_events': n_wrap, 'hold_cycles': n_hold,
        'clr_and_en_events': n_clren, 'total_cycles': len(clrs),
        'marks': marks,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out-root', type=Path, default=HERE / 'stim')
    args = ap.parse_args()

    clrs, ens, ds, qs, cov = build()
    out = args.out_root / 'acc'
    out.mkdir(parents=True, exist_ok=True)
    files = {
        'clr.hex': hex_bit(clrs),
        'en.hex': hex_bit(ens),
        'n_cycles.hex': f'{len(clrs):08X}\n',
    }
    for l in range(N_LANES):
        files[f'd{l}_i32.hex'] = hex1([d[l] for d in ds])
        files[f'q{l}_exp_i32.hex'] = hex1([q[l] for q in qs])
    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    manifest = {
        'name': 'acc',
        'seed': SEED,
        'n_lanes': N_LANES,
        'data_w': DATA_W,
        'contract': 'clr > en(hold when 0) > int32 wrap add; '
                    'q checked every cycle every lane',
        'coverage': cov,
        'gold_ref': 'numpy-int32-equivalent python model (wrap32), '
                    'same priority order as RTL',
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] acc: {cov["total_cycles"]} cycles x {N_LANES} lanes, '
          f'wrap={cov["wrap_events"]} hold={cov["hold_cycles"]} '
          f'clr&en={cov["clr_and_en_events"]}, manifest written')


if __name__ == '__main__':
    main()
