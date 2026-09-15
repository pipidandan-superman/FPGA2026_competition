"""M4 xbuf 激励生成器 + 黄金（BFM 风格参考模型）。

合同（rtl/yolo_xbuf.v）：N_COLS=16 列 × K 深字节存储器 × 双 bank（列组
织，与 wbuf 行组织对称）；写口 1 拍 1 字节（wcol/waddr/wdata）；读口
ren/raddr → 1 拍延迟广播 16 列字节（dout）；en=0 保持；无参数随载；
双缓冲：写 wr_bank 与读 rd_bank 可同时激活，互不干扰。

轮次结构（r0 真实 + r1..r7 合成，bank = r%2）：
  r0：真实 golden00 im2col X tile（conv0 几何 3x3/S2/P1，n_start=0 即
      ox=0 左缘 tile，pad−128 富集；16 列 × 27 字节）写入 bank0 → 全量
      读校验（真实数据回归，逐字节与 numpy 独立窗口提取闭合）；
  r≥1：**交错相**（向 bank r%2 写 tile_r 的同时从另一 bank 逐拍读校验
      tile_{r−1}，每 4 拍写中 1 拍与读同周期并发——双缓冲隔离证据）
      → 切换 → tile_r 全量读校验 + 保持拍。
K 档 {576, 64, 2304, 2304, 256, 48}——两 bank 各一次全深度 2304。

M3 教训固化：黄金值生成期断言 <2^128；交错相读侧深度钳位到**前轮**
klen（未写地址 RTL 为 x、黄金定义为 0，激励不得读越界）。
"""
import hashlib
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SEED = 404
N_COLS = 16
K_DEEPS = [27, 576, 64, 2304, 2304, 256, 48]   # r1..r7

OP_IDLE, OP_WD, OP_RD, OP_WRRD = range(4)

# conv0 真实几何（golden_extract.py 合同）
IC, IH, IW = 3, 320, 320
KH, KW, SH, SW, PH, PW = 3, 3, 2, 2, 1, 1
OW = (IW + 2 * PW - KW) // SW + 1          # 160
K_REAL = IC * KH * KW                       # 27
PAD_VAL = -128                              # 首层 z 折叠


def im2col_byte(x, n, k):
    """真实 X tile 单元：列 n（oy,ox）× 行 k（ic,kh,kw）→ 字节。"""
    oy, ox = divmod(n, OW)
    ic = k // (KH * KW)
    kr = k % (KH * KW)
    kh = kr // KW
    kw = kr % KW
    ih = oy * SH + kh - PH
    iw = ox * SW + kw - PW
    if ih < 0 or ih >= IH or iw < 0 or iw >= IW:
        return PAD_VAL & 0xFF
    return int(x[ic, ih, iw]) & 0xFF


class Model:
    """参考模型：双 bank tile + 输出影子（保持语义）。"""

    def __init__(self):
        self.banks = [dict(), dict()]   # (col, k) -> 字节
        self.dout = 0          # 128b 影子（16 字节）

    def wdata(self, bank, col, k, byte):
        self.banks[bank][(col, k)] = byte & 0xFF

    def rd(self, bank, k):
        v = 0
        for c in range(N_COLS):
            v |= self.banks[bank].get((c, k), 0) << (8 * c)
        self.dout = v
        return v


