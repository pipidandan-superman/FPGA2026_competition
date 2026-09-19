"""M3 wbuf 激励生成器 + 黄金（BFM 风格参考模型）。

合同（rtl/yolo_wbuf.v）：N_ROWS=16 行 × K 深字节存储器 × 双 bank；
写口 1 拍 1 字节（wr_sel: 0=data / 1=bias / 2=m / 3=shift）；读口
ren/raddr → 1 拍延迟广播 16 行字节（dout）；参数口 pren/(row,sel) →
1 拍延迟 32b；en=0 保持；双缓冲：写 wr_bank 与读 rd_bank 可同时激活，
互不干扰。

轮次结构（r0 真实 + r1..r7 合成，bank = r%2）：
  r0：真实 golden00 W tile（16×27 字节 + 真实 bias/m/shift）写入 bank0
      → 全量读校验 + 参数扫（真实数据回归）；
  r≥1：参数装载 → **交错相**（向 bank r%2 写 tile_r 的同时从另一 bank
      逐拍读校验 tile_{r−1}，写读相邻拍并发——双缓冲隔离证据）→
      切换 → tile_r 全量读校验 + 参数扫 + 保持拍。
K 档：{27, 576, 64, 2304, 2304, 256, 48}——两 bank 各一次全深度 2304。
覆盖断言：数据读 ≥5000、参数读每字段 ≥100、写读相邻交错 ≥200、
  保持拍 ≥16、两 bank 均有 2304 全深度校验。
"""
import hashlib
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SEED = 303
N_ROWS = 16
K_DEEPS = [27, 576, 64, 2304, 2304, 256, 48]   # r1..r7

OP_IDLE, OP_WD, OP_WPB, OP_WPM, OP_WPS, OP_RD, OP_RP, OP_WRRD = range(8)
SEL_DATA, SEL_BIAS, SEL_M, SEL_SHIFT = 0, 1, 2, 3


class Model:
    """参考模型：双 bank tile + 输出影子（保持语义）。

    数据与参数必须分字典——RTL 中二者是独立存储体；若共用
    (row, ·) 键空间，参数写会覆盖 k=1/2/3 处的数据字节并使
    rd() 拼出 >128b 的黄金值（run1 实测 144/151 位）。
    """

    def __init__(self):
        self.banks = [dict(), dict()]   # 数据：(row, k) -> 字节
        self.pars = [dict(), dict()]    # 参数：(row, sel) -> u32
        self.dout = 0          # 128b 影子（16 字节）
        self.pdata = 0

    def wdata(self, bank, row, k, byte):
        self.banks[bank][(row, k)] = byte & 0xFF

    def wpar(self, bank, row, sel, val):
        self.pars[bank][(row, sel)] = val & 0xFFFFFFFF

    def rd(self, bank, k):
        v = 0
        for r in range(N_ROWS):
            v |= self.banks[bank].get((r, k), 0) << (8 * r)
        self.dout = v
        return v

    def rp(self, bank, row, sel):
        self.pdata = self.pars[bank].get((row, sel), 0)
        return self.pdata


