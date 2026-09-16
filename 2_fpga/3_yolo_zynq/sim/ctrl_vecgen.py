"""M8 ctrl 激励生成器 + 黄金（指令级参考模型）。

合同（rtl/yolo_ctrl.v V1.1，基线 §3.1）：层描述符流（oc_total/n_total/
k_total/last）→ tile 三层循环 n 外 × oc 内，每 tile：
  S_TILE（acc_clr 电平 ≥1 拍——V1.1 起等待 tile_rdy_i，本生成器每
  tile 随机注入 0..4 拍等待，等待拍 acc_clr 拉长）→ S_K（K 拍，k_cnt
  0..K−1，末拍后计数器保持 K）→ S_RQ（oc_tail×n_tail 拍，rq_idx 平铺
  oc 慢 n 快）→ 下一 tile（尾部钳位 tail_calc，rd_bank 翻转——跨层
  连续，首 tile 读 bank0）→ 层末 S_LDONE（layer_done 脉冲；last 层
  同时 all_done）→ S_IDLE（dsc_ready）。输出 = 寄存器状态组合直出。
  tile_rdy 逐拍驱动值由黄金模型决定并记录（drv_rdy.hex），TB 回放
  同一序列 → DUT 与黄金消费一致。

层计划（23 层）：
  L0  real conv0 形状（oc16/n25600/k27——真实几何回归 + N 档 25600）；
  L1..L15  15 档 K（27..2304）× n=100（N 档 100 + 尾 tile 4）；
  L16..L18 N 档 400/1600/6400；
  L19 oc=24（OC 尾 8）；L20 单 tile 层；L21 极小层（oc1/n1/k1）；
  L22 last 层（all_done）。层间混合 0 拍（背靠背）与随机间隔切换。

黄金 = python 逐拍寄存器影子（与 RTL case 一一对应，含 V1.1 等待），
逐周期比对 15 路输出。覆盖断言：15 K 档全集、5 N 档全集、n/oc 尾
事件、单 tile、all_done 恰 1 次、背靠背与间隔层切换均有、等待拍
总量充分且 0 等待/长等待 tile 均存在。
"""
import hashlib
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SEED = 808
OC_EDGE = 16
N_EDGE = 16
K_TIERS = [27, 32, 48, 64, 96, 128, 144, 192, 256, 288, 384, 512,
           576, 1152, 2304]
N_TIERS = [100, 400, 1600, 6400, 25600]


def tail_calc(total, tiles, idx, edge):
    """尾 tile 宽（与 RTL 函数同式）。"""
    if idx == tiles - 1:
        return total - (tiles - 1) * edge
    return edge


