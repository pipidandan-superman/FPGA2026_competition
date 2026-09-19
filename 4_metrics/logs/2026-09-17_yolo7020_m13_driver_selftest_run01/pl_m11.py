#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M11 板端驱动（A2 loader V2，EES-331 XC7Z020 PYNQ Linux）。

执行 sim/stim/m11 全套程序（prog.hex/lut_all.hex/ddr.hex）：
  PS 角   = 本进程（numpy，逐位对齐 TB t_copy/t_rscl/t_add/t_maxp5/
            t_ups2 = pynq/intarith.py 原语）+ 活 DDR 镜像同步合同
  PL 角色 = yolo_engine_top（GP0 CSR @0x43C1_0000，HP0 W读+Y写，
            HP1 X 读；见 hw_contract/address_map.md V1.1）

流程（对齐 tb_yolo_fullnet V1.2 解释器，token 布局唯一事实源）：
  conv 行 = 29 词（tok14 first / tok15 act / tok16 walk / tok17..21
            W/X/B/M/S 基址 / tok22 lut_idx / tok24 y_base / tok25
            g_base / tok26 task_idx）；last 位 = 层序 == n_conv-1。
  每层：LUT 窗口 256 写 -> DESC0..5 + BASE*6（+DDR_BASE）-> CTRL.START
        -> 轮询 STATUS ldone_cnt 增量 -> DDR 读回 y 区入镜像 ->
        与 g_base 黄金区逐字节比对（板端复刻 TB per-conv check）。
  PS op：镜像上 numpy，dst 段写回 DDR（后层 X 区 = 前步输出，
        物理链接与 TB 同构）。
  判据：nerr==0 && convs==63 && psops==65 && head 149100 字节
        sha256 == 9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad

用法（板上）：
  python3 pl_m11.py                       # stim 目录 = 脚本同目录
  python3 pl_m11.py --stim /mnt/sd/m11 --ddr-base 0x30000000
PC 端预处理（可选，板端解析 30MB hex -> 直接读 bin）：
  python3 pl_m11.py --mkbin --stim <m11 目录>

DDR carve-out：默认 0x30000000（1GB 高段），跑前建议
  echo 3 > /proc/sys/vm/drop_caches