def build():
    rng = np.random.default_rng(SEED)
    m = Model()
    ops = []   # (op, bank, row, k, sel, wdata, exp_dout, exp_vld, exp_pdata, exp_pvld)

    def emit(op, bank=0, row=0, k=0, sel=0, wdata=0,
             chk_d=False, chk_p=False, rbank=None, rk=None):
        rb = bank if rbank is None else rbank
        kk = k if rk is None else rk
        ops.append({'op': op, 'bank': bank, 'row': row, 'k': k,
                    'sel': sel, 'wdata': wdata & 0xFFFFFFFF,
                    'rbank': rb, 'rk': kk,
                    'ed': m.dout if not chk_d else m.rd(rb, kk),
                    'ev': 1 if chk_d else 0,
                    'ep': m.pdata if not chk_p else m.rp(bank, row, sel),
                    'epv': 1 if chk_p else 0})

    # ---- r0：真实 golden00 W tile（bank0）----
    base = HERE / 'stim' / 'conv0_golden00'
    w = np.fromfile(base / 'w_i8.bin', dtype=np.int8).reshape(16, 27)
    bias = np.fromfile(base / 'bias_eff_i32.bin', dtype=np.int32)
    marr = np.fromfile(base / 'm_i32.bin', dtype=np.int32)
    sarr = np.fromfile(base / 'shift_u8.bin', dtype=np.uint8)
    for row in range(N_ROWS):
        for k in range(27):
            emit(OP_WD, 0, row, k, SEL_DATA, int(w[row, k]))
            m.wdata(0, row, k, int(w[row, k]))
    for row in range(N_ROWS):
        for sel, val in ((SEL_BIAS, int(bias[row])), (SEL_M, int(marr[row])),
                         (SEL_SHIFT, int(sarr[row]))):
            emit([OP_WPB, OP_WPM, OP_WPS][sel - 1], 0, row, 0, sel, val)
            m.wpar(0, row, sel, val)
    for k in range(27):                        # 全量读校验
        emit(OP_RD, 0, 0, k, 0, 0, chk_d=True)
    emit(OP_IDLE)                              # 保持拍
    for row in range(N_ROWS):
        for sel in (SEL_BIAS, SEL_M, SEL_SHIFT):
            emit(OP_RP, 0, row, 0, sel, 0, chk_p=True)
    emit(OP_IDLE)

    # ---- r1..r7：合成轮，交错双缓冲 ----
    prev = {'bank': 0, 'klen': 27}             # r0 在 bank0
    for ri, klen in enumerate(K_DEEPS, start=1):
        bank = ri % 2
        tile = rng.integers(-128, 128, size=(N_ROWS, klen))
        pars = {'bias': rng.integers(-2**31, 2**31, size=N_ROWS,
                                     dtype=np.int64),
                'm': rng.integers(-(2**31 - 1), 2**31, size=N_ROWS,
                                  dtype=np.int64),
                'shift': rng.integers(0, 63, size=N_ROWS)}
        # 参数装载（写 bank）
        for row in range(N_ROWS):
            for sel, val in ((SEL_BIAS, int(pars['bias'][row])),
                             (SEL_M, int(pars['m'][row])),
                             (SEL_SHIFT, int(pars['shift'][row]))):
                emit([OP_WPB, OP_WPM, OP_WPS][sel - 1], bank, row, 0, sel,
                     val)
                m.wpar(bank, row, sel, val)
        # 交错相：16 写 + 1 读循环（写 tile_r 到 bank，读 tile_{r-1}）；
        # 每 4 拍写中 1 拍与读**同周期**并发（写 A 读 B 同拍，隔离证据）；
        # 读侧深度 = 前轮 klen（未写地址 RTL 为 x，黄金定义为 0——
        # 激励不得读越界）
        wi = 0
        rk = 0
        total_w = N_ROWS * klen
        rd_len = prev['klen']
        while wi < total_w or rk < rd_len:
            for _ in range(16):
                if wi < total_w:
                    row, k = divmod(wi, klen)
                    if wi % 4 == 3 and rk < rd_len:
                        emit(OP_WRRD, bank, row, k, SEL_DATA,
                             int(tile[row, k]), rbank=1 - bank, rk=rk,
                             chk_d=True)
                        m.wdata(bank, row, k, int(tile[row, k]))
                        wi += 1
                        rk += 1
                    else:
                        emit(OP_WD, bank, row, k, SEL_DATA,
                             int(tile[row, k]))
                        m.wdata(bank, row, k, int(tile[row, k]))
                        wi += 1
            if rk < rd_len:
                emit(OP_RD, 1 - bank, 0, rk, 0, 0, chk_d=True)
                rk += 1
        emit(OP_IDLE)
        # 切换后 tile_r 全量校验
        for k in range(klen):
            emit(OP_RD, bank, 0, k, 0, 0, chk_d=True)
        emit(OP_IDLE)
        for row in range(N_ROWS):
            for sel in (SEL_BIAS, SEL_M, SEL_SHIFT):
                emit(OP_RP, bank, row, 0, sel, 0, chk_p=True)
        emit(OP_IDLE)
        prev = {'bank': bank, 'klen': klen}

    # ---- 覆盖统计与断言 ----
    assert all(0 <= o['ed'] < 2**128 for o in ops), 'golden dout >128b'
    n_rd = sum(1 for o in ops if o['op'] == OP_RD)
    n_rp = {s: sum(1 for o in ops if o['op'] == OP_RP and o['sel'] == s)
            for s in (SEL_BIAS, SEL_M, SEL_SHIFT)}
    n_ilv = 0
    n_ilv_same = 0
    for a, b in zip(ops, ops[1:]):
        if a['op'] == OP_WD and b['op'] == OP_RD:
            n_ilv += 1
    n_ilv_same = sum(1 for o in ops if o['op'] == OP_WRRD)
    n_idle = sum(1 for o in ops if o['op'] == OP_IDLE)
    depth_ok = {0: False, 1: False}
    for ri, klen in enumerate(K_DEEPS, start=1):
        if klen == 2304:
            depth_ok[ri % 2] = True
    cov = {'total_ops': len(ops), 'n_read_data': n_rd, 'n_read_par': n_rp,
           'interleave_write_read_adjacent': n_ilv,
           'same_cycle_wr_rd': n_ilv_same,
           'idle_hold': n_idle,
           'depth2304_verified_bank': depth_ok,
           'real_round': 'golden00 w/bias/m/shift (16x27)'}
    assert n_rd >= 5000, cov
    assert all(v >= 100 for v in n_rp.values()), cov
    assert n_ilv + n_ilv_same >= 200 and n_idle >= 16, cov
    assert n_ilv_same >= 200, cov
    assert all(depth_ok.values()), cov
    return ops, cov


