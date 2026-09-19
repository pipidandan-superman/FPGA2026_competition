#!/usr/bin/env python3
"""pl_b2_loopback.py - B2 board gate: GEMM regression (path A) + DMA loopback (path B).

Maps to zynq-pynq-overlay-workflow canon (CK1-CK4 load gates, staged) then:
  Path A (regression, verbatim from run23 pl_gemm_b1.py):
    CK6 S1 full 8x16 K=64 act=1 / CK7 S2 masked / CK8 S3 two-block / CK9 soft_rst
    Seeds identical to run23 (0x5119/0x2240/0x3396) - the BD changed (ic0 M02,
    PS7 HP0), path A re-proves the untouched half was not disturbed.
  Path B (new, PS-DMA loopback over HP0):
    DB1 reset state: DMASR.SGIncld==0 (SG off on silicon) + Halted==1, both ch
    DB2 bring-up: DMACR.RS=1 -> poll Halted==0
    DB3 basic 4096B loopback: S2MM armed first, then MM2S; IOC+Idle poll on both;
       byte-exact compare + no-overrun tail check
    DB4 size sweep 137/1/1000/8192 (aligned starts, partial-beat tails)
    DB5 back-to-back x3 4096B without halt between
    DB6 stop + soft reset hygiene (RS=0 -> Halted; DMACR.Reset self-clear)
    DB7 cross-liveness: DMA 256B recovery transfer + GEMM full S1 rerun (new
       seed 0x7E11) in the same session - both paths alive together
  Verdict: BOARD_B2_PASS only if every gate passed.

DMA register model is NOT from memory: every offset/field below is transcribed
from the IP's own display_test_axi_dma_0_0.xci memory_maps/S_AXI_LITE (extracted
2026-09-19 preflight, see preflight_bd_check.txt):
  MM2S_DMACR 0x00 RS[0] Reset[2] IOC_IrqEn[12] Err_IrqEn[14]
  MM2S_DMASR 0x04 Halted[0] Idle[1] SGIncld[3] IntErr[4] SlvErr[5] DecErr[6]
                  IOC_Irq[12] Dly_Irq[13] Err_Irq[14]   (W1C on irq bits)
  MM2S_SA 0x18 / MM2S_LENGTH 0x28
  S2MM_DMACR 0x30 / S2MM_DMASR 0x34 / S2MM_DA 0x48 / S2MM_LENGTH 0x58
BD: axi_dma_0 Reg @0x40400000/64K; M_AXIS_MM2S->S_AXIS_S2MM direct loopback;
M_AXI_{MM2S,S2MM} -> axi_mem_intercon -> PS7 S_AXI_HP0 (DDR 0x0/1G).

Dual-channel logging: stdout + /dev/console.  Usage (root): python3 this.py <tag>
"""
import os, sys, time, hashlib, subprocess, random, select
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
BIT = os.path.join(HERE, 'display_test_wrapper.bit')
tag = sys.argv[1] if len(sys.argv) > 1 else 'b2'

GEMM_BASE, CSR_BASE, DMA_BASE = 0x43C00000, 0x43C10000, 0x40400000
EXP_GEMM_ID = 0x20260919
EXP_CSR_ID, EXP_CSR_VER = 0x594F4C32, 0x0300

# ---- yolo_gemm_top.v V1.0 register map (byte offsets, unchanged) ----
A_ID, A_CTRL, A_STATUS = 0x00, 0x04, 0x08
A_GEOM, A_ROWVAL, A_NMASK, A_JOBCFG, A_LDGRP = 0x0C, 0x10, 0x14, 0x18, 0x1C
A_P_BIAS, A_P_M, A_P_SH, A_PCTL = 0x20, 0x24, 0x28, 0x2C
A_WDATA, A_WDATA2, A_WCTL = 0x30, 0x34, 0x38
A_LDSTAT, A_LDLEN, A_LUTD = 0x3C, 0x40, 0x44
A_YSTAT, A_YADDR, A_YDATA = 0x48, 0x4C, 0x50

# ---- axi_dma_0 register map (from XCI memory_maps, see header) ----
D_MM2S_DMACR, D_MM2S_DMASR, D_MM2S_SA, D_MM2S_LEN = 0x00, 0x04, 0x18, 0x28
D_S2MM_DMACR, D_S2MM_DMASR, D_S2MM_DA, D_S2MM_LEN = 0x30, 0x34, 0x48, 0x58
B_RS, B_DMARESET = 0x1, 0x4
B_HALTED, B_IDLE, B_SGINCLD = 0x1, 0x2, 0x8
B_ERRS = 0x70                    # IntErr|SlvErr|DecErr
B_IOC_IRQ, B_ERR_IRQ = 0x1000, 0x4000

