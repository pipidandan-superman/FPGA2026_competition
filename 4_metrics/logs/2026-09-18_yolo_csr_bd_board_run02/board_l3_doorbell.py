#!/usr/bin/env python3
"""board_l3_doorbell.py - L3 doorbell frame flow, golden = TB T4 verbatim.

Mirrors tb_yolo_control_subsystem.sv T4 (lines 381-412) on real silicon:
  D1  prep     : DESC_BASE=0; write desc item0 word0=0x0301 (opcode=1,
                 valid, last), word14=0x000246FC (149100 B); readback both
  D2  arm      : DESC_CFG=0x80 (depth 128), DESC_TAIL=1, DOORBELL=1
  D3  start    : CTRL=0x5 (ENABLE+START_FRAME)  <- engine starts running
  D4  wait     : poll STATUS bit2 FRAME_DONE, 2 s deadline, fail on
                 ERROR_STATUS != 0
  D5  results  : RESULT_SEQ==1, HEAD_BYTES==0x246FC, RING_HEAD==1,
                 RESULT_STATUS==0x11 (valid+ps_owned)
  D6  ring win : RING_WIN+0x04==1 (w1 seq), +0x10==0x246FC (w4 bytes),
                 +0x28==0x11 (w10 flags)
  D7  consume  : RESULT_ACK=1 -> RING_TAIL==1, STATUS bit7 cleared,
                 DESC_HEAD==1, DESC_DONE_COUNT==1, ERROR_STATUS==0,
                 STATUS back to idle (bit0 set)
Dual-channel markers (stdout + /dev/console) around every write so a
freeze pins the exact step. Usage (root): python3 board_l3_doorbell.py <tag>
"""
import os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
BIT = os.path.join(HERE, 'display_test_wrapper.bit')
tag = sys.argv[1] if len(sys.argv) > 1 else 'l3'

CSR_BASE = 0x43C10000
A_CTRL, A_STATUS, A_ERROR_STATUS = 0x010, 0x014, 0x018
A_HEAD_BYTES, A_RESULT_SEQ = 0x04C, 0x054
A_RESULT_STATUS, A_RESULT_ACK = 0x05C, 0x060
A_RING_HEAD, A_RING_TAIL = 0x064, 0x068
A_DESC_CFG, A_DESC_BASE = 0x100, 0x104
A_DESC_HEAD, A_DESC_DONE_COUNT = 0x10C, 0x11C
A_DESC_TAIL, A_DESC_DOORBELL = 0x110, 0x114
A_DESC_WIN, A_RING_WIN = 0x1000, 0x6000

results = {}

def emit(m):
    line = '[%s %s %s]' % (tag, m, time.strftime('%H:%M:%S'))
    print(line, flush=True)
    try:
        with open('/dev/console', 'a') as c:
            c.write(line + '\n'); c.flush()
    except Exception as e:
        print('[console-fail %r]' % e, flush=True)

def rd(m, a):
    v = m.read(a)
    emit('  rd 0x%03X = 0x%08X' % (a, v))
    return v

def wr(m, a, v):
    emit('  wr 0x%03X <- 0x%08X begin' % (a, v))
    m.write(a, v)
    emit('  wr 0x%03X done' % a)