def main():
    ops, cov = build()
    out = HERE / 'stim' / 'wbuf'
    out.mkdir(parents=True, exist_ok=True)
    files = {
        'n_ops.hex': f'{len(ops):08X}\n',
        'op.hex': ''.join(f'{o["op"]:01X}\n' for o in ops),
        'bank.hex': ''.join(f'{o["bank"]:01X}\n' for o in ops),
        'row_u8.hex': ''.join(f'{o["row"]:02X}\n' for o in ops),
        'kaddr_u16.hex': ''.join(f'{o["k"]:04X}\n' for o in ops),
        'sel.hex': ''.join(f'{o["sel"]:01X}\n' for o in ops),
        'wdata_i32.hex': ''.join(f'{o["wdata"]:08X}\n' for o in ops),
        'rbank.hex': ''.join(f'{o["rbank"]:01X}\n' for o in ops),
        'rkaddr_u16.hex': ''.join(f'{o["rk"]:04X}\n' for o in ops),
        'edout_i128.hex': ''.join(f'{o["ed"]:032X}\n' for o in ops),
        'evld.hex': ''.join(f'{o["ev"]:01X}\n' for o in ops),
        'epdata_i32.hex': ''.join(f'{o["ep"]:08X}\n' for o in ops),
        'epvld.hex': ''.join(f'{o["epv"]:01X}\n' for o in ops),
    }
    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    manifest = {
        'name': 'wbuf', 'seed': SEED,
        'contract': 'dual-bank row store; 1-cycle sync read broadcast; '
                    'params (bias/m/shift) loaded with tile; concurrent '
                    'wr/rd on opposite banks; en=0 hold',
        'gold_ref': 'python BFM model (dict-based banks + output shadow)',
        'coverage': cov,
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] wbuf: {cov["total_ops"]} ops '
          f'(rd={cov["n_read_data"]} par={sum(cov["n_read_par"].values())} '
          f'ilv={cov["interleave_write_read_adjacent"]} '
          f'same-cyc={cov["same_cycle_wr_rd"]} '
          f'hold={cov["idle_hold"]}), manifest written')


if __name__ == '__main__':
    main()