P_TO, P_TN = 8, 16
CB = [-128, -1, 0, 1, 127, -128]
BUF_SZ = 16384

results = {}
counts = {'wop': 0, 'rop': 0, 'rb_ok': 0, 'rb_bad': 0, 'db_ok': 0, 'db_bad': 0}


def emit(m):
    line = '[%s %s %s]' % (tag, m, time.strftime('%H:%M:%S'))
    print(line, flush=True)
    try:
        with open('/dev/console', 'a') as c:
            c.write(line + '\n'); c.flush()
    except Exception as e:
        print('[console-fail %r]' % e, flush=True)


# ---------------- GEMM oracle + sequences (run23 verbatim) ----------------
def sat_addr(q7):
    return (q7 + 128) & 0xFF


def requant(acc, bias, m, s):
    p = (acc + bias) * m
    if s == 0:
        fl, rr = p, 0
    else:
        mod = 1 << s
        hh = mod >> 1
        fl = p // mod if p >= 0 else -((-p) // mod)
        if p < 0 and (p % mod) != 0:
            fl -= 1
        rr = p - fl * mod
    qn = fl + (1 if (rr > hh or (rr == hh and (fl & 1))) else 0)
    qn = 127 if qn > 127 else (-128 if qn < -128 else qn)
    return qn


def fill_wx(K, rng):
    Wm = [[0] * K for _ in range(P_TO)]
    Xm = [[0] * K for _ in range(P_TN)]
    for k in range(K):
        for i in range(P_TN):
            if i < P_TO:
                Wm[i][k] = CB[rng.randrange(6)] if rng.randrange(16) == 0 \
                    else rng.randrange(256) - 128
            Xm[i][k] = CB[rng.randrange(6)] if rng.randrange(16) == 0 \
                else rng.randrange(256) - 128
    return Wm, Xm


def load_params(m, rng):
    PB, PM, PS = [0] * P_TO, [0] * P_TO, [0] * P_TO
    for r in range(P_TO):
        PB[r] = rng.randrange(0x08000000) - 0x04000000
        PM[r] = -0x40000000 if rng.randrange(4) == 0 else 0x40000000
        if rng.randrange(8) == 0:
            PM[r] = 1
        PS[r] = 1 + rng.randrange(62)
        m.write(A_P_BIAS, PB[r] & 0xFFFFFFFF)
        m.write(A_P_M, PM[r] & 0xFFFFFFFF)
        m.write(A_P_SH, PS[r])
        m.write(A_PCTL, 0x100 | r)
        counts['wop'] += 4
    return PB, PM, PS


def push_expected(K, Wm, Xm, PB, PM, PS, rvm, nmm):
    eqm = [[0] * P_TN for _ in range(P_TO)]
    for r in range(P_TO):
        if (rvm >> r) & 1:
            for n in range(P_TN):
                if (nmm >> n) & 1:
                    acc = 0
                    for k in range(K):
                        acc += Wm[r][k] * Xm[n][k]
                    eqm[r][n] = requant(acc, PB[r], PM[r], PS[r])
    return eqm


def wr(m, a, d):
    m.write(a & 0xFFFFFFFF, d & 0xFFFFFFFF)
    counts['wop'] += 1


def rd(m, a):
    v = m.read(a)
    counts['rop'] += 1
    return v


def wr_beat(m, d64, is_x, x_hi, first, last):
    wr(m, A_WDATA, d64 & 0xFFFFFFFF)
    wr(m, A_WDATA2, (d64 >> 32) & 0xFFFFFFFF)
    wr(m, A_WCTL, (0x800 if last else 0) | (0x400 if first else 0) |
       (0xFF << 2) | (0x02 if x_hi else 0) | (0x01 if is_x else 0))


