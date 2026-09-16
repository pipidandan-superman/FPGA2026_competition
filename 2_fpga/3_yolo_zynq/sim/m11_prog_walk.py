#!/usr/bin/env python3
# m11_prog_walk.py -- 只读解码 sim/stim/m11/prog.hex 的算子序列
# 目的：还原 conv4(task6) 与 conv5(task9) 之间的 PS 算子及其源/目的
# 区域，判断 conv5 的 xbase 读窗是否全部被已写区域覆盖。
# 字段布局 = tb_yolo_fullnet.v 的 OP_* 分发（FLDS=28）。
import sys

D = r"E:\competition\2_fpga\3_yolo_zynq\sim\stim\m11"
prog = [int(x, 16) for x in open(D + r"\prog.hex").read().split()]
n = len(prog)
print(f"prog words={n}")

OPS = {0: "END", 1: "CONV", 2: "COPY", 3: "RSCL", 4: "ADD", 5: "MAXP5", 6: "UPS2", 7: "HEADS"}

pc = 0
rows = []
while pc < n and prog[pc] != 0:
    op = OPS.get(prog[pc], f"BAD({prog[pc]})")
    row = {"pc": pc, "op": op}
    if op == "CONV":
        f = prog[pc + 1: pc + 29]
        row.update(task=f[26], oc=f[1], nn=f[2], k=f[3], ih=f[4], iw=f[5], ow=f[6],
                   ic=f[7], kh=f[8], kw=f[9], sh=f[10], sw=f[11], ph=f[12], pw=f[13],
                   first=f[14], act=f[15], wbase=f[17], xbase=f[18], bbase=f[19],
                   mbase=f[20], sbase=f[21], lut=f[22], ybase=f[24], gold=f[25])
        pc += 29
    elif op == "COPY":
        row.update(dst=prog[pc + 1], src=prog[pc + 2], ln=prog[pc + 3]); pc += 4
    elif op == "RSCL":
        row.update(dst=prog[pc + 1], src=prog[pc + 2], ln=prog[pc + 3],
                   mul=prog[pc + 4], sh=prog[pc + 5]); pc += 6
    elif op == "ADD":
        row.update(dst=prog[pc + 1], a=prog[pc + 2], ma=prog[pc + 3], sa=prog[pc + 4],
                   b=prog[pc + 5], mb=prog[pc + 6], sb=prog[pc + 7], ln=prog[pc + 8]); pc += 9
    elif op == "MAXP5":
        row.update(dst=prog[pc + 1], src=prog[pc + 2], w=prog[pc + 3],
                   h=prog[pc + 4], c=prog[pc + 5]); pc += 6
    elif op == "UPS2":
        row.update(dst=prog[pc + 1], src=prog[pc + 2], w=prog[pc + 3],
                   h=prog[pc + 4], c=prog[pc + 5]); pc += 6
    elif op == "HEADS":
        nt = prog[pc + 1]
        row.update(nt=nt)
        pc += 2 + 2 * nt
    else:
        print(f"STOP bad opcode at pc={pc}"); break
    rows.append(row)

conv_n = 0
for r in rows:
    if r["op"] == "CONV":
        tag = f"conv{conv_n}"
        conv_n += 1
    else:
        tag = "    "
    if r["op"] == "CONV" and 3 <= conv_n - 1 <= 6 or r["op"] != "CONV":
        print(f"pc={r['pc']:5d} {tag:6s} {r['op']:6s} " +
              " ".join(f"{k}={v}" for k, v in r.items() if k not in ("pc", "op")))

# conv5 读窗覆盖检查：xbase 起 ic*ih*iw（或 kh/kw 扫过的行窗）字节
print("\n== conv5 覆盖预查 ==")
c5 = [r for r in rows if r["op"] == "CONV"][:6]
for r in c5:
    print(f"task={r['task']} xbase={r['xbase']} wbase={r['wbase']} ybase={r['ybase']} "
          f"gold={r['gold']} ic={r['ic']} ih={r['ih']} iw={r['iw']} k={r['k']} "
          f"kh={r['kh']} kw={r['kw']} sh={r['sh']} sw={r['sw']} ph={r['ph']} pw={r['pw']} "
          f"first={r['first']} act={r['act']}")
