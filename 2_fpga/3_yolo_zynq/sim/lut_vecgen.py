"""M6 SiLU LUT 激励生成器 + 黄金（真实 lut.bin 为参照）。

合同（rtl/yolo_silu_lut.v）：
  act=1: y = LUT[(y_pre + 128) & 0xFF]（+128 折叠由 8b 无符号回绕实现）；
  act=0: y = y_pre（位透传，noact 层）；
  en=0 保持 y_o；vld_o = en 打一拍；同步写口 we/waddr/wdata。

表集合（256 全索引走查 × 每表）：
  real00 / real02：conv0_golden00/02 真实 lut_i8.bin（真实数据回归）；
  identity：lut[i] = i-128（兼 noact 参照，256 distinct）；
  random：seed 606 全域 int8；
  extreme：-128/127 棋盘 + 端点单调段（近旁值敏感性）。
反退化断言：每表全 256 索引必走、每表 y distinct ≥ 8、act=0 ≥ 16、
  hold ≥ 16、identity 表 256 distinct、±128/±127 索引必含。
"""
import hashlib
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SEED = 606
N = 256


def load_tables():
    tables = {}
    for tag, gdir in (('real00', 'conv0_golden00'), ('real02', 'conv0_golden02')):
        tables[tag] = np.fromfile(HERE / 'stim' / gdir / 'lut_i8.bin',
                                  dtype=np.int8).astype(np.int64)
        assert tables[tag].shape == (N,)
    tables['identity'] = np.arange(N, dtype=np.int64) - 128
    rng = np.random.default_rng(SEED)
    tables['random'] = rng.integers(-128, 128, size=N, dtype=np.int64)
    ext = np.where(np.arange(N) % 2 == 0, -128, 127).astype(np.int64)
    ext[0:8] = np.arange(-128, -120)          # 端点单调段
    ext[248:256] = np.arange(120, 128)
    tables['extreme'] = ext
    return tables, rng


def build():
    tables, rng = load_tables()
    ops = []                                   # ('W', addr, data) / ('R', en, act, ypre, yexp)

    for tag, tab in tables.items():
        for i in range(N):                     # 装载段：写口 256 连写
            ops.append(('W', i, int(tab[i])))
        prev = 0
        n_hold = n_act0 = 0
        yps = []
        for i in range(N):                     # 走查段：y_pre -128..127 全索引
            yps.append(i - 128)
        for _ in range(24):                    # 复访随机点 + 旁路 + 保持
            yps.append(int(rng.integers(-128, 128)))
        for ypre in yps:
            r = rng.random()
            if r < 0.06:
                ops.append(('R', 0, 1, ypre, prev))   # hold
                n_hold += 1
            elif r < 0.14:
                ops.append(('R', 1, 0, ypre, ypre & 0xFF))    # act 旁路
                n_act0 += 1
                prev = ypre & 0xFF
            else:
                ops.append(('R', 1, 1, ypre, int(tab[ypre + 128]) & 0xFF))
                prev = int(tab[ypre + 128]) & 0xFF
        assert n_hold >= 3 and n_act0 >= 3, (tag, n_hold, n_act0)

    # ---- 覆盖统计与断言 ----
    n_w = sum(1 for o in ops if o[0] == 'W')
    n_r = sum(1 for o in ops if o[0] == 'R')
    n_hold = sum(1 for o in ops if o[0] == 'R' and o[1] == 0)
    n_act0 = sum(1 for o in ops if o[0] == 'R' and o[1] == 1 and o[2] == 0)
    for tag, tab in tables.items():
        dist = len({int(v) & 0xFF for v in tab})
        assert dist >= 8, (tag, dist)
    assert len({int(v) & 0xFF for v in tables['identity']}) == N
    cov = {'total_ops': len(ops), 'n_write': n_w, 'n_read': n_r,
           'n_hold': n_hold, 'n_act_bypass': n_act0,
           'tables': list(tables.keys()),
           'walk': 'all 256 indices per table, y_pre=-128..127 ascending',
           'real_tables': ['real00', 'real02']}
    assert n_hold >= 16 and n_act0 >= 16, cov
    return ops, tables, cov


def main():
    ops, tables, cov = build()
    out = HERE / 'stim' / 'lutmod'
    out.mkdir(parents=True, exist_ok=True)

    op_h, wa_h, wd_h = [], [], []
    en_h, act_h, yp_h, y_h = [], [], [], []
    for o in ops:
        if o[0] == 'W':
            op_h.append('0')
            wa_h.append(f'{o[1]:02X}')
            wd_h.append(f'{o[2] & 0xFF:02X}')
            en_h.append('0')
            act_h.append('0')
            yp_h.append('00')
            y_h.append('00')
        else:
            _, en, act, ypre, yexp = o
            op_h.append('1')
            wa_h.append('00')
            wd_h.append('00')
            en_h.append(f'{en:01X}')
            act_h.append(f'{act:01X}')
            yp_h.append(f'{ypre & 0xFF:02X}')
            y_h.append(f'{yexp:02X}')

    files = {
        'n_cycles.hex': f'{len(ops):08X}\n',
        'op.hex': ''.join(f'{v}\n' for v in op_h),
        'waddr_u8.hex': ''.join(f'{v}\n' for v in wa_h),
        'wdata_i8.hex': ''.join(f'{v}\n' for v in wd_h),
        'en.hex': ''.join(f'{v}\n' for v in en_h),
        'act.hex': ''.join(f'{v}\n' for v in act_h),
        'ypre_i8.hex': ''.join(f'{v}\n' for v in yp_h),
        'y_exp_i8.hex': ''.join(f'{v}\n' for v in y_h),
    }
    # 表本体快照（复现/审计；TB 不读，装载走写口以覆盖写路径）
    for tag, tab in tables.items():
        text = ''.join(f'{int(v) & 0xFF:02X}\n' for v in tab)
        files[f'lut_{tag}_i8.hex'] = text
    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    manifest = {
        'name': 'lutmod', 'seed': SEED,
        'contract': 'act1: y=LUT[(ypre+128)&0xFF]; act0: y=ypre bits; '
                    'en=0 hold; sync write port',
        'gold_ref': 'real lut_i8.bin (golden00/02) + identity/random/'
                    'extreme synthetic tables',
        'coverage': cov,
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] lutmod: {cov["total_ops"]} ops '
          f'(w={cov["n_write"]} r={cov["n_read"]} hold={cov["n_hold"]} '
          f'act0={cov["n_act_bypass"]}), tables={cov["tables"]}, '
          f'manifest written')


if __name__ == '__main__':
    main()
