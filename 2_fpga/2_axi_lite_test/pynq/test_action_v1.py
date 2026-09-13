"""Offline behavioral contracts, real UDP loopback and frame-decision cases."""
import random
import socket
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "3_host/model_env"))
from stable_action import StableAction
from action_link import ActionClient, ActionPublisher
from action_protocol import *
from action_driver import ActionDriver, REG, IP_ID
from action_service import ActionService


class ModelIO:
    """Independent time-stepped register/peripheral model for driver failures."""
    def __init__(self):
        self.regs = {offset: 0 for offset in REG.values()}
        self.regs.update({0: IP_ID, 4: 0x10000, 8: 7, 0x1C: 1, 0x38: 1})
        self.starts = 0
        self.remaining = 0
        self.hang = False
        self.corrupt = False

    def read(self, offset):
        if offset == REG["STATUS"] and self.remaining and not self.hang:
            self.remaining -= 1
            if self.remaining == 0:
                seq, action = self.regs[0x14], self.regs[0x10]
                raw = uart_frame(seq, action)
                self.regs.update({0x1C: 4, 0x24: seq, 0x28: action,
                                  0x30: self.starts, 0x3C: self.starts,
                                  0x34: action | (raw[2]<<8) | (raw[4]<<16)})
                if self.corrupt:
                    self.regs[0x28] ^= 1
        return self.regs[offset]

    def write(self, offset, value):
        if offset == 0x18:
            if value == 1:
                self.starts += 1
                self.regs[0x20] = self.regs[0x14]
                self.regs[0x1C] = 2
                self.remaining = 4
            elif value == 2:
                self.regs[0x1C] = 1
        else:
            self.regs[offset] = value


class StableTests(unittest.TestCase):
    def row(self, gate, fid, label="Up", confidence=.9, now=None):
        now = fid * .2 if now is None else now
        return gate.feed(fid, now, now, [] if label is None else
                         [{"label": label, "confidence": confidence}])

    def test_three_distinct_frames_once(self):
        gate = StableAction()
        self.assertIsNone(self.row(gate, 1))
        for _ in range(100):
            self.assertIsNone(self.row(gate, 1))
        self.assertIsNone(self.row(gate, 2))
        self.assertEqual(self.row(gate, 3)["action"], 7)
        for i in range(4, 10):
            self.assertIsNone(self.row(gate, i))

    def test_invalid_breaks_streak(self):
        for invalid in (None, "Left", "Right", "unexpected"):
            gate = StableAction()
            self.row(gate, 1); self.row(gate, 2)
            self.assertIsNone(self.row(gate, 3, invalid))
            self.assertIsNone(self.row(gate, 4))
            self.assertIsNone(self.row(gate, 5))
            self.assertEqual(self.row(gate, 6)["action"], 7)

    def test_confidence_conflict_and_stale(self):
        gate = StableAction()
        self.row(gate, 1); self.row(gate, 2, confidence=.749)
        self.row(gate, 3)
        self.assertEqual(gate.streak, 1)
        gate.feed(4, .8, .8, [{"label": "Up", "confidence": .99},
                            {"label": "Stop", "confidence": .99}])
        self.assertEqual(gate.streak, 0)
        self.assertIsNone(gate.feed(5, 1, 2.1, [{"label": "Up", "confidence": .99}]))
        self.assertEqual(gate.streak, 0)
        self.assertIsNone(self.row(gate, 6, confidence=float("nan")))

    def test_clear_once_then_rearm(self):
        gate = StableAction()
        for i in range(1, 4): self.row(gate, i)
        self.assertIsNone(gate.tick(1.59))
        self.assertEqual(gate.tick(1.61)["action"], 0)
        self.assertIsNone(gate.tick(5))
        for i in range(6, 8): self.assertIsNone(self.row(gate, i, now=i))
        # Gaps of one second are not a continuous streak.
        self.assertEqual(gate.streak, 1)
        self.assertIsNone(self.row(gate, 9, now=7.2))
        self.assertEqual(self.row(gate, 10, now=7.4)["action"], 7)

    def test_new_label_needs_three_and_old_frame_ignored(self):
        gate = StableAction()
        for i in range(1,4): self.row(gate,i)
        self.assertIsNone(self.row(gate,4,"Stop"))
        self.assertIsNone(self.row(gate,2,"Stop"))
        self.assertIsNone(self.row(gate,5,"Stop"))
        self.assertEqual(self.row(gate,6,"Stop")["action"],4)