def bank_load(m, Wm, Xm, ln, k0, grp):
    wr(m, A_LDGRP, 3 if grp else 0)
    for k in range(ln):
        w64 = 0
        for i in range(P_TO):
            w64 |= (Wm[i][k0 + k] & 0xFF) << (8 * i)
        wr_beat(m, w64, 0, 0, first=(k == 0), last=0)
        x64 = 0
        for i in range(8):
            x64 |= (Xm[i][k0 + k] & 0xFF) << (8 * i)
        wr_beat(m, x64, 1, 0, first=0, last=0)
        x64 = 0
        for i in range(8):
            x64 |= (Xm[i + 8][k0 + k] & 0xFF) << (8 * i)
        wr_beat(m, x64, 1, 1, first=0, last=(k == ln - 1))
    for _ in range(4000):
        st = rd(m, A_STATUS)
        ll = rd(m, A_LDLEN)
        if (st & 0x8) and (ll & 0x1FFF) == ln and ((ll >> 13) & 0x1FFF) == ln:
            return True
    emit('CKx ld incomplete grp=%d STATUS=%08X LDLEN=%08X exp=%d'
         % (grp, st, ll, ln))
    return False


def run_job(m, jlen, act, first, last, wgrp, xgrp, timeout_s=30):
    wr(m, A_GEOM, jlen)
    wr(m, A_JOBCFG, (1 if act else 0) | (2 if first else 0) |
       (4 if last else 0) | (8 if wgrp else 0) | (16 if xgrp else 0))
    wr(m, A_CTRL, 1)
    t0 = time.time()
    st = 0
    while time.time() - t0 < timeout_s:
        st = rd(m, A_STATUS)
        if (st & 0x1) == 0 and (st & 0x20):
            break
    done = ((st & 0x1) == 0) and bool(st & 0x20)
    errs = (st >> 6) & 0xF
    return done, errs, st


def readback(m, eqm, lut_exp, act_exp, rvm, nmm):
    first_bad = []
    for r in range(P_TO):
        if (rvm >> r) & 1:
            for n in range(P_TN):
                if (nmm >> n) & 1:
                    wr(m, A_YADDR, (r << 4) | n)
                    rd(m, A_STATUS)
                    got = rd(m, A_YDATA) & 0xFF
                    q7 = eqm[r][n]
                    exp = (lut_exp[sat_addr(q7)] if act_exp else q7) & 0xFF
                    if got == exp:
                        counts['rb_ok'] += 1
                    else:
                        counts['rb_bad'] += 1
                        if len(first_bad) < 8:
                            first_bad.append((r, n, got, exp))
    return first_bad


def gemm_s1(g, lut_exp, seed, gate):
    """One full 8x16 K=64 act=1 job; returns True if 128/128 + y_count=128."""
    for i in range(256):
        wr(g, A_LUTD, (i << 8) | lut_exp[i])
    rng = random.Random(seed)
    Wm, Xm = fill_wx(64, rng)
    PB, PM, PS = load_params(g, rng)
    eqm = push_expected(64, Wm, Xm, PB, PM, PS, 0xFF, 0xFFFF)
    wr(g, A_ROWVAL, 0xFF); wr(g, A_NMASK, 0xFFFF)
    if not bank_load(g, Wm, Xm, 64, 0, 0):
        return False
    done, errs, st = run_job(g, 64, 1, 1, 1, 0, 0)
    if not done or errs:
        emit('%s job done=%d errs=%X STATUS=%08X' % (gate, done, errs, st))
    bad = readback(g, eqm, lut_exp, True, 0xFF, 0xFFFF)
    ycnt = rd(g, A_YSTAT) & 0xFFFF
    ok = done and errs == 0 and not bad and ycnt == 128
    emit('%s rb=%d bad=%d y_count=%d STATUS=%08X %s'
         % (gate, counts['rb_ok'], counts['rb_bad'], ycnt, st,
            'PASS' if ok else 'FAIL'))
    if bad:
        emit('%s first mismatches %s' % (gate, bad))
    return ok


# ---------------- DMA loopback helpers ----------------
def dma_pattern(n, seed):
    rng = random.Random(seed)
    b = bytearray(n)
    if n >= 4:
        b[0], b[1], b[2], b[n - 1] = 0x00, 0xFF, 0x80, 0x7F
    for i in range(4, n - 1):
        b[i] = rng.randrange(256)
    return bytes(b)