若内核占页导致 oops，改设备树 reserved-memory 或换 --ddr-base。
"""
import argparse
import binascii
import hashlib
import mmap
import os
import struct
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from intarith import rne_shift, sat_i8, sat_i32, maxpool5, upsample_nearest2

HEAD_SHA_GOLDEN = ("9ce70525fc1732cde640bfa654919dd28504422aa"
                   "9791a2875225ae6ad6aa6ad")
EXPECT = dict(convs=63, psops=65, compared=3553900, head_bytes=149100)

# opcodes（m11_vecgen.py 合同 = tb_yolo_fullnet.v localparam）
OP_END, OP_CONV, OP_COPY, OP_RSCL = 0, 1, 2, 3
OP_ADD, OP_MAXP5, OP_UPS2, OP_HEADS = 4, 5, 6, 7
FLDS = 28        # conv 行 token 数（tb_yolo_fullnet FLDS=28；walk@16）

# CSR 偏移（address_map.md V1.1 单一事实源）
O_CTRL, O_STATUS = 0x08, 0x0C
O_DESC0, O_LUT = 0x10, 0x400


# ---------------------------------------------------------------- stim
def load_words(path_bin, path_hex, width):
    """32 位词表（prog）或 N 字节表：优先 .bin，退回 .hex 逐行解析。"""
    if path_bin and os.path.exists(path_bin):
        raw = open(path_bin, "rb").read()
        if width == 4:
            return np.frombuffer(raw, dtype="<u4").astype(np.int64)
        return np.frombuffer(raw, dtype=np.uint8)
    with open(path_hex, "rb") as f:
        lines = f.read().split()
    if width == 4:
        return np.array([int(l, 16) for l in lines], dtype=np.int64)
    return np.array([int(l, 16) for l in lines], dtype=np.uint8)


def load_ddr(path_bin, path_hex, n_words):
    """ddr.hex = 1665001 行 64 位词 -> 13,320,008 字节小端物理镜像。"""
    if path_bin and os.path.exists(path_bin):
        return open(path_bin, "rb").read()
    with open(path_hex, "rb") as f:
        blob = binascii.unhexlify(b"".join(f.read().split()))
    words = np.frombuffer(blob, dtype=">u8")[:n_words]
    return words.byteswap().tobytes()          # >u8 -> <u8 物理布局


def mkbin(stim):
    """PC 端：hex 三件 -> prog.bin/lut_all.bin/ddr.bin（板端免解析）。"""
    n_words = int(open(f"{stim}/n_ddrwords.hex").readline(), 16)
    prog = load_words(None, f"{stim}/prog.hex", 4)
    lut = load_words(None, f"{stim}/lut_all.hex", 1)
    ddr = load_ddr(None, f"{stim}/ddr.hex", n_words)
    prog.astype("<u4").tofile(f"{stim}/prog.bin")
    lut.tofile(f"{stim}/lut_all.bin")
    open(f"{stim}/ddr.bin", "wb").write(ddr)
    print(f"[mkbin] prog={len(prog)}w lut={len(lut)}B ddr={len(ddr)}B")


# ------------------------------------------------------------- PL 通道
class PL:
    """GP0 CSR 窗口 + DDR carve-out（/dev/mem 固定地址，无 .hwh 依赖）。"""

    def __init__(self, csr_base, ddr_base, ddr_len):
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        self.csr = mmap.mmap(fd, 0x10000, flags=mmap.MAP_SHARED,
                             offset=csr_base)
        self.ddr_base = ddr_base
        self.ddr = mmap.mmap(fd, ddr_len, flags=mmap.MAP_SHARED,
                             offset=ddr_base)
        os.close(fd)
        ident, ver = self.r32(0x00), self.r32(0x04)
        if ident != 0x594F4C31 or ver != 0x00020000:
            raise RuntimeError(f"CSR ID/VER 不符 {ident:08X}/{ver:08X}"
                               "（bitstream 未加载或非 A2 版）")

    def w32(self, off, v):
        self.csr[off:off + 4] = struct.pack("<I", v & 0xFFFFFFFF)

    def r32(self, off):
        return struct.unpack("<I", self.csr[off:off + 4])[0]

    def status(self):
        s = self.r32(O_STATUS)
        return s & 1, (s >> 1) & 1, (s >> 2) & 1, (s >> 3) & 1, s >> 16

    def run_conv(self, tok, last, lut, timeout_s=30.0):
        """一层：LUT 预载 + 描述符 + 门铃 + 轮询 ldone_cnt 增量。"""
        for i in range(256):
            self.w32(O_LUT + 4 * i, int(lut[i]))
        self.w32(0x10, ((tok[2] & 0xFFFF) << 16) | (tok[1] & 0x7FF))
        self.w32(0x14, (tok[3] & 0xFFF) | ((1 if last else 0) << 16)
                 | (tok[14] << 17) | (tok[15] << 18) | (tok[16] << 19))
        self.w32(0x18, ((tok[5] & 0xFFFF) << 16) | (tok[4] & 0xFFFF))
        self.w32(0x1C, ((tok[7] & 0xFFFF) << 16) | (tok[6] & 0xFFFF))
        self.w32(0x20, (tok[8] & 0xFF) | ((tok[9] & 0xFF) << 8)
                 | ((tok[10] & 0xFF) << 16) | ((tok[11] & 0xFF) << 24))
        self.w32(0x24, (tok[12] & 0xFF) | ((tok[13] & 0xFF) << 8))
        for reg, off in ((0x28, 17), (0x2C, 18), (0x30, 24), (0x34, 19),
                         (0x38, 20), (0x3C, 21)):
            self.w32(reg, self.ddr_base + int(tok[off]))
        _, ready, _, _, done0 = self.status()
        if not ready:
            raise RuntimeError("dsc_ready=0 at doorbell")
        self.w32(O_CTRL, 1)                      # START 门铃
        t0 = time.monotonic()
        target = done0 + 1
        while True:
            _, _, _, pend, done = self.status()
            if done >= target:
                return time.monotonic() - t0
            if pend and time.monotonic() - t0 > 0.100:
                # 门铃长期未受理：描述符/基址在 pend=1 期间被改过的唯一
                # 可能是本驱动 bug —— 直接报错而不是死等
                raise RuntimeError(f"dsc_pend 卡住 ldone={done}")
            if time.monotonic() - t0 > timeout_s:
                raise RuntimeError(f"层超时 ldone={done} busy/pend="
                                   f"{self.status()}")
            time.sleep(0.0002)


# ------------------------------------------------------------- PS ops
def ps_op(pl, mirror, op, a):
    """TB t_* 逐位对齐；输入取自镜像，dst 段写回 DDR（同步合同）。"""
    dst = int(a[0])
    if op == OP_COPY:
        src, ln = int(a[1]), int(a[2])
        mirror[dst:dst + ln] = mirror[src:src + ln]
        pl.ddr[dst:dst + ln] = mirror[dst:dst + ln]
        return ln
    if op == OP_RSCL:
        src, ln, mu, s = int(a[1]), int(a[2]), int(a[3]), int(a[4])
        if mu == 0 and s == 0:                       # t_rscl 全零特例
            out = np.zeros(ln, dtype=np.int8)
        else:
            v = np.frombuffer(mirror[src:src + ln], dtype=np.int8)
            out = sat_i8(rne_shift(v.astype(np.int64) * mu, s))
        mirror[dst:dst + ln] = out.tobytes()
        pl.ddr[dst:dst + ln] = out.tobytes()
        return ln
    if op == OP_ADD:
        asrc, bsrc, ln = int(a[0 + 1]), int(a[1 + 1]), int(a[2 + 1])
        ma, sa, mb, sb = (int(a[3 + 1]), int(a[4 + 1]),
                          int(a[5 + 1]), int(a[6 + 1]))
        dst = int(a[0])
        va = np.frombuffer(mirror[asrc:asrc + ln], dtype=np.int8)
        vb = np.frombuffer(mirror[bsrc:bsrc + ln], dtype=np.int8)
        out = sat_i8(sat_i32(rne_shift(va.astype(np.int64) * ma, sa)
                             + rne_shift(vb.astype(np.int64) * mb, sb)
                             ).astype(np.int64))
        mirror[dst:dst + ln] = out.tobytes()
        pl.ddr[dst:dst + ln] = out.tobytes()
        return ln
    if op == OP_MAXP5:
        src, c, h, w = int(a[1]), int(a[2]), int(a[3]), int(a[4])
        x = np.frombuffer(mirror[src:src + c * h * w],
                          dtype=np.int8).reshape(1, c, h, w)
        out = maxpool5(x).tobytes()
        mirror[dst:dst + c * h * w] = out
        pl.ddr[dst:dst + c * h * w] = out
        return c * h * w
    if op == OP_UPS2:
        src, c, h, w = int(a[1]), int(a[2]), int(a[3]), int(a[4])
        x = np.frombuffer(mirror[src:src + c * h * w],
                          dtype=np.int8).reshape(1, c, h, w)
        out = upsample_nearest2(x).tobytes()
        mirror[dst:dst + c * h * w * 4] = out
        pl.ddr[dst:dst + c * h * w * 4] = out
        return c * h * w * 4
    raise ValueError(op)


# ------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stim", default=os.path.dirname(
        os.path.abspath(__file__)))
    ap.add_argument("--csr", type=lambda x: int(x, 0), default=0x43C10000)
    ap.add_argument("--ddr-base", type=lambda x: int(x, 0),
                    default=0x30000000)
    ap.add_argument("--maxconv", type=int, default=63)
    ap.add_argument("--head-out", default="head_dump.bin")
    ap.add_argument("--mkbin", action="store_true")
    args = ap.parse_args()
    if args.mkbin:
        mkbin(args.stim)
        return

    n_words = int(open(f"{args.stim}/n_ddrwords.hex").readline(), 16)
    n_conv = int(open(f"{args.stim}/n_conv.hex").readline(), 16)
    prog = load_words(f"{args.stim}/prog.bin", f"{args.stim}/prog.hex", 4)
    lut = load_words(f"{args.stim}/lut_all.bin", f"{args.stim}/lut_all.hex", 1)
    mirror = bytearray(load_ddr(f"{args.stim}/ddr.bin",
                                f"{args.stim}/ddr.hex", n_words))
    print(f"[stim] prog={len(prog)}w lut={len(lut)}B mirror={len(mirror)}B"
          f" n_conv={n_conv}")

    pl = PL(args.csr, args.ddr_base, len(mirror))
    pl.w32(O_CTRL, 2)                              # CLR_STATS 帧首
    pl.ddr[:] = mirror[:]                          # 全量镜像入 DDR
    print("[ddr] mirror -> DDR 完成")

    convs = ps_ops = compared = nerr = head_bytes = 0
    t_conv = t_ps = 0.0
    first_err = None
    pc = 0
    while True:
        op = int(prog[pc])
        if op == OP_END:
            break
        if op == OP_CONV:
            tok = prog[pc + 1:pc + 1 + FLDS]
            oc, n = int(tok[1]), int(tok[2])
            dt = pl.run_conv(tok, convs == args.maxconv - 1,
                             lut[int(tok[22]) * 256:
                                 (int(tok[22]) + 1) * 256])
            yb, gb, tot = int(tok[24]), int(tok[25]), oc * n
            got = bytes(pl.ddr[yb:yb + tot])
            mirror[yb:yb + tot] = got               # 读回 = 镜像同步
            gold = mirror[gb:gb + tot]
            bad = np.frombuffer(got, np.int8) != np.frombuffer(gold, np.int8)
            nb = int(bad.sum())
            if nb and first_err is None:
                i = int(np.argmax(bad))
                first_err = (convs, i, got[i], gold[i])
            nerr += nb
            compared += tot
            t_conv += dt
            print(f"[conv {convs:2d}/{args.maxconv}] task={int(tok[26]):2d}"
                  f" oc={oc:3d} n={n:5d} walk={int(tok[16])}"
                  f" t={dt * 1000:8.2f}ms acc_err={nb}")
            convs += 1
            pc += 1 + FLDS
        elif op == OP_HEADS:
            nt = int(prog[pc + 1])
            head = bytearray()
            for k in range(nt):
                b0, ln = int(prog[pc + 2 + 2 * k]), int(prog[pc + 3 + 2 * k])
                head += mirror[b0:b0 + ln]
                head_bytes += ln
            open(args.head_out, "wb").write(head)
            print(f"[heads] {head_bytes}B -> {args.head_out}")
            pc += 2 + 2 * nt
        else:
            t0 = time.monotonic()
            ps_op(pl, mirror, op, prog[pc + 1:pc + 9])
            t_ps += time.monotonic() - t0
            ps_ops += 1
            pc += {OP_COPY: 4, OP_RSCL: 6, OP_ADD: 9,
                   OP_MAXP5: 6, OP_UPS2: 6}[op]

    sha = hashlib.sha256(open(args.head_out, "rb").read()).hexdigest()
    t_wall = t_conv + t_ps
    ok = (nerr == 0 and convs == args.maxconv
          and (args.maxconv < 63
               or (ps_ops == EXPECT["psops"]
                   and head_bytes == EXPECT["head_bytes"]
                   and sha == HEAD_SHA_GOLDEN)))
    tag = "PL_M11_PASS" if ok else "PL_M11_FAIL"
    print(f"{tag} convs={convs} psops={ps_ops} compared={compared} "
          f"nerr={nerr} head_bytes={head_bytes} "
          f"head_sha256={sha[:16]}... conv_ms={t_conv * 1000:.1f} "
          f"ps_ms={t_ps * 1000:.1f} fps_est={1.0 / t_wall if t_wall else 0:.2f}"
          + ("" if ok else
             f" first_err(conv,i,dut,gold)={first_err} "
             f"sha_expect={HEAD_SHA_GOLDEN[:16]}..."))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
