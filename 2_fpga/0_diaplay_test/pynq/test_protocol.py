"""Cross-check the Python sender against the existing unmodified PC decoder."""
import importlib.util
from pathlib import Path
import queue
import sys
import unittest

sys.dont_write_bytecode = True
import camera

viewer_path = Path(__file__).resolve().parents[3] / '3_host/udp_video/udp_video_gui.py'
spec = importlib.util.spec_from_file_location('existing_viewer', viewer_path)
viewer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(viewer)


class WireCompatibility(unittest.TestCase):
    def setUp(self):
        viewer.stats.clear()
        self.receiver = viewer.Receiver(5000, queue.Queue())
        self.frame = bytes((17, 83, 201)) * (640 * 480)  # B,G,R asymmetric channels
        self.packets = list(camera.datagrams(self.frame, 42, 123456))

    def test_existing_decoder_exact_frame_and_color_order(self):
        result = None
        self.assertEqual(len(self.packets), 640)
        for packet in self.packets:
            self.assertEqual(len(packet), 1472)
            result = self.receiver.feed(packet)
        self.assertEqual(result, self.frame)
        self.assertEqual(self.receiver.last_raw_mode, 'BGR')
        self.assertEqual(self.receiver.last_complete_fid, 42)
        self.assertEqual(viewer.stats['ok_frames'], 1)
        self.assertEqual(viewer.stats['crc_err'], 0)

    def test_corrupt_payload_not_displayed(self):
        packet = bytearray(self.packets[12])
        packet[70] ^= 1
        self.packets[12] = bytes(packet)
        for packet in self.packets:
            self.assertIsNone(self.receiver.feed(packet))
        self.assertEqual(viewer.stats['crc_err'], 1)
        self.assertEqual(viewer.stats['ok_frames'], 0)

    def test_incomplete_frame_not_displayed(self):
        for i, packet in enumerate(self.packets):
            if i != 10:
                self.assertIsNone(self.receiver.feed(packet))
        self.assertEqual(viewer.stats['ok_frames'], 0)


if __name__ == '__main__':
    unittest.main()
