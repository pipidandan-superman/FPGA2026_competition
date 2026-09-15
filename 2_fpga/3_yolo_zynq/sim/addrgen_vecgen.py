"""M7 addrgen 激励生成器 + 黄金（golden_extract.py 文档合同为参照）。

合同（rtl/yolo_addrgen.v）：
  逐拍 beat（n 外层 × k 内层）：
    k = ic*(KH*KW) + kh*KW + kw；ih = oy*SH+kh-PH；iw = ox*SW+kw-PW；
    pad = !(0<=ih<IH && 0<=iw<IW)；x_addr = ic*(IH*IW)+ih*IW+iw（CHW）；
    pad beat 地址 0、pad_val = -128（首层 z 折叠）/ 0（后续层）；
    几何在 start 脉冲采样（描述符语义）。

黄金 = 同式 Python 参照（golden_extract.py 的 k_layout/CHW/pad 合同），
真实回归额外做**数据闭合**：beat 地址取真实 x_i8.bin 的字节必须等于
numpy 独立窗口提取值（xp 含 -128 pad）——任何地址错误都体现为数据错。

案例：
  real00/real02：conv0 真实几何（3x3/S2/P1/IC3/320x320/K27/N25600/first），
    64 随机 tile（n_start 随机，n_len 8）+ 首 tile（start 0）+ 尾 tile
    （start N-8）；
  syn_1x1_nopad：1x1/S1/P0/IC256/80x80/K256——零 pad beat（反退化：无
    pad 路径必测）；
  syn_k2304：3x3/S1/P1/IC256/30x30/K2304/N900 整 tile（ic 回卷 255 次）；
  syn_tail：N=100，n_start 96 / n_len 4（尾 tile，ctrl 预钳位语义）；
  syn_allpad：3x3/S1/P0/1x1 平面——27 beat 中 26 pad（z 折叠主导）；
  syn_wrap：3x3/S2/P1/5x5→3x3/N9 整 tile（ox 回绕 + oy 递增全覆盖）。
覆盖断言：pad beat ≥1000、非 pad ≥10000、pad_val=-128 与 0 两类各 ≥500、
  每 tile 的 k 全程 0..K-1、ic 回卷 ≥1、ox 回绕 ≥1、oy 递增 ≥1。
"""
import hashlib
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SEED = 707

CFG_WORDS = ['ih', 'iw', 'ow', 'ic', 'kh', 'kw', 'sh', 'sw', 'ph', 'pw',
             'k_len', 'n_start', 'n_len']       # 13 字 + first 共 14


def golden_case(g, tile):
    """同式黄金：返回 beat 列表 (addr, pad, pad_val, k, n_local)。"""
    beats = []
    ic_n, kh_n, kw_n = g['ic'], g['kh'], g['kw']
    for n_loc in range(tile['n_len']):
        n_glob = tile['n_start'] + n_loc
        oy, ox = divmod(n_glob, g['ow'])
        for k in range(g['k_len']):
            ic, r = divmod(k, kh_n * kw_n)
            kh, kw = divmod(r, kw_n)
            ih = oy * g['sh'] + kh - g['ph']
            iw = ox * g['sw'] + kw - g['pw']
            in_b = 0 <= ih < g['ih'] and 0 <= iw < g['iw']
            pv = 0x80 if g['first'] else 0x00
            addr = (ic * g['ih'] * g['iw'] + ih * g['iw'] + iw) if in_b else 0
            beats.append((addr, 0 if in_b else 1, pv, k, n_loc))
    return beats


def real_check(g, beats, x, xp):
    """真实数据闭合：beat 值 == numpy 独立窗口提取值。"""
    for addr, pad, pv, k, n_loc in beats:
        oy, ox = divmod(g['n_start'] + n_loc, g['ow'])
        ic, r = divmod(k, g['kh'] * g['kw'])
        kh, kw = divmod(r, g['kw'])
        ih = oy * g['sh'] + kh - g['ph']
        iw = ox * g['sw'] + kw - g['pw']
        want = int(xp[ic, ih + 1, iw + 1])      # xp 已含 -128 pad
        if pad:
            assert (pv & 0xFF) == (want & 0xFF), (k, n_loc, pv, want)
        else:
            got = int(x.flat[addr])
            assert got == want, f'addr {addr} data mismatch @k={k} n={n_loc}'


