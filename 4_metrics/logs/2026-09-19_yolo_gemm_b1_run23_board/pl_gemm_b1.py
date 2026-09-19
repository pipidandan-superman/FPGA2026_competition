#!/usr/bin/env python3
"""pl_gemm_b1.py - B1 GEMM board gate: overlay load + golden tiles S1/S2/S3.

Maps 1:1 to zynq-pynq-overlay-workflow canon (CK1-CK4 load gates, staged)
plus the run21 TB canonical register sequences with an independent Python
oracle (INT64 accumulate + C-truncation div + floor fix + RNE ties-even +
saturate +/-127/-128 + LUT / linear bypass).  Register sequence is the
tb_yolo_gemm_top_axi.sv canon; stimulus is freshly drawn here with the
same distribution discipline (deterministic seeds); golden values come
from the oracle only, never from the DUT.

Gates:
  CK1 HWH contract : u_yolo_gemm @0x43c00000/64K, u_yolo_csr @0x43c10000
  CK2 download     : root + XILINX_XRT=/usr
  CK3 liveness     : fpga0 state == operating
  CK4 fresh load   : dmesg zocl 'locked, ref=1' delta == +1
  CK5 identity     : fork-protected first GEMM read (run06 discipline),
                     then GEMM ID==0x20260919, CSR ID==0x594F4C32 V==0x0300
  CK6 S1  full 8x16 K=64 act=1 (LUT i^A5): 128/128 readback + y_count=128
  CK7 S2  masked 0x5A/0x0F0F K=40 act=0  : 32/32 readback + y_count=32
                     + phantom-slot stale check (addr0 keeps S1 value)
  CK8 S3  two-block K=96 ping-pong grp0/grp1 (concurrent grp1 load):
                     128/128 readback + y_count=128
  CK9 soft_rst hygiene: STATUS==0, YSTAT==0, ID preserved
  CK10 verdict     : BOARD_B1_PASS only if every gate passed

Dual-channel logging: stdout (host tee) + /dev/console (COM6 survives a
mid-run freeze).  Usage (root): python3 pl_gemm_b1.py <tag>
"""
import os, sys, time, hashlib, subprocess, random, select

HERE = os.path.dirname(os.path.abspath(__file__))
BIT = os.path.join(HERE, 'display_test_wrapper.bit')
tag = sys.argv[1] if len(sys.argv) > 1 else 'b1'

GEMM_BASE, CSR_BASE = 0x43C00000, 0x43C10000
EXP_GEMM_ID = 0x20260919
EXP_CSR_ID, EXP_CSR_VER = 0x594F4C32, 0x0300

# ---- yolo_gemm_top.v V1.0 register map (byte offsets) ----
A_ID, A_CTRL, A_STATUS = 0x00, 0x04, 0x08
A_GEOM, A_ROWVAL, A_NMASK, A_JOBCFG, A_LDGRP = 0x0C, 0x10, 0x14, 0x18, 0x1C
A_P_BIAS, A_P_M, A_P_SH, A_PCTL = 0x20, 0x24, 0x28, 0x2C
A_WDATA, A_WDATA2, A_WCTL = 0x30, 0x34, 0x38
A_LDSTAT, A_LDLEN, A_LUTD = 0x3C, 0x40, 0x44
A_YSTAT, A_YADDR, A_YDATA = 0x48, 0x4C, 0x50

P_TO, P_TN = 8, 16
CB = [-128, -1, 0, 1, 127, -128]           # TB corner-value table

results = {}
counts = {'wop': 0, 'rop': 0, 'rb_ok': 0, 'rb_bad': 0}


def emit(m):
    line = '[%s %s %s]' % (tag, m, time.strftime('%H:%M:%S'))
    print(line, flush=True)
    try:
        with open('/dev/console', 'a') as c:
            c.write(line + '\n'); c.flush()
    except Exception as e:
        print('[console-fail %r]' % e, flush=True)