def build():
    rng = np.random.default_rng(SEED)
    layers = ([dict(oc=16, n=25600, k=27, last=0, tag='real_conv0')]
              + [dict(oc=16, n=100, k=kt, last=0, tag=f'k{kt}')
                 for kt in K_TIERS]
              + [dict(oc=16, n=400, k=27, last=0, tag='n400'),
                 dict(oc=16, n=1600, k=27, last=0, tag='n1600'),
                 dict(oc=16, n=6400, k=27, last=0, tag='n6400'),
                 dict(oc=24, n=100, k=32, last=0, tag='oc_tail8'),
                 dict(oc=16, n=16, k=27, last=0, tag='single_tile'),
                 dict(oc=1, n=1, k=1, last=0, tag='tiny'),
                 dict(oc=16, n=400, k=576, last=1, tag='final_last')])
    # 层间隔：第一处层切换强制背靠背（0 拍），其余随机 0..4 拍
    gaps = [int(rng.integers(0, 5)) for _ in range(len(layers))]
    gaps[1] = 0
    assert any(g > 0 for g in gaps[2:]), 'need at least one gapped switch'

    # ---- 指令级参考模型：寄存器影子，逐周期发射 ----
    # V1.1：进 TILE 态时抽等待拍数 w∈{0..4}；TILE 态逐拍消费——w>0 拍
    # rdy=0（拉长 acc_clr 电平），随后 rdy=1 放行进 K。rdy 驱动值逐拍
    # 记录进 cyc（TB 按 drv_rdy.hex 回放同一序列）。
    # V1.3：K 末拍后经 DRAIN 态 3 拍（drain 0→1→2，第三拍末转 RQ）
    # 再进 RQ——镜像 RTL S_DRAIN（pe_pack V1.2 三级流水排空）。
    # DRAIN 拍所有输出为 0（busy=1，k_cnt 保持 K）。
    r = dict(state='IDLE', oc_tot=0, n_tot=0, k_tot=0, last=0,
             oc_tiles=0, n_tiles=0, oc_tile=0, n_tile=0,
             oc_tail=0, n_tail=0, k=0, rq=0, rdb=0, wait=0, rdy=1,
             drain=0)
    cyc = []
    wait_cyc = [0]                      # 等待拍累计（闭包可变计数）
    drain_cyc = [0]                     # V1.3 DRAIN 拍累计
    waits = []                          # 每 tile 等待拍数（覆盖统计用）

    def emit(valid, oc, n, k, last):
        """后沿语义：先按本拍输入走一次时钟，再发射新状态（采样点
        = 消耗本拍输入的时钟沿之后，与 wbuf/xbuf 1 拍延迟读同惯例）。
        rdy 消费值在 step 内决定，随本拍记录回放。"""
        step(valid, oc, n, k, last)
        cyc.append(dict(valid=valid, d_oc=oc, d_n=n, d_k=k, d_last=last,
                        rdy=r['rdy'],
                        ready=int(r['state'] == 'IDLE'),
                        busy=int(r['state'] != 'IDLE'),
                        accclr=int(r['state'] == 'TILE'),
                        beaten=int(r['state'] == 'K'),
                        k_cnt=r['k'],
                        rqen=int(r['state'] == 'RQ'),
                        rq_idx=r['rq'],
                        wrbank=1 - r['rdb'], rdbank=r['rdb'],
                        oc_tile=r['oc_tile'], n_tile=r['n_tile'],
                        n_tail=r['n_tail'], oc_tail=r['oc_tail'],
                        ldone=int(r['state'] == 'LDONE'),
                        alldone=int(r['state'] == 'LDONE') and r['last']))

    def step(valid, oc, n, k, last):
        s = r['state']
        r['rdy'] = 1                     # 非 TILE 拍 rdy 无关，驱动 1
        if s == 'IDLE':
            if valid:
                oc_tiles = (oc + OC_EDGE - 1) // OC_EDGE
                n_tiles = (n + N_EDGE - 1) // N_EDGE
                r.update(state='TILE', oc_tot=oc, n_tot=n, k_tot=k,
                         last=last, oc_tiles=oc_tiles, n_tiles=n_tiles,
                         oc_tile=0, n_tile=0,
                         oc_tail=tail_calc(oc, oc_tiles, 0, OC_EDGE),
                         n_tail=tail_calc(n, n_tiles, 0, N_EDGE),
                         k=0, rq=0)
                r['wait'] = int(rng.integers(0, 5))
                waits.append(r['wait'])
        elif s == 'TILE':
            if r['wait'] > 0:            # V1.1 等待拍：rdy=0
                r['wait'] -= 1
                r['rdy'] = 0
                wait_cyc[0] += 1
            else:
                r['state'] = 'K'
        elif s == 'K':
            k_last = (r['k'] == r['k_tot'] - 1)
            r['k'] = r['k'] + 1        # 末拍后保持 K
            if k_last:
                r.update(state='DRAIN', rq=0, drain=0)
        elif s == 'DRAIN':
            # V1.3：3 拍排空（RTL drain_cnt_r 0→1→2，=2 的拍末转 RQ）
            drain_cyc[0] += 1
            if r['drain'] >= 2:
                r.update(state='RQ', rq=0, drain=0)
            else:
                r['drain'] += 1
        elif s == 'RQ':
            if r['rq'] == r['oc_tail'] * r['n_tail'] - 1:
                last_oc = r['oc_tile'] == r['oc_tiles'] - 1
                last_n = r['n_tile'] == r['n_tiles'] - 1
                if last_oc and last_n:
                    r.update(state='LDONE', rq=0, k=0)
                else:
                    n_oc = 0 if last_oc else r['oc_tile'] + 1
                    n_n = r['n_tile'] + 1 if last_oc else r['n_tile']
                    r.update(state='TILE', rq=0, k=0,
                             oc_tile=n_oc, n_tile=n_n,
                             oc_tail=tail_calc(r['oc_tot'], r['oc_tiles'],
                                               n_oc, OC_EDGE),
                             n_tail=tail_calc(r['n_tot'], r['n_tiles'],
                                              n_n, N_EDGE),
                             rdb=1 - r['rdb'])
                    r['wait'] = int(rng.integers(0, 5))
                    waits.append(r['wait'])
            else:
                r['rq'] += 1
        elif s == 'LDONE':
            r['state'] = 'IDLE'

    for L, gap in zip(layers, gaps):
        for _ in range(gap):
            emit(0, 0, 0, 0, 0)         # 间隔拍：valid=0，字段无效
        emit(1, L['oc'], L['n'], L['k'], L['last'])
        while r['state'] != 'IDLE':     # 层运行期逐拍推进直到完成
            emit(0, 0, 0, 0, 0)
    for _ in range(8):                   # 尾部 idle 拍
        emit(0, 0, 0, 0, 0)

    # ---- 覆盖统计与断言 ----
    k_used = {L['k'] for L in layers}
    n_used = {L['n'] for L in layers}
    assert set(K_TIERS).issubset(k_used), k_used
    assert set(N_TIERS).issubset(n_used), n_used
    assert any(c['n_tail'] < N_EDGE and c['ldone'] or
               c['n_tail'] < N_EDGE for c in cyc)
    n_tail_ev = sum(1 for c in cyc if c['rqen'] and c['n_tail'] < N_EDGE)
    oc_tail_ev = sum(1 for c in cyc if c['rqen'] and c['oc_tail'] < OC_EDGE)
    n_accclr = sum(1 for c in cyc if c['accclr'])
    n_beats = sum(1 for c in cyc if c['beaten'])
    n_rq = sum(1 for c in cyc if c['rqen'])
    n_ldone = sum(1 for c in cyc if c['ldone'])
    n_alldone = sum(1 for c in cyc if c['alldone'])
    tiles_ref = sum((L['oc'] + 15) // 16 * (L['n'] + 15) // 16
                    for L in layers)
    bank_toggles = sum(1 for a, b in zip(cyc, cyc[1:])
                       if b['rdbank'] != a['rdbank'])
    assert n_tail_ev >= 100 and oc_tail_ev >= 50, (n_tail_ev, oc_tail_ev)
    # acc_clr 是 TILE 态电平：每 tile 1 拍 + 等待拍
    assert n_accclr == tiles_ref + wait_cyc[0], (n_accclr, tiles_ref,
                                                 wait_cyc[0])
    assert n_ldone == len(layers) and n_alldone == 1
    assert any(L['n'] == 16 and L['oc'] == 16 for L in layers)  # 单 tile
    assert bank_toggles == tiles_ref - len(layers)  # 每 tile 推进翻转一次
    # V1.1 等待覆盖：总量充分、0 等待 tile 与长等待 tile 均存在
    assert wait_cyc[0] >= 1000, wait_cyc[0]
    assert any(w == 0 for w in waits) and any(w >= 3 for w in waits)
    # V1.3：每 tile 恰 3 拍 DRAIN
    assert drain_cyc[0] == 3 * tiles_ref, (drain_cyc[0], tiles_ref)
    cov = {'total_cycles': len(cyc), 'layers': len(layers),
           'tiles': tiles_ref, 'acc_clr_cycles': n_accclr,
           'tile_wait_cycles': wait_cyc[0], 'drain_cycles': drain_cyc[0],
           'k_beats': n_beats, 'rq_beats': n_rq,
           'layer_done_pulses': n_ldone, 'all_done_pulses': n_alldone,
           'n_tail_events': n_tail_ev, 'oc_tail_events': oc_tail_ev,
           'bank_toggles': bank_toggles,
           'k_tiers_all15': sorted(k_used) == sorted(K_TIERS),
           'n_tiers_all5': set(N_TIERS).issubset(n_used)}
    return cyc, cov


