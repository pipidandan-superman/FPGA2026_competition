#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""xbuf 冻结激励角落性质审计（M4 改造前只读检查，不改任何文件）。

目的：把 yolo_xbuf 从分布式 LUTRAM 重写为 2x BMG(2304x128, 16 字节写使能,
SDP, READ_FIRST, 读延迟 1 拍) 之前，确认冻结激励会触到哪些角落，从而
锁定包装器的等价性要求：
  A. 同 bank 同地址的 WRRD（同拍写读碰撞）数量 —— 决定 WRITE_MODE 语义
     是否被激励触碰（RTL 参考行为 = 非阻塞 = 读旧值 = READ_FIRST）；
  B. 首次读之前的操作数与其期望值（ed==0 / ev==0，即复位值比对）；
  C. ren=0 的保持拍里 rd_bank 相对上次读的 bank 是否变化（决定读侧
     bank 选择是否必须寄存保持）；
  D. 是否存在读从未写满 16 列的 (bank,addr)（RTL 参考为 x，vecgen 应
     已避免；若非 0 则需要停下重审）；
  E. 全程 evld 与 op 类型的一致性、保持拍期望值 == 上一次读的期望值
     （确认期望模型本身使用保持语义）。
输出：仅打印统计，任何文件不写。
"""
import sys

BASE = r"E:\competition\2_fpga\3_yolo_zynq\sim\stim\xbuf"

def load(name):
    vals = []
    with open(BASE + "\\" + name, "r") as f:
        for line in f:
            s = line.strip()
            if s:
                vals.append(int(s, 16))
    return vals

def main():
    n_ops = load("n_ops.hex")[0]
    op    = load("op.hex")
    bank  = load("bank.hex")
    col   = load("col_u8.hex")
    k     = load("kaddr_u16.hex")
    rb    = load("rbank.hex")
    rk    = load("rkaddr_u16.hex")
    ed    = load("edout_i128.hex")
    ev    = load("evld.hex")
    names = ["op","bank","col","k","rb","rk","ed","ev"]
    arrs  = [op,bank,col,k,rb,rk,ed,ev]
    print("n_ops(hex file) = %d (0x%X)" % (n_ops, n_ops))
    for nm, a in zip(names, arrs):
        print("  %-4s len=%d" % (nm, len(a)))
    assert all(len(a) == n_ops for a in arrs), "length mismatch vs n_ops"

    # per-bank written columns: mem[b][addr] = set(cols written)
    mem = {0: {}, 1: {}}
    first_read = None
    n_collide = 0            # A: WRRD 同 bank 同地址
    n_collide_same_bank_diff_k = 0
    n_hold_bank_change = 0    # C: ev==0 且 rd_bank != 最近一次读的 bank
    n_hold_bank_change_after_read = 0
    n_unwritten_read = 0      # D: 读 (bank,addr) 时 16 列未写满
    n_ev_mismatch = 0         # E: ev 与 op 类型不一致
    n_pre_read_ops = 0        # B: 首读之前的操作数
    n_pre_read_ed_nonzero = 0
    n_hold_ed_mismatch = 0    # E: 保持拍期望 != 上次读期望
    last_rd_bank = None
    last_ed = 0

    for c in range(n_ops):
        o = op[c]
        wr = o in (1, 3)
        rd = o in (2, 3)
        if ev[c] != (1 if rd else 0):
            n_ev_mismatch += 1
        if wr:
            mem[bank[c]].setdefault(k[c], set()).add(col[c])
        if rd:
            b = bank[c] if o == 2 else rb[c]
            kk = k[c] if o == 2 else rk[c]
            if first_read is None:
                first_read = c
            if len(mem[b].get(kk, set())) != 16:
                n_unwritten_read += 1
            if last_rd_bank is not None and ev[c] == 0:
                pass
            last_rd_bank = b
            last_ed = ed[c]
            if o == 3 and bank[c] == b and k[c] == kk:
                n_collide += 1
            if o == 3 and bank[c] == b and k[c] != kk:
                n_collide_same_bank_diff_k += 1
        else:
            if last_rd_bank is not None and rb[c] != last_rd_bank:
                n_hold_bank_change += 1
                n_hold_bank_change_after_read += 1
            if first_read is None:
                n_pre_read_ops += 1
                if ed[c] != 0:
                    n_pre_read_ed_nonzero += 1
            else:
                if ed[c] != last_ed:
                    n_hold_ed_mismatch += 1

    print("A. WRRD 同bank同地址碰撞      : %d" % n_collide)
    print("   WRRD 同bank不同地址        : %d" % n_collide_same_bank_diff_k)
    print("B. 首读前操作数               : %d (first_read op#=%s)" %
          (n_pre_read_ops, first_read))
    print("   首读前期望 ed!=0 的数量    : %d" % n_pre_read_ed_nonzero)
    print("C. 保持拍 rd_bank 变化        : %d" % n_hold_bank_change)
    print("D. 读未写满16列 (bank,addr)   : %d" % n_unwritten_read)
    print("E. ev 与 op 类型不一致        : %d" % n_ev_mismatch)
    print("   保持拍期望 != 上次读期望   : %d" % n_hold_ed_mismatch)

    ok = (n_unwritten_read == 0 and n_ev_mismatch == 0
          and n_hold_ed_mismatch == 0 and n_pre_read_ed_nonzero == 0)
    print("AUDIT_%s" % ("OK" if ok else "NG"))
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
