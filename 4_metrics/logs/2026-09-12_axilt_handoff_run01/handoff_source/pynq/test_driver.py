import unittest
from axilt import Axilt, IP_ID, ABI_VERSION, REG


class FakeIO:
    def __init__(self):
        self.regs = {offset: 0 for offset in REG.values()}
        self.regs.update({REG["IP_ID"]: IP_ID, REG["ABI_VERSION"]: ABI_VERSION,
                          REG["CAPS"]: 1, REG["STATUS"]: 1})
        self.writes = []
        self.stuck = False
        self.corrupt = False

    def read(self, offset):
        return self.regs[offset]

    def write(self, offset, value):
        self.writes.append((offset, value))
        self.regs[offset] = value
        if offset == REG["ACTION"] and value == 1:
            self.regs[REG["ACCEPT_SEQ"]] = self.regs[REG["CMD_SEQ"]]
            self.regs[REG["STATUS"]] = 2
            if not self.stuck:
                self.regs[REG["DONE_SEQ"]] = self.regs[REG["CMD_SEQ"]]
                self.regs[REG["TEST_RESULT"]] = self.regs[REG["TEST_INPUT"]] ^ 0xFFFFFFFF
                self.regs[REG["EXEC_COUNT"]] += 1
                self.regs[REG["STATUS"]] = 4
                if self.corrupt:
                    self.regs[REG["TEST_RESULT"]] ^= 1
        if offset == REG["ACTION"] and value == 2:
            self.regs[REG["STATUS"]] = 1


class DriverTests(unittest.TestCase):
    def test_command_and_ack(self):
        io = FakeIO()
        driver = Axilt(io)
        for value in (0, 1, 0xFFFFFFFF, 0x12345678):
            self.assertEqual(driver.execute(value)["result"], value ^ 0xFFFFFFFF)
        self.assertEqual(io.regs[REG["EXEC_COUNT"]], 4)

    def test_duplicate_rejected_before_write(self):
        io = FakeIO()
        driver = Axilt(io)
        driver.execute(7, seq=1)
        before = list(io.writes)
        with self.assertRaises(ValueError):
            driver.execute(7, seq=1)
        self.assertEqual(before, io.writes)

    def test_wrap_rejected(self):
        io = FakeIO()
        io.regs[REG["ACCEPT_SEQ"]] = 0xFFFFFFFF
        with self.assertRaises(ValueError):
            Axilt(io).execute(0)
        self.assertFalse(io.writes)

    def test_busy_or_old_result(self):
        for status in (2, 4):
            io = FakeIO()
            io.regs[REG["STATUS"]] = status
            with self.assertRaises(RuntimeError):
                Axilt(io).execute(0)
            self.assertFalse(io.writes)

    def test_timeout_no_retry(self):
        io = FakeIO()
        io.stuck = True
        driver = Axilt(io)
        with self.assertRaises(TimeoutError):
            driver.execute(0, timeout=0.001)
        before = list(io.writes)
        with self.assertRaises(RuntimeError):
            driver.execute(0)
        self.assertEqual(before, io.writes)

    def test_corrupt_result_not_acknowledged(self):
        io = FakeIO()
        io.corrupt = True
        with self.assertRaises(RuntimeError):
            Axilt(io).execute(0)
        self.assertNotIn((REG["ACTION"], 2), io.writes)

    def test_wrong_hardware(self):
        for name in ("IP_ID", "ABI_VERSION", "CAPS"):
            io = FakeIO()
            io.regs[REG[name]] = 0
            with self.assertRaises(RuntimeError):
                Axilt(io)

    def test_invalid_data(self):
        io = FakeIO()
        driver = Axilt(io)
        for value in (-1, 0x100000000, True, 1.5):
            with self.assertRaises(ValueError):
                driver.execute(value)
        self.assertFalse(io.writes)


if __name__ == "__main__":
    unittest.main()

