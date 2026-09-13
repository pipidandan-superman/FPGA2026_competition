#!/usr/bin/env python3
"""EES-331: existing OV5640/ADV7511 PL + Linux-owned VDMA buffers + OV56 UDP.

Run through run_camera.sh using PYNQ 3.0.1. The exact bit/HWH pair and the
VDMA configuration below come from the board-proven display_test XSA.
No Linux driver and this process may own the same VDMA simultaneously.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import struct
import time
import zlib

from main_hardware_contract import validate_main_hardware_contract

WIDTH, HEIGHT, STRIDE = 640, 480, 1920
FRAME_BYTES, SLOT_BYTES, SLOTS = 921600, 0x100000, 3
HEADER = struct.Struct('>4sBBHIHHHHHHII')
PAYLOAD, PACKETS = 1440, 640
ERROR_MASK = 0x8FF0  # Include EOLLateErr (bit 15) as well as the baseline errors.
MM2S_CONTROL, S2MM_CONTROL = 0x1008B, 0x180CB
SENSOR_SETTLE_SECONDS = 10.0
FIRST_FRAME_TIMEOUT_SECONDS = 30.0
FIRST_FRAME_PROGRESS_SECONDS = 1.0
BIT_HASH = '633e7846da5fbeda5c3554c25c255647114ca50d1b1d246dc8ce421c05d9a5d0'
HWH_HASH = '8f75976076d36ebdaee4f7af4f89f2a66b464241bf30c4cf5ddb73098a4beec0'
stopping = False


def log(event, **data):
    print(json.dumps(dict(event=event, monotonic=round(time.monotonic(), 6), **data)), flush=True)


def request_stop(signum, frame):
    global stopping
    stopping = True


def datagrams(frame, fid, timestamp):
    if len(frame) != FRAME_BYTES:
        raise ValueError('OV56 requires exactly 640x480x3 bytes')
    crc = zlib.crc32(frame) & 0xFFFFFFFF
    for pid in range(PACKETS):
        flags = (1 if pid == 0 else 0) | (2 if pid == PACKETS - 1 else 0)
        yield HEADER.pack(b'OV56', 1, 1, flags, fid & 0xFFFFFFFF, pid,
                          PACKETS, PAYLOAD, WIDTH, HEIGHT, STRIDE,
                          timestamp & 0xFFFFFFFF, crc) + frame[pid * PAYLOAD:(pid + 1) * PAYLOAD]


class Camera:
    def __init__(self, bit, expected_hashes=None,
                 contract_validator=validate_main_hardware_contract):
        from pynq import Overlay, MMIO, allocate
        self.buf = None
        self.mmio = None
        self.transitions = [0, 0]
        self.last_slots = [None, None]
        self.last_progress = [time.monotonic(), time.monotonic()]
        hashes = expected_hashes or {".bit": BIT_HASH, ".hwh": HWH_HASH}
        for path, expected in ((bit, hashes[".bit"]),
                               (bit.with_suffix('.hwh'), hashes[".hwh"])):
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            if actual != expected:
                raise RuntimeError(f'Unvalidated bit/HWH file: {path} {actual}')
        contract = contract_validator(bit.with_suffix('.hwh'))
        log('HARDWARE_CONTRACT', **contract)
        self.overlay = Overlay(str(bit), download=False)
        desc = self.overlay.ip_dict['axi_vdma_0']
        params = desc['parameters']
        required = {'C_NUM_FSTORES': 3, 'C_INCLUDE_SG': 0,
                    'C_M_AXIS_MM2S_TDATA_WIDTH': 24, 'C_S_AXIS_S2MM_TDATA_WIDTH': 24,
                    'C_MM2S_GENLOCK_MODE': 3, 'C_S2MM_GENLOCK_MODE': 2}
        for key, value in required.items():
            if int(params[key]) != value:
                raise RuntimeError(f'Unsupported VDMA parameter {key}={params[key]}')
        self.overlay.download()
        state = Path('/sys/class/fpga_manager/fpga0/state').read_text().strip()
        if state != 'operating':
            raise RuntimeError(f'FPGA manager state={state}')
        log('PL_LOADED', bit_sha256=hashes[".bit"], state=state, base=hex(desc['phys_addr']))
        self.mmio = MMIO(desc['phys_addr'], desc['addr_range'])
        # The bare-metal application initializes Ethernet before VDMA. After a
        # Linux hot reload that implicit sensor/SCCB settling time must be
        # explicit. This remains a timed diagnostic gate, not proof that SCCB,
        # PCLK or VSYNC are healthy.
        settle_started = time.monotonic()
        settle_deadline = settle_started + SENSOR_SETTLE_SECONDS
        next_report = settle_started + FIRST_FRAME_PROGRESS_SECONDS
        log('SENSOR_SETTLE_BEGIN', seconds=SENSOR_SETTLE_SECONDS,
            readiness='TIMED_WAIT_NOT_SENSOR_PROOF')
        while not stopping and time.monotonic() < settle_deadline:
            now = time.monotonic()
            if now >= next_report:
                log('SENSOR_SETTLE_PROGRESS',
                    elapsed=round(now - settle_started, 3),
                    remaining=round(max(0.0, settle_deadline - now), 3))
                next_report += FIRST_FRAME_PROGRESS_SECONDS
            time.sleep(min(.1, max(0.0, settle_deadline - now)))
        if stopping:
            raise RuntimeError('Stopped during sensor settle wait')
        log('SENSOR_SETTLE_COMPLETE', seconds=SENSOR_SETTLE_SECONDS,
            readiness='TIMED_WAIT_NOT_SENSOR_PROOF')
        self.reset()
        self.buf = allocate(shape=(SLOTS, SLOT_BYTES), dtype='u1')
        base = self.buf.device_address
        # Current crossbar exposes only 0..0x1fffffff; use the proven HP1 window.
        if not (0x10000000 <= base and base + self.buf.nbytes <= 0x20000000):
            self.buf.freebuffer()
            self.buf = None
            raise RuntimeError(f'CMA address {base:#x} is outside the proven HP1 DDR window; boot with cma=128M@0x10000000')
        self.buf[:] = 0
        self.buf.flush()
        log('BUFFER_ALLOCATED', address=hex(base), size=self.buf.nbytes, coherent=self.buf.coherent)

    def read(self, reg):
        return self.mmio.read(reg)

    def write(self, reg, value):
        self.mmio.write(reg, int(value))

    def reset(self):
        for reg in (0, 0x30):
            self.write(reg, 4)
            deadline = time.monotonic() + 2
            while self.read(reg) & 4:
                if time.monotonic() >= deadline:
                    raise RuntimeError(f'VDMA reset timeout {reg:#x}')
                time.sleep(.001)
            self.write(reg + 4, 0xFFF0)
        log('VDMA_RESET_OK')

    def slots(self):
        park = self.read(0x28)
        result = [(park >> 16) & 31, (park >> 24) & 31]
        if max(result) >= SLOTS:
            raise RuntimeError(f'Invalid VDMA park pointer {park:#x}')
        return result

    def status(self):
        now = time.monotonic()
        slots = self.slots()
        result = dict(mm2s_cr=hex(self.read(0)), mm2s_sr=hex(self.read(4)),
                      s2mm_cr=hex(self.read(0x30)), s2mm_sr=hex(self.read(0x34)), slots=slots)
        for i, reg in enumerate((0, 0x30)):
            if self.read(reg + 4) & ERROR_MASK or not self.read(reg) & 1:
                raise RuntimeError('VDMA_ERROR ' + json.dumps(result))
            if slots[i] != self.last_slots[i]:
                if self.last_slots[i] is not None:
                    self.transitions[i] += 1
                self.last_progress[i] = now
                self.last_slots[i] = slots[i]
            elif now - self.last_progress[i] > 2:
                raise RuntimeError('VDMA_STREAM_STALLED ' + json.dumps(result))
        return dict(result, observed_transitions=list(self.transitions))

    def start(self):
        base = self.buf.device_address
        # Keep the working main.c order, including VSIZE last on both channels.
        self.write(0x30, S2MM_CONTROL)
        for i in range(SLOTS):
            self.write(0xAC + 4 * i, base + i * SLOT_BYTES)
        self.write(0xA8, STRIDE)
        self.write(0xA4, STRIDE)
        self.write(0xA0, HEIGHT)
        for i in range(SLOTS):
            self.write(0x5C + 4 * i, base + i * SLOT_BYTES)
        self.write(0x58, STRIDE)
        self.write(0x54, STRIDE)
        self.write(0, MM2S_CONTROL)
        self.write(0x50, HEIGHT)
        for reg, expected in ((0, MM2S_CONTROL), (0x30, S2MM_CONTROL),
                              (0x50, HEIGHT), (0x54, STRIDE), (0x58, STRIDE),
                              (0xA0, HEIGHT), (0xA4, STRIDE), (0xA8, STRIDE)):
            if self.read(reg) != expected:
                raise RuntimeError(f'VDMA readback mismatch at {reg:#x}: {self.read(reg):#x} != {expected:#x}')
        initial = self.slots()
        seen = [False, False]
        wait_started = time.monotonic()
        deadline = wait_started + FIRST_FRAME_TIMEOUT_SECONDS
        next_report = wait_started
        # Match main.c: wait for MM2S first, then acknowledge startup camera
        # framing errors once. With repeat-on-error, waiting for S2MM to rotate
        # before acknowledging these errors can leave it repeating one slot.
        while not seen[0]:
            current_slots = self.slots()
            for i, current in enumerate(current_slots):
                seen[i] |= current != initial[i]
            now = time.monotonic()
            if now >= next_report:
                log('FIRST_FRAME_WAIT', elapsed=round(now - wait_started, 3),
                    timeout=FIRST_FRAME_TIMEOUT_SECONDS, initial=initial,
                    slots=current_slots, seen=seen,
                    mm2s_sr=hex(self.read(4)), s2mm_sr=hex(self.read(0x34)))
                next_report += FIRST_FRAME_PROGRESS_SECONDS
            if stopping or now > deadline:
                log('FIRST_FRAME_TIMEOUT', seen=seen, mm2s_sr=hex(self.read(4)),
                    s2mm_sr=hex(self.read(0x34)), mm2s_cr=hex(self.read(0)),
                    s2mm_cr=hex(self.read(0x30)), elapsed=round(now - wait_started, 3),
                    timeout=FIRST_FRAME_TIMEOUT_SECONDS)
                raise RuntimeError(f'No real frame transition: {seen}')
            time.sleep(.001)
        time.sleep(.1)
        if self.read(4) & ERROR_MASK or self.read(0x34) & 0x60:
            raise RuntimeError('Nonrecoverable startup VDMA error')
        # Log startup sticky bits explicitly before the one permitted clear.
        log('STARTUP_STATUS', mm2s_sr=hex(self.read(4)), s2mm_sr=hex(self.read(0x34)))
        self.write(4, 0xFFF0)
        self.write(0x34, 0xFFF0)
        self.last_progress = [time.monotonic(), time.monotonic()]
        # Require actual new read AND write transitions after the clear. Any
        # persistent framing error now fails; it is never repeatedly cleared.
        self.last_slots = self.slots()
        deadline = time.monotonic() + 2
        while not all(self.transitions):
            self.status()
            if stopping or time.monotonic() >= deadline:
                raise RuntimeError('No fresh capture/display frames after startup synchronization')
            time.sleep(.001)
        log('VDMA_STREAM_STARTED', **self.status())

    def snapshot(self):
        # Use the completed slot behind the writer. Reject any writer movement
        # during copying. The <10 ms bound rules out an unnoticed 3-slot wrap:
        # even active pixels alone require >12 ms at this design's pixel rate.
        started = time.monotonic()
        writer = self.slots()[1]
        slot = (writer + SLOTS - 1) % SLOTS
        view = self.buf[slot, :FRAME_BYTES]
        view.invalidate()
        frame = view.tobytes()
        elapsed = time.monotonic() - started
        if self.slots()[1] != writer or elapsed >= .010:
            return None
        return frame

    def close(self):
        if self.mmio is not None:
            for reg in (0, 0x30):
                self.write(reg, self.read(reg) & ~1)
            deadline = time.monotonic() + 2
            while not all(self.read(reg) & 1 for reg in (4, 0x34)):
                if time.monotonic() >= deadline:
                    self.reset()
                    break
                time.sleep(.001)
            if not all(self.read(reg) & 1 for reg in (4, 0x34)):
                # Do not let the kernel reclaim pages while PL can still DMA.
                log('FATAL_DMA_NOT_HALTED_BUFFER_RETAINED')
                while True:
                    time.sleep(1)
            log('VDMA_HALTED')
        if self.buf is not None:
            self.buf.freebuffer()
            self.buf = None
            log('BUFFER_FREED')


def main():
    import fcntl
    parser = argparse.ArgumentParser()
    parser.add_argument('--bit', type=Path, default=Path(__file__).with_name('overlay.bit'))
    parser.add_argument('--peer', default='192.168.240.2')
    parser.add_argument('--port', type=int, default=5000)
    parser.add_argument('--fps', type=float, default=5)
    parser.add_argument('--seconds', type=float, default=0, help='0 runs until SIGTERM/Ctrl-C')
    parser.add_argument('--no-udp', action='store_true')
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()
    if not 0 < args.fps <= 15 or args.seconds < 0:
        parser.error('fps must be in (0,15]; seconds must be nonnegative')
    if os.geteuid() != 0:
        parser.error('Use sudo with run_camera.sh')
    if args.evidence is None:
        boot_id = Path('/proc/sys/kernel/random/boot_id').read_text().strip()[:8]
        args.evidence = Path('/home/xilinx/ees331_camera/evidence') / f'{boot_id}_{int(time.monotonic()*1000)}'
    args.evidence.mkdir(parents=True, exist_ok=True)
    log('EVIDENCE_DIRECTORY', path=str(args.evidence))
    lock = open('/run/lock/ees331_camera.lock', 'w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    camera, sock = None, None
    result = dict(result='NOT_COMPLETED')
    try:
        camera = Camera(args.bit)
        camera.start()
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 2 * 1024 * 1024)
        sock.settimeout(1)
        started = last_report = next_send = time.monotonic()
        frames = packets = rejected = 0
        first_crc, changes = None, 0
        last_good = None
        last_frame_time = started
        while not stopping and (not args.seconds or time.monotonic() - started < args.seconds):
            status = camera.status()
            now = time.monotonic()
            if now >= next_send:
                frame = camera.snapshot()
                if frame is None:
                    rejected += 1
                else:
                    last_good = frame
                    crc = zlib.crc32(frame) & 0xFFFFFFFF
                    if frames == 0:
                        first_crc = crc
                        (args.evidence / 'first_frame.bgr').write_bytes(frame)
                    if crc != first_crc:
                        changes += 1
                    if not args.no_udp:
                        for pid, packet in enumerate(datagrams(frame, frames, int(now * 1e6))):
                            sock.sendto(packet, (args.peer, args.port))
                            packets += 1
                            if (pid + 1) % 16 == 0:
                                time.sleep(.001)
                    frames += 1
                    last_frame_time = time.monotonic()
                    next_send = max(next_send + 1 / args.fps, last_frame_time)
            if time.monotonic() - last_frame_time > 5:
                raise RuntimeError('No stable camera snapshot for 5 seconds')
            if now - last_report >= 2:
                log('HEARTBEAT', frames=frames, udp_packets=packets,
                    snapshot_rejected=rejected, changes_from_first=changes, **status)
                last_report = now
            time.sleep(.001)
        if frames:
            (args.evidence / 'last_frame.bgr').write_bytes(last_good)
        duration = time.monotonic() - started
        result = dict(result='CAPTURE_VDMA_RUN_COMPLETE', seconds=duration, frames=frames,
                      udp_packets=packets, fps=frames/duration, snapshot_rejected=rejected,
                      changes_from_first=changes, vdma=camera.status(),
                      hdmi_visual='REQUIRES_PHYSICAL_OBSERVATION', pc_receive='REQUIRES_RECEIVER_EVIDENCE')
        log('RUN_COMPLETE', **result)
    except Exception as exc:
        result = dict(result='FAIL', error=str(exc))
        log('FAIL', error=str(exc))
        raise
    finally:
        if camera is not None:
            camera.close()
        if sock is not None:
            sock.close()
        (args.evidence / 'result.json').write_text(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
