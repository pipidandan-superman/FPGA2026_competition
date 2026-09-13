"""AXLT ABI 1.0 driver. Register stage only; no automatic command retry."""
import ctypes
import time
from pathlib import Path

IP_ID = 0x41584C54
ABI_VERSION = 0x00010000
REG = dict(IP_ID=0x00, ABI_VERSION=0x04, CAPS=0x08, SCRATCH=0x0C,
           TEST_INPUT=0x10, CMD_SEQ=0x14, ACTION=0x18, STATUS=0x1C,
           ACCEPT_SEQ=0x20, DONE_SEQ=0x24, TEST_RESULT=0x28,
           ERROR_CODE=0x2C, EXEC_COUNT=0x30)


class OrderedMMIO:
    def __init__(self, mmio, library):
        # MMIO's device mapping is kept alive. No normal-memory substitute.
        self.mmio = mmio
        self.lib = ctypes.CDLL(str(Path(library).resolve()))
        self.lib.axilt_read32.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        self.lib.axilt_read32.restype = ctypes.c_uint32
        self.lib.axilt_write32.argtypes = [ctypes.c_void_p, ctypes.c_uint32,
                                          ctypes.c_uint32]
        self.lib.axilt_write32.restype = None
        self.base = ctypes.c_void_p(mmio.array.ctypes.data)
        self.length = mmio.length

    def _check(self, offset):
        if type(offset) is not int or offset % 4 or not 0 <= offset <= self.length - 4:
            raise ValueError("Unaligned or out-of-window offset")

    def read(self, offset):
        self._check(offset)
        return int(self.lib.axilt_read32(self.base, offset))

    def write(self, offset, value):
        self._check(offset)
        if type(value) is not int or not 0 <= value <= 0xFFFFFFFF:
            raise ValueError("Expected unsigned 32-bit value")
        self.lib.axilt_write32(self.base, offset, value)


class Axilt:
    """Backend injection supports offline driver tests, not board acceptance."""
    def __init__(self, io):
        self.io = io
        if self.read("IP_ID") != IP_ID or self.read("ABI_VERSION") != ABI_VERSION:
            raise RuntimeError("Wrong IP identity or incompatible ABI")
        if self.read("CAPS") != 1:
            raise RuntimeError("This driver expects register-only hardware")
        self.failed = False

    @classmethod
    def from_overlay(cls, overlay, library, ip_name="axi_lite_test_0"):
        from pynq import MMIO
        desc = overlay.ip_dict[ip_name]
        size = int(desc["addr_range"])
        if size != 4096 or int(desc["phys_addr"]) % 4096:
            raise RuntimeError("Unexpected HWH CSR mapping")
        return cls(OrderedMMIO(MMIO(desc["phys_addr"], size), library))

    def read(self, name):
        return self.io.read(REG[name])

    def write(self, name, value):
        if name not in ("SCRATCH", "TEST_INPUT"):
            raise ValueError("Use the command API for transaction registers")
        if type(value) is not int or not 0 <= value <= 0xFFFFFFFF:
            raise ValueError("Expected unsigned 32-bit value")
        self.io.write(REG[name], value)

    def status(self):
        value = self.read("STATUS")
        return dict(ready=bool(value & 1), busy=bool(value & 2),
                    done=bool(value & 4), failed=self.failed,
                    accept_seq=self.read("ACCEPT_SEQ"), done_seq=self.read("DONE_SEQ"))

    def execute(self, value, seq=None, timeout=1.0):
        if self.failed:
            raise RuntimeError("Previous command uncertain; reload before further commands")
        if type(value) is not int or not 0 <= value <= 0xFFFFFFFF:
            raise ValueError("Expected unsigned 32-bit input")
        if not isinstance(timeout, (int, float)) or not 0 < timeout <= 60:
            raise ValueError("Timeout must be in (0,60] seconds")
        state = self.status()
        if not state["ready"] or state["busy"] or state["done"]:
            raise RuntimeError("Hardware not ready or old result unacknowledged")
        previous = state["accept_seq"]
        if seq is None:
            seq = previous + 1
        if type(seq) is not int or not previous < seq <= 0xFFFFFFFF:
            raise ValueError("Sequence must increase without wraparound")
        count = self.read("EXEC_COUNT")
        self.io.write(REG["TEST_INPUT"], value)
        self.io.write(REG["CMD_SEQ"], seq)
        # Mark uncertainty before the hardware side effect.
        self.failed = True
        self.io.write(REG["ACTION"], 1)
        deadline = time.monotonic() + timeout
        while True:
            status = self.read("STATUS")
            if status & 4:
                break
            if time.monotonic() >= deadline:
                raise TimeoutError("Command timed out; do not resubmit automatically")
            time.sleep(0.0005)
        result = self.read("TEST_RESULT")
        observed = dict(accept_seq=self.read("ACCEPT_SEQ"),
                        done_seq=self.read("DONE_SEQ"), error=self.read("ERROR_CODE"),
                        exec_count=self.read("EXEC_COUNT"))
        expected = (value ^ 0xFFFFFFFF)
        if (status & 2 or observed["accept_seq"] != seq or observed["done_seq"] != seq
                or observed["error"] or observed["exec_count"] != ((count + 1) & 0xFFFFFFFF)
                or result != expected):
            raise RuntimeError("Hardware result/sequence/count mismatch: " + repr(observed))
        self.io.write(REG["ACTION"], 2)
        if self.read("STATUS") != 1:
            raise RuntimeError("ACK did not restore READY")
        self.failed = False
        return dict(seq=seq, input=value, result=result, **observed)

