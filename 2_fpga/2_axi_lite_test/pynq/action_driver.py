"""ACTL v1 MMIO driver: one outstanding command, explicit completion/ACK."""
import time
from action_protocol import uart_frame

IP_ID = 0x4143544C
REG = dict(IP_ID=0x00, ABI_VERSION=0x04, CAPS=0x08, SCRATCH=0x0C,
           ACTION_CODE=0x10, CMD_SEQ=0x14, CONTROL=0x18, STATUS=0x1C,
           ACCEPT_SEQ=0x20, DONE_SEQ=0x24, LAST_ACTION=0x28, ERROR_CODE=0x2C,
           EXEC_COUNT=0x30, LAST_FRAME=0x34, OUTPUT_STATUS=0x38, FRAME_COUNT=0x3C)


class ActionDriver:
    def __init__(self, io, clock=time.monotonic):
        self.io, self.clock = io, clock
        self.pending = None
        self.failed = False
        if (self.read("IP_ID") != IP_ID or self.read("ABI_VERSION") != 0x10000
                or self.read("CAPS") != 7):
            raise RuntimeError("Expected ACTL v1 COM4/LED hardware")

    @classmethod
    def from_overlay(cls, overlay, library, ip_name="axi_action_0"):
        from pynq import MMIO
        from axilt import OrderedMMIO
        desc = overlay.ip_dict[ip_name]
        if int(desc["addr_range"]) != 4096:
            raise RuntimeError("CSR aperture must be 4 KiB")
        return cls(OrderedMMIO(MMIO(desc["phys_addr"], desc["addr_range"]), library))

    def read(self, name):
        return self.io.read(REG[name])

    def status(self):
        return dict(status=self.read("STATUS"), accept_seq=self.read("ACCEPT_SEQ"),
                    done_seq=self.read("DONE_SEQ"), action=self.read("LAST_ACTION"),
                    count=self.read("EXEC_COUNT"), failed=self.failed)

    def begin(self, seq, action, timeout=1.0):
        uart_frame(seq, action)
        if self.failed or self.pending is not None:
            raise RuntimeError("Driver failed or command pending")
        if not 0 < timeout <= 10:
            raise ValueError("Timeout out of range")
        state = self.status()
        if state["status"] != 1:
            raise RuntimeError("PL not READY")
        if seq <= state["accept_seq"]:
            raise ValueError("Sequence must increase")
        self.io.write(REG["ACTION_CODE"], action)
        self.io.write(REG["CMD_SEQ"], seq)
        self.failed = True  # An exception during START makes outcome uncertain.
        self.io.write(REG["CONTROL"], 1)
        self.pending = dict(seq=seq, action=action, count=state["count"],
                            deadline=self.clock()+timeout)
        self.failed = False

    def poll(self):
        if self.failed:
            raise RuntimeError("Previous command outcome uncertain")
        if self.pending is None:
            return None
        p = self.pending
        try:
            status = self.read("STATUS")
            if not status & 4:
                if self.clock() >= p["deadline"]:
                    raise TimeoutError("PL command timeout; do not resubmit")
                return None
            frame = uart_frame(p["seq"], p["action"])
            signature = int.from_bytes(bytes((frame[3], frame[2], frame[4], 0)), "little")
            expected_count = (p["count"]+1) & 0xFFFFFFFF
            required = dict(ACCEPT_SEQ=p["seq"], DONE_SEQ=p["seq"],
                            LAST_ACTION=p["action"], ERROR_CODE=0,
                            EXEC_COUNT=expected_count, FRAME_COUNT=expected_count,
                            LAST_FRAME=signature, OUTPUT_STATUS=1)
            observed = {key: self.read(key) for key in required}
            if status != 4 or observed != required:
                raise RuntimeError("ACTL completion mismatch: " + repr(observed))
            self.io.write(REG["CONTROL"], 2)
            if self.read("STATUS") != 1:
                raise RuntimeError("ACK failed to restore READY")
            self.pending = None
            return dict(seq=p["seq"], action=p["action"], done_seq=p["seq"],
                        count=expected_count, uart_hex=frame.hex())
        except Exception:
            self.failed = True
            raise

    def execute(self, seq, action, timeout=1.0):
        self.begin(seq, action, timeout)
        while True:
            result = self.poll()
            if result is not None:
                return result
            time.sleep(.0005)