def main():
    cyc, cov = build()
    out = HERE / 'stim' / 'ctrl'
    out.mkdir(parents=True, exist_ok=True)
    files = {
        'n_cycles.hex': f'{len(cyc):08X}\n',
        'drv_valid.hex': ''.join(f'{c["valid"]:01X}\n' for c in cyc),
        'drv_oc.hex': ''.join(f'{c["d_oc"]:03X}\n' for c in cyc),
        'drv_n.hex': ''.join(f'{c["d_n"]:04X}\n' for c in cyc),
        'drv_k.hex': ''.join(f'{c["d_k"]:04X}\n' for c in cyc),
        'drv_last.hex': ''.join(f'{c["d_last"]:01X}\n' for c in cyc),
        'drv_rdy.hex': ''.join(f'{c["rdy"]:01X}\n' for c in cyc),
        'e_ready.hex': ''.join(f'{c["ready"]:01X}\n' for c in cyc),
        'e_busy.hex': ''.join(f'{c["busy"]:01X}\n' for c in cyc),
        'e_accclr.hex': ''.join(f'{c["accclr"]:01X}\n' for c in cyc),
        'e_beaten.hex': ''.join(f'{c["beaten"]:01X}\n' for c in cyc),
        'e_k.hex': ''.join(f'{c["k_cnt"]:04X}\n' for c in cyc),
        'e_rqen.hex': ''.join(f'{c["rqen"]:01X}\n' for c in cyc),
        'e_rqidx.hex': ''.join(f'{c["rq_idx"]:03X}\n' for c in cyc),
        'e_wrbank.hex': ''.join(f'{c["wrbank"]:01X}\n' for c in cyc),
        'e_rdbank.hex': ''.join(f'{c["rdbank"]:01X}\n' for c in cyc),
        'e_octile.hex': ''.join(f'{c["oc_tile"]:03X}\n' for c in cyc),
        'e_ntile.hex': ''.join(f'{c["n_tile"]:03X}\n' for c in cyc),
        'e_ntail.hex': ''.join(f'{c["n_tail"]:03X}\n' for c in cyc),
        'e_octail.hex': ''.join(f'{c["oc_tail"]:03X}\n' for c in cyc),
        'e_ldone.hex': ''.join(f'{c["ldone"]:01X}\n' for c in cyc),
        'e_alldone.hex': ''.join(f'{c["alldone"]:01X}\n' for c in cyc),
    }
    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    manifest = {
        'name': 'ctrl', 'seed': SEED,
        'contract': 'descriptor stream -> tile loop (n outer, oc inner) '
                    'with tail clamp, per-tile bank toggle, layer_done/'
                    'all_done pulses, dsc_ready in IDLE; V1.1 S_TILE '
                    'waits tile_rdy_i (per-tile random 0..4 wait cycles, '
                    'rdy replayed from drv_rdy.hex); V1.3 S_K -> 3-cycle '
                    'S_DRAIN -> S_RQ (pe_pack V1.2 three-stage pipeline '
                    'drain, UG479)',
        'gold_ref': 'instruction-level cycle-accurate register shadow '
                    '(python)',
        'layer_plan': ['real conv0 shape oc16/n25600/k27']
                      + [f'k tier {k} @ n=100' for k in K_TIERS]
                      + ['n400', 'n1600', 'n6400', 'oc_tail8(oc=24)',
                         'single_tile', 'tiny(1/1/1)', 'final_last'],
        'coverage': cov,
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] ctrl: {cov["total_cycles"]} cycles '
          f'(layers={cov["layers"]} tiles={cov["tiles"]} '
          f'k_beats={cov["k_beats"]} rq_beats={cov["rq_beats"]} '
          f'bank_toggles={cov["bank_toggles"]} '
          f'tile_wait_cycles={cov["tile_wait_cycles"]} '
          f'drain_cycles={cov["drain_cycles"]}), manifest written')


if __name__ == '__main__':
    main()