def dma_xfer(d, src, dst, n, tmo=5.0):
    """One loopback transfer of n bytes. S2MM armed first, MM2S last."""
    d.write(D_S2MM_DA, dst.phys)
    d.write(D_S2MM_LEN, n)
    d.write(D_MM2S_SA, src.phys)
    d.write(D_MM2S_LEN, n)                               # starts MM2S
    t0 = time.time()
    ms = ss = 0
    while time.time() - t0 < tmo:
        ms = d.read(D_MM2S_DMASR)
        ss = d.read(D_S2MM_DMASR)
        if (ms & B_IOC_IRQ) and (ms & B_IDLE) and \
           (ss & B_IOC_IRQ) and (ss & B_IDLE):
            break
        time.sleep(0.001)
    d.write(D_MM2S_DMASR, B_IOC_IRQ | B_ERR_IRQ)         # W1C
    d.write(D_S2MM_DMASR, B_IOC_IRQ | B_ERR_IRQ)
    ok = bool((ms & B_IOC_IRQ) and (ms & B_IDLE) and
              (ss & B_IOC_IRQ) and (ss & B_IDLE) and
              not (ms & B_ERRS) and not (ss & B_ERRS))
    return ok, ms, ss


def dma_compare(dst, pat, n, label):
    got = bytes(dst.buf[:n])
    ok = got == pat
    if ok and n < BUF_SZ:
        tail = bytes(dst.buf[n:])
        ok = all(v == 0xA5 for v in tail)
        if not ok:
            emit('DBx %s tail overwritten beyond n=%d' % (label, n))
    counts['db_ok' if ok else 'db_bad'] += 1
    if not ok:
        for i in range(n):
            if got[i] != pat[i]:
                emit('DBx %s first diff @%d got=%02X exp=%02X'
                     % (label, i, got[i], pat[i]))
                break
    return ok


class DmaBuf(object):
    def __init__(self, npbuf):
        self.buf = npbuf
        self.phys = npbuf.device_address