def build():
    rng = np.random.default_rng(SEED)
    m = Model()
    ops = []

    def emit(op, bank=0, col=0, k=0, wdata=0,
             chk_d=False, rbank=None, rk=None):
        rb = bank if rbank is None else rbank
        kk = k if rk is None else rk
        ops.append({'op': op, 'bank': bank, 'col': col, 'k': k,
                    'wdata': wdata & 0xFF,
                    'rbank': rb, 'rk': kk,
                    'ed': m.dout if not chk_d else m.rd(rb, kk),
                    'ev': 1 if chk_d else 0})

    # ---- r0：真实 golden00 im2col X tile（bank0，n_start=0 左缘）----
    base = HERE / 'stim' / 'conv0_golden00'
    x = np.fromfile(base / 'x_i8.bin', dtype=np.int8).reshape(IC, IH, IW)
    n_start, n_len = 0, N_COLS
    for col in range(n_len):
        for k in range(K_REAL):
            b = im2col_byte(x, n_start + col, k)
            emit(OP_WD, 0, col, k, b)
            m.wdata(0, col, k, b)
    emit(OP_IDLE)                              # 保持拍
    for k in range(K_REAL):                    # 全量读校验
        emit(OP_RD, 0, 0, k, 0, chk_d=True)
    emit(OP_IDLE)

    # 独立闭合：pad+切片窗口路径 ≠ 地址算术路径（im2col_byte），
    # 两者逐字节一致才允许真实轮进入操作流
    xp = np.pad(x, ((0, 0), (PH, PH), (PW, PW)),
                constant_values=PAD_VAL).astype(np.int64)
    for col in range(n_len):
        oy, ox = divmod(n_start + col, OW)
        win = xp[:, oy * SH:oy * SH + KH, ox * SW:ox * SW + KW]
        ref = win.reshape(-1)                  # (ic, kh, kw) 序 = k 序
        for k in range(K_REAL):
            assert m.banks[0][(col, k)] == (int(ref[k]) & 0xFF), (col, k)

    # ---- r1..r7：合成轮，交错双缓冲 ----
    prev = {'bank': 0, 'klen': K_REAL}         # r0 在 bank0
    for ri, klen in enumerate(K_DEEPS, start=1):
        bank = ri % 2
        tile = rng.integers(-128, 128, size=(N_COLS, klen))
        # 交错相：16 写 + 1 读循环（写 tile_r 到 bank，读 tile_{r-1}）；
        # 每 4 拍写中 1 拍与读**同周期**并发；读侧深度 = 前轮 klen
        wi = 0
        rk = 0
        total_w = N_COLS * klen
        rd_len = prev['klen']
        while wi < total_w or rk < rd_len:
            for _ in range(16):
                if wi < total_w:
                    col, k = divmod(wi, klen)
                    if wi % 4 == 3 and rk < rd_len:
                        emit(OP_WRRD, bank, col, k, int(tile[col, k]),
                             rbank=1 - bank, rk=rk, chk_d=True)
                        m.wdata(bank, col, k, int(tile[col, k]))
                        wi += 1
                        rk += 1
                    else:
                        emit(OP_WD, bank, col, k, int(tile[col, k]))
                        m.wdata(bank, col, k, int(tile[col, k]))
                        wi += 1
            if rk < rd_len:
                emit(OP_RD, 1 - bank, 0, rk, 0, chk_d=True)
                rk += 1
        emit(OP_IDLE)
        # 切换后 tile_r 全量校验
        for k in range(klen):
            emit(OP_RD, bank, 0, k, 0, chk_d=True)
        emit(OP_IDLE)
        prev = {'bank': bank, 'klen': klen}

    # ---- 覆盖统计与断言 ----
    assert all(0 <= o['ed'] < 2**128 for o in ops), 'golden dout >128b'
    n_rd = sum(1 for o in ops if o['op'] == OP_RD)
    n_ilv = sum(1 for a, b in zip(ops, ops[1:])
                if a['op'] == OP_WD and b['op'] == OP_RD)
    n_ilv_same = sum(1 for o in ops if o['op'] == OP_WRRD)
    n_idle = sum(1 for o in ops if o['op'] == OP_IDLE)
    depth_ok = {0: False, 1: False}
    for ri, klen in enumerate(K_DEEPS, start=1):
        if klen == 2304:
            depth_ok[ri % 2] = True
    cov = {'total_ops': len(ops), 'n_read_data': n_rd,
           'interleave_write_read_adjacent': n_ilv,
           'same_cycle_wr_rd': n_ilv_same,
           'idle_hold': n_idle,
           'depth2304_verified_bank': depth_ok,
           'real_round': 'golden00 im2col X tile 16x27 @n_start=0'}
    assert n_rd >= 5000, cov
    assert n_ilv + n_ilv_same >= 200 and n_idle >= 16, cov
    assert n_ilv_same >= 200, cov
    assert all(depth_ok.values()), cov
    return ops, cov


def main():
    ops, cov = build()
    out = HERE / 'stim' / 'xbuf'
    out.mkdir(parents=True, exist_ok=True)
    files = {
        'n_ops.hex': f'{len(ops):08X}\n',
        'op.hex': ''.join(f'{o["op"]:01X}\n' for o in ops),
        'bank.hex': ''.join(f'{o["bank"]:01X}\n' for o in ops),
        'col_u8.hex': ''.join(f'{o["col"]:02X}\n' for o in ops),
        'kaddr_u16.hex': ''.join(f'{o["k"]:04X}\n' for o in ops),
        'wdata_u8.hex': ''.join(f'{o["wdata"]:02X}\n' for o in ops),
        'rbank.hex': ''.join(f'{o["rbank"]:01X}\n' for o in ops),
        'rkaddr_u16.hex': ''.join(f'{o["rk"]:04X}\n' for o in ops),
        'edout_i128.hex': ''.join(f'{o["ed"]:032X}\n' for o in ops),
        'evld.hex': ''.join(f'{o["ev"]:01X}\n' for o in ops),
    }
    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    manifest = {
        'name': 'xbuf', 'seed': SEED,
        'contract': 'dual-bank column store; 1-cycle sync read broadcast; '
                    'no params with tile; concurrent wr/rd on opposite '
                    'banks; en=0 hold; stimulus never reads unwritten '
                    'addresses',
        'gold_ref': 'python BFM model (dict-based banks + output shadow)',
        'coverage': cov,
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] xbuf: {cov["total_ops"]} ops '
          f'(rd={cov["n_read_data"]} '
          f'ilv={cov["interleave_write_read_adjacent"]} '
          f'same-cyc={cov["same_cycle_wr_rd"]} '
          f'hold={cov["idle_hold"]}), manifest written')


if __name__ == '__main__':
    main()