# ---------------- independent oracle (run15/run21 math, literal) ----------------
def sat_addr(q7):                          # {~q7[7], q7[6:0]} == q7+128
    return (q7 + 128) & 0xFF


def requant(acc, bias, m, s):
    p = (acc + bias) * m                   # |p| < 2^57: no INT64 wrap
    if s == 0:
        fl, rr = p, 0
    else:
        mod = 1 << s
        hh = mod >> 1
        fl = p // mod if p >= 0 else -((-p) // mod)   # C truncation
        if p < 0 and (p % mod) != 0:
            fl -= 1                                    # floor correction
        rr = p - fl * mod
    qn = fl + (1 if (rr > hh or (rr == hh and (fl & 1))) else 0)  # RNE even
    qn = 127 if qn > 127 else (-128 if qn < -128 else qn)
    return qn


# ---------------- stimulus (TB fill_wx / load_params discipline) ----------------
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
        PS[r] = 1 + rng.randrange(62)      # s=0 -> TB hh-X corner, skipped
        m.write(A_P_BIAS, PB[r] & 0xFFFFFFFF)
        m.write(A_P_M, PM[r] & 0xFFFFFFFF)
        m.write(A_P_SH, PS[r])
        m.write(A_PCTL, 0x100 | r)         # {8 we, 2:0 row}
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


# ---------------- canonical register sequences (TB literal) ----------------
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
    """One block: per k three beats (W / Xlo / Xhi-last), then combined
    ld_done + LDLEN completion audit (stronger than the sticky alone)."""
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
    for _ in range(4000):                  # PS-paced: completes in a few reads
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
    errs = (st >> 6) & 0xF                 # bank/proto/ld_pend/start
    return done, errs, st


def readback(m, eqm, lut_exp, act_exp, rvm, nmm):
    """Capture-RAM coordinate readback; YDATA has 1-cycle RAM latency so a
    STATUS read is inserted between YADDR and YDATA (>> 2 fabric cycles)."""
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