def main():
    emit('CK0a start bit_sha=%s'
         % hashlib.sha256(open(BIT, 'rb').read()).hexdigest()[:16])
    os.environ['XILINX_XRT'] = '/usr'
    from pynq import Overlay, MMIO, allocate

    # ---- CK1: HWH contract (no download yet) ----
    ol = Overlay(BIT, download=False)
    ips = sorted(ol.ip_dict.keys())
    emit('CK1a ip_dict=%s' % ips)
    gp = ol.ip_dict.get('u_yolo_gemm', {}).get('phys_addr')
    cp = ol.ip_dict.get('u_yolo_csr', {}).get('phys_addr')
    dp = ol.ip_dict.get('axi_dma_0', {}).get('phys_addr')
    results['CK1'] = (gp == GEMM_BASE) and (cp == CSR_BASE) \
        and (dp == DMA_BASE)
    emit('CK1b gemm=%s csr=%s dma=%s -> %s'
         % (hex(gp) if gp is not None else None,
            hex(cp) if cp is not None else None,
            hex(dp) if dp is not None else None,
            'PASS' if results['CK1'] else 'FAIL'))
    if not results['CK1']:
        emit('CKz BOARD_B2_FAIL hwh_contract'); return 1

    # ---- CK2/CK3/CK4: download + liveness + fresh lock ----
    def lock_count():
        out = subprocess.run(['dmesg'], capture_output=True, text=True).stdout
        return sum(1 for l in out.splitlines() if 'locked, ref=1' in l)
    pre = lock_count()
    emit('CK2a pre_locks=%d download_begin' % pre)
    ol.download()
    emit('CK2b download_returned')
    st_fpga = open('/sys/class/fpga_manager/fpga0/state').read().strip()
    emit('CK3 state=%s' % st_fpga)
    post = lock_count()
    results['CK4'] = (st_fpga == 'operating') and (post == pre + 1)
    emit('CK4 lock_delta=%d -> %s' % (post - pre,
         'PASS' if results['CK4'] else 'FAIL'))
    if not results['CK4']:
        emit('CKz BOARD_B2_FAIL load'); return 1

    g = MMIO(GEMM_BASE, 0x10000)
    c = MMIO(CSR_BASE, 0x10000)
    d = MMIO(DMA_BASE, 0x1000)

    # ---- CK5: fork-protected first reads (GEMM ID + DMA MM2S_DMASR) ----
    emit('CK5a sacrificial_first_reads_begin (GEMM + DMA)')
    r_pipe, w_pipe = os.pipe()
    pid = os.fork()
    if pid == 0:
        try:
            v1 = g.read(0x00)
            v2 = d.read(D_MM2S_DMASR)
            os.write(w_pipe, b'OK %08X %08X' % (v1, v2))
        except Exception as e:
            os.write(w_pipe, b'FAULT %r' % e)
        os._exit(0)
    ready, _, _ = select.select([r_pipe], [], [], 5.0)
    if ready:
        msg = os.read(r_pipe, 64).decode().strip()
        os.close(r_pipe); os.close(w_pipe); os.waitpid(pid, 0)
    else:
        os.kill(pid, 9); os.waitpid(pid, 0)
        msg = 'AXI_HANG'
    emit('CK5b first_reads=%s' % msg)
    if not msg.startswith('OK'):
        emit('CKz BOARD_B2_FAIL first_read'); return 1
    gid = rd(g, A_ID)
    cid, cver = rd(c, 0x000), rd(c, 0x004)
    emit('CK5c GEMM_ID=0x%08X CSR_ID=0x%08X CSR_VER=0x%08X' % (gid, cid, cver))
    results['CK5'] = (gid == EXP_GEMM_ID) and (cid == EXP_CSR_ID) \
        and (cver == EXP_CSR_VER)
    emit('CK5d identity -> %s' % ('PASS' if results['CK5'] else 'FAIL'))
    if not results['CK5']:
        emit('CKz BOARD_B2_FAIL identity'); return 1

    lut_exp = [(i ^ 0xA5) & 0xFF for i in range(256)]

    # ================= Path A: GEMM regression (run23 verbatim) =================
    emit('PA_A begin GEMM regression (BD changed: ic0 M02 + PS7 HP0 added)')

    emit('CK6a S1_begin (seed 0x5119)')
    results['CK6'] = gemm_s1(g, lut_exp, 0x5119, 'CK6e S1')
    if not results['CK6']:
        emit('CKz BOARD_B2_FAIL s1'); return 1

    rb0 = counts['rb_ok']; bad0 = counts['rb_bad']
    emit('CK7a S2_begin (seed 0x2240)')
    rng = random.Random(0x2240)
    Wm2, Xm2 = fill_wx(40, rng)
    PB2, PM2, PS2 = load_params(g, rng)
    eqm_s2 = push_expected(40, Wm2, Xm2, PB2, PM2, PS2, 0x5A, 0x0F0F)
    wr(g, A_ROWVAL, 0x5A); wr(g, A_NMASK, 0x0F0F)
    if not bank_load(g, Wm2, Xm2, 40, 0, 1):
        emit('CKz BOARD_B2_FAIL s2_load'); return 1
    done, errs, st = run_job(g, 40, 0, 1, 1, 1, 1)
    if not done or errs:
        emit('CK7b S2 job done=%d errs=%X STATUS=%08X' % (done, errs, st))
    bad = readback(g, eqm_s2, lut_exp, False, 0x5A, 0x0F0F)
    wr(g, A_YADDR, 0)
    rd(g, A_STATUS)
    stale_got = rd(g, A_YDATA) & 0xFF          # logged only: addr0 keeps S1 value
    ycnt = rd(g, A_YSTAT) & 0xFFFF
    results['CK7'] = (done and errs == 0 and not bad and
                      counts['rb_ok'] - rb0 == 32 and counts['rb_bad'] == bad0 and
                      ycnt == 32)
    emit('CK7c S2 rb+=%d bad+=%d stale@0 got=%02X y_count=%d %s'
         % (counts['rb_ok'] - rb0, counts['rb_bad'] - bad0,
            stale_got, ycnt, 'PASS' if results['CK7'] else 'FAIL'))
    if bad:
        emit('CK7d S2 first mismatches %s' % bad)
    if not results['CK7']:
        emit('CKz BOARD_B2_FAIL s2'); return 1

    rb0 = counts['rb_ok']; bad0 = counts['rb_bad']
    emit('CK8a S3_begin (seed 0x3396)')
    rng = random.Random(0x3396)
    Wm3, Xm3 = fill_wx(96, rng)
    PB3, PM3, PS3 = load_params(g, rng)
    eqm_s3 = push_expected(96, Wm3, Xm3, PB3, PM3, PS3, 0xFF, 0xFFFF)
    wr(g, A_ROWVAL, 0xFF); wr(g, A_NMASK, 0xFFFF)
    if not bank_load(g, Wm3, Xm3, 48, 0, 0):
        emit('CKz BOARD_B2_FAIL s3_load0'); return 1
    wr(g, A_GEOM, 48)
    wr(g, A_JOBCFG, 0x3)
    wr(g, A_CTRL, 1)
    t0 = time.time()
    while time.time() - t0 < 10:
        if (rd(g, A_STATUS) & 0x2) == 0:
            break
    emit('CK8b S3 blk0 queued, grp1 concurrent load begin')
    if not bank_load(g, Wm3, Xm3, 48, 48, 1):
        emit('CKz BOARD_B2_FAIL s3_load1'); return 1
    done, errs, st = run_job(g, 48, 1, 0, 1, 1, 1)
    if not done or errs:
        emit('CK8c S3 job done=%d errs=%X STATUS=%08X' % (done, errs, st))
    bad = readback(g, eqm_s3, lut_exp, True, 0xFF, 0xFFFF)
    ycnt = rd(g, A_YSTAT) & 0xFFFF
    results['CK8'] = (done and errs == 0 and not bad and
                      counts['rb_ok'] - rb0 == 128 and counts['rb_bad'] == bad0 and
                      ycnt == 128)
    emit('CK8d S3 rb+=%d bad+=%d y_count=%d STATUS=%08X %s'
         % (counts['rb_ok'] - rb0, counts['rb_bad'] - bad0, ycnt, st,
            'PASS' if results['CK8'] else 'FAIL'))
    if bad:
        emit('CK8e S3 first mismatches %s' % bad)
    if not results['CK8']:
        emit('CKz BOARD_B2_FAIL s3'); return 1

    wr(g, A_CTRL, 2)
    rd(g, A_STATUS)
    st9, yst9, gid9 = rd(g, A_STATUS), rd(g, A_YSTAT), rd(g, A_ID)
    results['CK9'] = (st9 == 0) and ((yst9 & 0xFFFF) == 0) \
        and (gid9 == EXP_GEMM_ID)
    emit('CK9 soft_rst STATUS=%08X y_count=%d ID=%08X -> %s'
         % (st9, yst9 & 0xFFFF, gid9, 'PASS' if results['CK9'] else 'FAIL'))
    if not results['CK9']:
        emit('CKz BOARD_B2_FAIL sft_rst'); return 1

    # ================= Path B: DMA loopback over HP0 =================
    emit('PA_B begin DMA loopback')
    ms0, ss0 = rd(d, D_MM2S_DMASR), rd(d, D_S2MM_DMASR)
    results['DB1'] = ((ms0 & B_SGINCLD) == 0) and (ms0 & B_HALTED) and \
                     ((ss0 & B_SGINCLD) == 0) and (ss0 & B_HALTED)
    emit('DB1 reset_state MM2S_DMASR=%08X S2MM_DMASR=%08X '
         '(SGIncld=0, Halted=1 both) -> %s'
         % (ms0, ss0, 'PASS' if results['DB1'] else 'FAIL'))
    if not results['DB1']:
        emit('CKz BOARD_B2_FAIL dma_reset_state'); return 1

    d.write(D_MM2S_DMACR, B_RS)
    d.write(D_S2MM_DMACR, B_RS)
    t0 = time.time(); ok2 = True
    while time.time() - t0 < 2:
        ms = d.read(D_MM2S_DMASR); ss = d.read(D_S2MM_DMASR)
        if not (ms & B_HALTED) and not (ss & B_HALTED):
            break
        time.sleep(0.001)
    else:
        ok2 = False
    results['DB2'] = ok2 and not (ms & B_HALTED) and not (ss & B_HALTED)
    emit('DB2 run_bringup MM2S_DMASR=%08X S2MM_DMASR=%08X -> %s'
         % (ms, ss, 'PASS' if results['DB2'] else 'FAIL'))
    if not results['DB2']:
        emit('CKz BOARD_B2_FAIL dma_bringup'); return 1

    src = DmaBuf(allocate(shape=(BUF_SZ,), dtype=np.uint8))
    dst = DmaBuf(allocate(shape=(BUF_SZ,), dtype=np.uint8))
    emit('DB3a cma src_phys=0x%08X dst_phys=0x%08X size=%d'
         % (src.phys, dst.phys, BUF_SZ))

    def do_xfer(n, label, seed):
        pat = dma_pattern(n, seed)
        src.buf[:n] = np.frombuffer(pat, dtype=np.uint8)
        dst.buf[:] = 0xA5
        okc, mx, sx = dma_xfer(d, src, dst, n)
        okb = dma_compare(dst, pat, n, label)
        emit('%s n=%d MM2S_DMASR=%08X S2MM_DMASR=%08X cmp=%s'
             % (label, n, mx, sx, 'OK' if okb else 'BAD'))
        return okc and okb

    results['DB3'] = do_xfer(4096, 'DB3 basic4096', 0xB20000 + 4096)
    if not results['DB3']:
        emit('CKz BOARD_B2_FAIL dma_basic'); return 1

    ok4 = True
    for n in (137, 1, 1000, 8192):
        if not do_xfer(n, 'DB4 sweep', 0xB20000 + n):
            ok4 = False
    results['DB4'] = ok4
    emit('DB4 size_sweep 137/1/1000/8192 -> %s'
         % ('PASS' if ok4 else 'FAIL'))
    if not results['DB4']:
        emit('CKz BOARD_B2_FAIL dma_sweep'); return 1

    ok5 = True
    for i in range(3):
        if not do_xfer(4096, 'DB5 b2b%d' % i, 0xB21000 + i):
            ok5 = False
    results['DB5'] = ok5
    emit('DB5 back_to_back x3 -> %s' % ('PASS' if ok5 else 'FAIL'))
    if not results['DB5']:
        emit('CKz BOARD_B2_FAIL dma_b2b'); return 1

    # DB6: stop + soft reset hygiene
    d.write(D_MM2S_DMACR, 0)
    d.write(D_S2MM_DMACR, 0)
    t0 = time.time()
    while time.time() - t0 < 2:
        ms = d.read(D_MM2S_DMASR); ss = d.read(D_S2MM_DMASR)
        if (ms & B_HALTED) and (ss & B_HALTED):
            break
        time.sleep(0.001)
    halted = (ms & B_HALTED) and (ss & B_HALTED)
    d.write(D_MM2S_DMACR, B_DMARESET)
    d.write(D_S2MM_DMACR, B_DMARESET)
    time.sleep(0.1)
    mc, sc = d.read(D_MM2S_DMACR), d.read(D_S2MM_DMACR)
    ms6, ss6 = d.read(D_MM2S_DMASR), d.read(D_S2MM_DMASR)
    results['DB6'] = halted and not (mc & B_RS) and not (sc & B_RS) and \
        (ms6 & B_HALTED) and (ss6 & B_HALTED)
    emit('DB6 stop_reset halted=%d post_rst DMACR=%08X/%08X DMASR=%08X/%08X '
         '-> %s' % (halted, mc, sc, ms6, ss6,
                    'PASS' if results['DB6'] else 'FAIL'))
    if not results['DB6']:
        emit('CKz BOARD_B2_FAIL dma_reset'); return 1

    # DB7: cross-liveness - DMA recovery xfer + GEMM full S1 rerun (new seed)
    d.write(D_MM2S_DMACR, B_RS)
    d.write(D_S2MM_DMACR, B_RS)
    t0 = time.time()
    while time.time() - t0 < 2:
        ms = d.read(D_MM2S_DMASR); ss = d.read(D_S2MM_DMASR)
        if not (ms & B_HALTED) and not (ss & B_HALTED):
            break
        time.sleep(0.001)
    ok7 = do_xfer(256, 'DB7 dma_recovery256', 0xB70000)
    emit('DB7a dma_recovery -> %s' % ('PASS' if ok7 else 'FAIL'))
    gid7 = rd(g, A_ID)
    ok7g = (gid7 == EXP_GEMM_ID) and gemm_s1(g, lut_exp, 0x7E11, 'DB7b S1_rerun')
    results['DB7'] = ok7 and ok7g
    if not results['DB7']:
        emit('CKz BOARD_B2_FAIL cross_liveness'); return 1

    emit('CKz totals wop=%d rop=%d rb_ok=%d rb_bad=%d db_ok=%d db_bad=%d'
         % (counts['wop'], counts['rop'], counts['rb_ok'], counts['rb_bad'],
            counts['db_ok'], counts['db_bad']))
    ok = all(results.get(k) for k in
             ('CK1', 'CK4', 'CK5', 'CK6', 'CK7', 'CK8', 'CK9',
              'DB1', 'DB2', 'DB3', 'DB4', 'DB5', 'DB6', 'DB7'))
    emit('CKz %s' % ('BOARD_B2_PASS' if ok else 'BOARD_B2_FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