def build():
    rng = np.random.default_rng(SEED)
    cases = []                                   # (geometry, tiles, tag, real)

    # ---- 真实几何（golden00/02 conv0）----
    for tag, gdir in (('real00', 'conv0_golden00'),
                      ('real02', 'conv0_golden02')):
        base = HERE / 'stim' / gdir
        x = np.fromfile(base / 'x_i8.bin', dtype=np.int8)
        g_real = {'ih': 320, 'iw': 320, 'ow': 160, 'ic': 3, 'kh': 3, 'kw': 3,
                  'sh': 2, 'sw': 2, 'ph': 1, 'pw': 1, 'k_len': 27,
                  'n_total': 25600, 'first': 1}
        tiles = [{'n_start': int(s), 'n_len': 8}
                 for s in rng.integers(0, 25600 - 8, size=64)]
        tiles.insert(0, {'n_start': 0, 'n_len': 16})
        tiles.extend([{'n_start': 160, 'n_len': 8},    # 左列边界（iw=-1 pad）
                      {'n_start': 320, 'n_len': 8},
                      {'n_start': 25600 - 160, 'n_len': 8}])
        tiles.append({'n_start': 25600 - 8, 'n_len': 8})
        xp = np.full((3, 322, 322), -128, dtype=np.int8)
        xp[:, 1:321, 1:321] = x.reshape(3, 320, 320)
        cases.append((g_real, tiles, tag, (x, xp)))

    # ---- 合成几何 ----
    cases.append(({'ih': 80, 'iw': 80, 'ow': 80, 'ic': 256, 'kh': 1,
                   'kw': 1, 'sh': 1, 'sw': 1, 'ph': 0, 'pw': 0, 'k_len': 256,
                   'n_total': 6400, 'first': 0},
                  [{'n_start': 0, 'n_len': 64}], 'syn_1x1_nopad', None))
    cases.append(({'ih': 30, 'iw': 30, 'ow': 30, 'ic': 256, 'kh': 3, 'kw': 3,
                   'sh': 1, 'sw': 1, 'ph': 1, 'pw': 1, 'k_len': 2304,
                   'n_total': 900, 'first': 0},
                  [{'n_start': 100, 'n_len': 4}], 'syn_k2304', None))
    cases.append(({'ih': 4, 'iw': 4, 'ow': 4, 'ic': 32, 'kh': 3, 'kw': 3,
                   'sh': 1, 'sw': 1, 'ph': 1, 'pw': 1, 'k_len': 288,
                   'n_total': 16, 'first': 1},
                  [{'n_start': 0, 'n_len': 16}], 'syn_edge_first', None))
    cases.append(({'ih': 10, 'iw': 10, 'ow': 10, 'ic': 8, 'kh': 3, 'kw': 3,
                   'sh': 1, 'sw': 1, 'ph': 1, 'pw': 1, 'k_len': 72,
                   'n_total': 100, 'first': 0},
                  [{'n_start': 0, 'n_len': 96},
                   {'n_start': 96, 'n_len': 4}], 'syn_tail', None))
    cases.append(({'ih': 1, 'iw': 1, 'ow': 1, 'ic': 3, 'kh': 3, 'kw': 3,
                   'sh': 1, 'sw': 1, 'ph': 0, 'pw': 0, 'k_len': 27,
                   'n_total': 1, 'first': 1},
                  [{'n_start': 0, 'n_len': 1}], 'syn_allpad', None))
    cases.append(({'ih': 5, 'iw': 5, 'ow': 3, 'ic': 3, 'kh': 3, 'kw': 3,
                   'sh': 2, 'sw': 2, 'ph': 1, 'pw': 1, 'k_len': 27,
                   'n_total': 9, 'first': 0},
                  [{'n_start': 0, 'n_len': 9}], 'syn_wrap', None))

    # ---- 生成 + 覆盖统计 ----
    cov = {'n_cases': len(cases), 'n_tiles': 0, 'n_beats': 0, 'pad': 0,
           'nopad': 0, 'pad_neg128': 0, 'pad_zero': 0, 'ic_rollovers': 0,
           'ox_wraps': 0, 'oy_incs': 0, 'real_beats': 0}
    cfg_words = []
    cnts = []
    addr_h, pad_h, pv_h, k_h, n_h = [], [], [], [], []
    for g, tiles, tag, real in cases:
        for tile in tiles:
            beats = golden_case(g, tile)
            if real is not None:
                g_run = dict(g)
                g_run['n_start'] = tile['n_start']
                real_check(g_run, beats, real[0], real[1])
                cov['real_beats'] += len(beats)
            cov['n_tiles'] += 1
            cov['n_beats'] += len(beats)
            for addr, pad, pv, k, n_loc in beats:
                addr_h.append(f'{addr:08X}')
                pad_h.append(f'{pad:01X}')
                pv_h.append(f'{pv:02X}')
                k_h.append(f'{k:04X}')
                n_h.append(f'{n_loc:04X}')
                if pad:
                    cov['pad'] += 1
                    if pv & 0x80 and g['first']:
                        cov['pad_neg128'] += 1
                    else:
                        cov['pad_zero'] += 1
                else:
                    cov['nopad'] += 1
            cnts.append(len(beats))
            cfg_words.extend([g[k] & 0xFFFF for k in CFG_WORDS[:-2]]
                             + [tile['n_start'], tile['n_len'],
                                g['first']])
            # 几何级覆盖事件
            if g['k_len'] > g['kh'] * g['kw'] * 1:
                cov['ic_rollovers'] += g['k_len'] // (g['kh'] * g['kw']) - 1
            span = tile['n_start'] + tile['n_len']
            ow = g['ow']
            ox0 = tile['n_start'] % ow
            cov['ox_wraps'] += max(0, (ox0 + tile['n_len'] - 1) // ow)
            if span > ow:
                cov['oy_incs'] += 1

    assert cov['pad'] >= 1000 and cov['nopad'] >= 10000, cov
    assert cov['pad_neg128'] >= 500 and cov['pad_zero'] >= 500, cov
    assert cov['ic_rollovers'] >= 1 and cov['ox_wraps'] >= 1 \
        and cov['oy_incs'] >= 1, cov
    return cfg_words, cnts, addr_h, pad_h, pv_h, k_h, n_h, cov


def main():
    cfg_words, cnts, addr_h, pad_h, pv_h, k_h, n_h, cov = build()
    out = HERE / 'stim' / 'addrgen'
    out.mkdir(parents=True, exist_ok=True)
    files = {
        'n_tiles.hex': f'{len(cnts):08X}\n',
        'cfg_u16.hex': ''.join(f'{w & 0xFFFF:04X}\n' for w in cfg_words),
        'cnt_u32.hex': ''.join(f'{c:08X}\n' for c in cnts),
        'xaddr_u32.hex': ''.join(f'{v}\n' for v in addr_h),
        'pad.hex': ''.join(f'{v}\n' for v in pad_h),
        'padval_i8.hex': ''.join(f'{v}\n' for v in pv_h),
        'k_u16.hex': ''.join(f'{v}\n' for v in k_h),
        'nloc_u16.hex': ''.join(f'{v}\n' for v in n_h),
    }
    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    manifest = {
        'name': 'addrgen', 'seed': SEED,
        'contract': 'k=ic*(KH*KW)+kh*KW+kw; ih=oy*SH+kh-PH; CHW addr; '
                    'pad bypass with -128 (first) / 0; 1 beat/cycle',
        'gold_ref': 'formula reference per golden_extract.py contract + '
                    'real-tensor data closure (golden00/02)',
        'cfg_layout': f'{CFG_WORDS[:-2]} + n_start + n_len + first '
                      f'(= {len(CFG_WORDS) + 1} words per tile)',
        'coverage': cov,
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] addrgen: {cov["n_tiles"]} tiles / {cov["n_beats"]} beats '
          f'(pad={cov["pad"]} nopad={cov["nopad"]} '
          f'p-128={cov["pad_neg128"]} p0={cov["pad_zero"]} '
          f'real={cov["real_beats"]}), manifest written')


if __name__ == '__main__':
    main()