class ProtocolTests(unittest.TestCase):
    def test_known_crc(self):
        self.assertEqual(crc8(b"123456789"), 0xF4)
        self.assertEqual(crc8(b""), 0)

    def test_packets_and_stream_chunks(self):
        rng = random.Random(3312026)
        expected = [uart_frame(i, i%8) for i in range(1,1001)]
        raw = b"".join(expected)
        parser, actual = UartFrames(), []
        while raw:
            size = rng.randint(1,31)
            actual.extend(parser.feed(raw[:size])); raw = raw[size:]
        self.assertEqual(actual, expected)
        self.assertEqual((parser.errors, parser.discarded, len(parser.buffer)), (0,0,0))
        for i in range(1,1001):
            self.assertEqual(decode_command(command(i,i%8)), (1,i,i%8))
            self.assertEqual(decode_reply(reply(OK,i,i%8,i))["done_seq"],i)

    def test_corrupt_packet_rejected(self):
        good = command(1,7)
        for i in range(len(good)):
            bad = bytearray(good); bad[i] ^= 1
            with self.assertRaises(ValueError): decode_command(bad)
        for seq, action in ((0,1),(1,8),(1,-1),(-1,1)):
            with self.assertRaises(ValueError): command(seq,action)


class DriverTests(unittest.TestCase):
    def test_publisher_connection_failure_is_visible(self):
        from unittest.mock import patch
        rows=[]
        with patch("action_link.ActionClient", side_effect=OSError("network unavailable")):
            publisher=ActionPublisher(lambda kind,**fields:rows.append((kind,fields)))
            publisher.thread.join(2)
            self.assertFalse(publisher.thread.is_alive())
            self.assertIn("network unavailable", publisher.error)
            self.assertFalse(publisher.ready)
            self.assertEqual(rows[0][0],"ACTION_LINK_FAILED")
            publisher.close()

    def test_exact_completion_and_duplicate(self):
        io = ModelIO(); driver = ActionDriver(io)
        for seq in range(1,1001):
            out = driver.execute(seq,seq%8)
            self.assertEqual(out["count"],seq)
            with self.assertRaises(ValueError): driver.execute(seq,seq%8)
        self.assertEqual(io.starts,1000)

    def test_fail_closed_timeout_and_corruption(self):
        for mode in ("hang","corrupt"):
            io=ModelIO(); setattr(io,mode,True)
            driver=ActionDriver(io)
            with self.assertRaises((RuntimeError,TimeoutError)):
                driver.execute(1,4,timeout=.005)
            self.assertTrue(driver.failed)
            with self.assertRaises(RuntimeError): driver.execute(2,4)
            self.assertEqual(io.starts,1)

    def test_wrong_identity(self):
        io=ModelIO(); io.regs[0]=0x41584C54
        with self.assertRaises(RuntimeError): ActionDriver(io)

    def test_real_udp_idempotency(self):
        io=ModelIO()
        service=ActionService(ActionDriver(io),"127.0.0.1",lambda *a,**k:None,
                              ("127.0.0.1",0))
        service.start()
        client=ActionClient("127.0.0.1",service.socket.getsockname()[1])
        try:
            self.assertEqual(client.synchronize()["seq"],0)
            for i in range(1,33):
                self.assertEqual(client.execute(i%8)["seq"],i)
            before=io.starts
            client.sock.send(command(32,0))
            self.assertEqual(decode_reply(client.sock.recv(2048))["status"],DUPLICATE)
            client.sock.send(command(32,1))
            self.assertEqual(decode_reply(client.sock.recv(2048))["status"],BAD_SEQUENCE)
            self.assertEqual(io.starts,before)
        finally:
            client.close(); service.close()

    def test_inference_publisher_to_udp_service(self):
        io=ModelIO()
        rows=[]
        service=ActionService(ActionDriver(io),"127.0.0.1",lambda *a,**k:None,
                              ("127.0.0.1",0))
        service.start()
        publisher=ActionPublisher(lambda kind,**fields:rows.append((kind,fields)),
                                  "127.0.0.1",service.socket.getsockname()[1])
        def wait_for(predicate):
            deadline=time.monotonic()+2
            while not predicate() and time.monotonic()<deadline:
                time.sleep(.005)
            self.assertTrue(predicate(),repr(rows))
        try:
            wait_for(lambda:publisher.ready)
            self.assertEqual(io.starts,1) # Initial AXI CLEAR.
            for fid in range(1,4):
                # Windows monotonic timestamps can advance only every ~15 ms.
                # Model genuinely distinct arrivals; duplicate GUI rows below
                # must retain exactly the same arrival timestamp.
                time.sleep(.03)
                row=dict(fid=fid,arrival=time.monotonic(),
                         detections=[dict(label="Stop",confidence=.95)])
                publisher.feed(row)
                for _ in range(5): publisher.feed(row)
            wait_for(lambda:any(k=="ACTION_CONFIRMED" and d["action"]==4 for k,d in rows))
            self.assertEqual(io.starts,2)
            for fid in range(4,8):
                publisher.feed(dict(fid=fid,arrival=time.monotonic(),
                                    detections=[dict(label="Left",confidence=.99)]))
            wait_for(lambda:any(k=="ACTION_CONFIRMED" and d["action"]==0 for k,d in rows))
            self.assertEqual(io.starts,3)
            self.assertIsNone(publisher.error)
        finally:
            publisher.close();service.close()
        self.assertEqual(io.starts,4) # Close uses one final AXI CLEAR.


if __name__ == "__main__":
    unittest.main(verbosity=2)