def main():
    emit('L3a start (no download here; overlay loaded by r2)')
    # PYNQ 3.0.1: standalone MMIO needs XILINX_XRT env + a device context
    # (Overlay(download=False) establishes it without touching the PL).
    os.environ['XILINX_XRT'] = '/usr'
    from pynq import Overlay, MMIO
    ol = Overlay(BIT, download=False)
    phys = ol.ip_dict.get('u_yolo_csr', {}).get('phys_addr')
    emit('L3b device_ctx ok phys=%s' % hex(phys) if phys else 'L3b device_ctx FAIL')
    if phys != CSR_BASE:
        emit('L9 BOARD_L3_FAIL device_ctx'); return 1
    m = MMIO(CSR_BASE, 0x10000)

    st = rd(m, A_STATUS)
    results['D0'] = ((st & 0x1) == 1) and (rd(m, A_ERROR_STATUS) == 0)
    emit('D0 pre-state idle+noerr -> %s' % ('PASS' if results['D0'] else 'FAIL'))
    if not results['D0']:
        emit('L9 BOARD_L3_FAIL prestate'); return 1

    # ---- D1: descriptor prep (T3-fed values, TB lines 349-357) ----
    emit('D1a desc_prep_begin')
    wr(m, A_DESC_BASE, 0x0)
    wr(m, A_DESC_WIN + 0x000, 0x00000301)   # item0 w0: opcode=1 valid last
    wr(m, A_DESC_WIN + 0x038, 0x000246FC)   # item0 w14: 149100 bytes
    rb0, rb14 = rd(m, A_DESC_WIN + 0x000), rd(m, A_DESC_WIN + 0x038)
    results['D1'] = (rb0 == 0x301) and (rb14 == 0x246FC)
    emit('D1b desc_readback w0=0x%08X w14=0x%08X -> %s'
         % (rb0, rb14, 'PASS' if results['D1'] else 'FAIL'))
    if not results['D1']:
        emit('L9 BOARD_L3_FAIL desc_prep'); return 1

    # ---- D2: arm queue (TB lines 384-386) ----
    emit('D2a arm_begin')
    wr(m, A_DESC_CFG, 0x80)      # depth 128
    wr(m, A_DESC_TAIL, 0x1)      # 1 item queued
    emit('D2b doorbell_write_begin')
    wr(m, A_DESC_DOORBELL, 0x1)  # commit
    emit('D2c doorbell_written')

    # ---- D3: start frame (TB line 387) ----
    emit('D3a ctrl_start_begin')
    wr(m, A_CTRL, 0x5)           # ENABLE + START_FRAME
    emit('D3b ctrl_start_written')

    # ---- D4: poll FRAME_DONE (TB line 388; 2 s board deadline) ----
    t0 = time.time(); got = False; st = 0
    while time.time() - t0 < 2.0:
        st = m.read(A_STATUS)
        if st & 0x4:
            got = True; break
        if m.read(A_ERROR_STATUS) != 0:
            break
    dt = (time.time() - t0) * 1000
    emit('D4 poll FRAME_DONE got=%s STATUS=0x%08X after %.1f ms' % (got, st, dt))
    results['D4'] = got
    if not got:
        emit('L9 BOARD_L3_FAIL frame_done_timeout'); return 1

    # ---- D5: result registers (TB lines 390-397) ----
    seq = rd(m, A_RESULT_SEQ);   hb = rd(m, A_HEAD_BYTES)
    rh  = rd(m, A_RING_HEAD);    rs = rd(m, A_RESULT_STATUS)
    results['D5'] = (seq == 1) and (hb == 0x246FC) and (rh == 1) and (rs == 0x11)
    emit('D5 seq=%d head_bytes=0x%X ring_head=%d result_status=0x%X -> %s'
         % (seq, hb, rh, rs, 'PASS' if results['D5'] else 'FAIL'))

    # ---- D6: ring window entry (TB lines 400-405) ----
    w1 = rd(m, A_RING_WIN + 0x04)
    w4 = rd(m, A_RING_WIN + 0x10)
    w10 = rd(m, A_RING_WIN + 0x28)
    results['D6'] = (w1 == 1) and (w4 == 0x246FC) and (w10 == 0x11)
    emit('D6 ring w1_seq=%d w4_bytes=0x%X w10_flags=0x%X -> %s'
         % (w1, w4, w10, 'PASS' if results['D6'] else 'FAIL'))

    # ---- D7: consume via ACK (TB lines 408-412) ----
    emit('D7a ack_write_begin')
    wr(m, A_RESULT_ACK, 0x1)
    rt = rd(m, A_RING_TAIL);  st2 = rd(m, A_STATUS)
    dh = rd(m, A_DESC_HEAD);  dc = rd(m, A_DESC_DONE_COUNT)
    es = rd(m, A_ERROR_STATUS)
    results['D7'] = (rt == 1) and ((st2 & 0x80) == 0) and (dh == 1) \
                    and (dc == 1) and (es == 0) and ((st2 & 0x1) == 1)
    emit('D7 ring_tail=%d status=0x%08X desc_head=%d done=%d err=0x%X -> %s'
         % (rt, st2, dh, dc, es, 'PASS' if results['D7'] else 'FAIL'))

    ok = all(results.get(k) for k in ('D0', 'D1', 'D4', 'D5', 'D6', 'D7'))
    emit('L9 %s' % ('BOARD_L3_PASS' if ok else 'BOARD_L3_FAIL'))
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main())