def main():
    emit('CK0a start bit_sha=%s'
         % hashlib.sha256(open(BIT, 'rb').read()).hexdigest()[:16])
    os.environ['XILINX_XRT'] = '/usr'
    from pynq import Overlay, MMIO

    # ---- CK1: HWH contract (no download yet) ----
    ol = Overlay(BIT, download=False)
    ips = sorted(ol.ip_dict.keys())
    emit('CK1a ip_dict=%s' % ips)
    gp = ol.ip_dict.get('u_yolo_gemm', {}).get('phys_addr')
    gr = ol.ip_dict.get('u_yolo_gemm', {}).get('addr_range')
    cp = ol.ip_dict.get('u_yolo_csr', {}).get('phys_addr')
    results['CK1'] = (gp == GEMM_BASE) and (cp == CSR_BASE)
    emit('CK1b gemm phys=%s range=%s csr phys=%s -> %s'
         % (hex(gp) if gp is not None else None, gr,
            hex(cp) if cp is not None else None,
            'PASS' if results['CK1'] else 'FAIL'))
    if not results['CK1']:
        emit('CK10 BOARD_B1_FAIL hwh_contract'); return 1

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
        emit('CK10 BOARD_B1_FAIL load'); return 1

    g = MMIO(GEMM_BASE, 0x10000)
    c = MMIO(CSR_BASE, 0x10000)

    # ---- CK5: fork-protected first GEMM read, then identities ----
    emit('CK5a sacrificial_first_read_begin')
    r_pipe, w_pipe = os.pipe()
    pid = os.fork()
    if pid == 0:                           # child: the one risky read
        try:
            v = g.read(0x00)
            os.write(w_pipe, b'OK %08X' % v)
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
    emit('CK5b first_read=%s' % msg)
    if not msg.startswith('OK'):
        emit('CK10 BOARD_B1_FAIL first_read'); return 1
    gid = rd(g, A_ID)
    yst0 = rd(g, A_YSTAT)
    cid, cver = rd(c, 0x000), rd(c, 0x004)
    emit('CK5c GEMM_ID=0x%08X YSTAT=0x%08X CSR_ID=0x%08X CSR_VER=0x%08X'
         % (gid, yst0, cid, cver))
    results['CK5'] = (gid == EXP_GEMM_ID) and (cid == EXP_CSR_ID) \
        and (cver == EXP_CSR_VER)
    emit('CK5d identity -> %s' % ('PASS' if results['CK5'] else 'FAIL'))
    if not results['CK5']:
        emit('CK10 BOARD_B1_FAIL identity'); return 1

    lut_exp = [(i ^ 0xA5) & 0xFF for i in range(256)]

    # ================= CK6: S1 full 8x16 K=64 act=1 =================
    emit('CK6a S1_begin lut_preload')
    for i in range(256):
        wr(g, A_LUTD, (i << 8) | lut_exp[i])
    rng = random.Random(0x5119)            # fresh deterministic stream
    Wm, Xm = fill_wx(64, rng)
    PB, PM, PS = load_params(g, rng)
    eqm_s1 = push_expected(64, Wm, Xm, PB, PM, PS, 0xFF, 0xFFFF)
    wr(g, A_ROWVAL, 0xFF); wr(g, A_NMASK, 0xFFFF)
    emit('CK6b S1 bank_load begin')
    if not bank_load(g, Wm, Xm, 64, 0, 0):
        emit('CK10 BOARD_B1_FAIL s1_load'); return 1
    emit('CK6c S1 job begin')
    done, errs, st = run_job(g, 64, 1, 1, 1, 0, 0)
    if not done or errs:
        emit('CK6d S1 job done=%d errs=%X STATUS=%08X' % (done, errs, st))
    bad = readback(g, eqm_s1, lut_exp, True, 0xFF, 0xFFFF)
    yst = rd(g, A_YSTAT)
    ycnt = yst & 0xFFFF
    ok6 = done and errs == 0 and not bad and counts['rb_bad'] == 0 and ycnt == 128
    emit('CK6e S1 rb=%d bad=%d y_count=%d STATUS=%08X %s'
         % (counts['rb_ok'], counts['rb_bad'], ycnt, st,
            'PASS' if ok6 else 'FAIL'))
    if bad:
        emit('CK6f S1 first mismatches %s' % bad)
    results['CK6'] = ok6
    if not ok6:
        emit('CK10 BOARD_B1_FAIL s1'); return 1

    # ================= CK7: S2 masked 0x5A/0x0F0F K=40 act=0 =================
    rb0 = counts['rb_ok']; bad0 = counts['rb_bad']
    emit('CK7a S2_begin')
    rng = random.Random(0x2240)
    Wm2, Xm2 = fill_wx(40, rng)
    PB2, PM2, PS2 = load_params(g, rng)
    eqm_s2 = push_expected(40, Wm2, Xm2, PB2, PM2, PS2, 0x5A, 0x0F0F)
    wr(g, A_ROWVAL, 0x5A); wr(g, A_NMASK, 0x0F0F)
    if not bank_load(g, Wm2, Xm2, 40, 0, 1):
        emit('CK10 BOARD_B1_FAIL s2_load'); return 1
    done, errs, st = run_job(g, 40, 0, 1, 1, 1, 1)
    if not done or errs:
        emit('CK7b S2 job done=%d errs=%X STATUS=%08X' % (done, errs, st))
    bad = readback(g, eqm_s2, lut_exp, False, 0x5A, 0x0F0F)
    # phantom-slot check: addr 0 (r=0 masked out) keeps the S1 value
    wr(g, A_YADDR, 0)
    rd(g, A_STATUS)
    stale_got = rd(g, A_YDATA) & 0xFF
    stale_exp = lut_exp[sat_addr(eqm_s1[0][0])]
    yst = rd(g, A_YSTAT)
    ycnt = yst & 0xFFFF
    ok7 = (done and errs == 0 and not bad and
           counts['rb_ok'] - rb0 == 32 and counts['rb_bad'] == bad0 and
           stale_got == stale_exp and ycnt == 32)
    emit('CK7c S2 rb+=%d bad+=%d stale@0 got=%02X exp=%02X y_count=%d %s'
         % (counts['rb_ok'] - rb0, counts['rb_bad'] - bad0,
            stale_got, stale_exp, ycnt, 'PASS' if ok7 else 'FAIL'))
    if bad:
        emit('CK7d S2 first mismatches %s' % bad)
    results['CK7'] = ok7
    if not ok7:
        emit('CK10 BOARD_B1_FAIL s2'); return 1

    # ================= CK8: S3 two-block K=96 ping-pong =================
    rb0 = counts['rb_ok']; bad0 = counts['rb_bad']
    emit('CK8a S3_begin')
    rng = random.Random(0x3396)
    Wm3, Xm3 = fill_wx(96, rng)
    PB3, PM3, PS3 = load_params(g, rng)
    eqm_s3 = push_expected(96, Wm3, Xm3, PB3, PM3, PS3, 0xFF, 0xFFFF)
    wr(g, A_ROWVAL, 0xFF); wr(g, A_NMASK, 0xFFFF)
    if not bank_load(g, Wm3, Xm3, 48, 0, 0):
        emit('CK10 BOARD_B1_FAIL s3_load0'); return 1
    wr(g, A_GEOM, 48)
    wr(g, A_JOBCFG, 0x3)                   # act|first, grp0
    wr(g, A_CTRL, 1)
    t0 = time.time()                       # wait job_pend clear (feeder took it)
    while time.time() - t0 < 10:
        if (rd(g, A_STATUS) & 0x2) == 0:
            break
    emit('CK8b S3 blk0 queued, grp1 concurrent load begin')
    if not bank_load(g, Wm3, Xm3, 48, 48, 1):
        emit('CK10 BOARD_B1_FAIL s3_load1'); return 1
    done, errs, st = run_job(g, 48, 1, 0, 1, 1, 1)   # last block, grp1
    if not done or errs:
        emit('CK8c S3 job done=%d errs=%X STATUS=%08X' % (done, errs, st))
    bad = readback(g, eqm_s3, lut_exp, True, 0xFF, 0xFFFF)
    yst = rd(g, A_YSTAT)
    ycnt = yst & 0xFFFF
    ok8 = (done and errs == 0 and not bad and
           counts['rb_ok'] - rb0 == 128 and counts['rb_bad'] == bad0 and
           ycnt == 128)
    emit('CK8d S3 rb+=%d bad+=%d y_count=%d STATUS=%08X %s'
         % (counts['rb_ok'] - rb0, counts['rb_bad'] - bad0, ycnt, st,
            'PASS' if ok8 else 'FAIL'))
    if bad:
        emit('CK8e S3 first mismatches %s' % bad)
    results['CK8'] = ok8
    if not ok8:
        emit('CK10 BOARD_B1_FAIL s3'); return 1

    # ================= CK9: soft_rst hygiene =================
    wr(g, A_CTRL, 2)
    rd(g, A_STATUS)                        # spacing
    st9, yst9, gid9 = rd(g, A_STATUS), rd(g, A_YSTAT), rd(g, A_ID)
    results['CK9'] = (st9 == 0) and ((yst9 & 0xFFFF) == 0) \
        and (gid9 == EXP_GEMM_ID)
    emit('CK9 soft_rst STATUS=%08X y_count=%d ID=%08X -> %s'
         % (st9, yst9 & 0xFFFF, gid9,
            'PASS' if results['CK9'] else 'FAIL'))

    emit('CKz totals wop=%d rop=%d rb_ok=%d rb_bad=%d'
         % (counts['wop'], counts['rop'], counts['rb_ok'], counts['rb_bad']))
    ok = all(results.get(k) for k in
             ('CK1', 'CK4', 'CK5', 'CK6', 'CK7', 'CK8', 'CK9'))
    emit('CK10 %s' % ('BOARD_B1_PASS' if ok else 'BOARD_B1_FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
