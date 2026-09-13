import unittest
from gesture_viewer_core import TestSession, action_text


class ViewerTests(unittest.TestCase):
    def test_decisions(self):
        def d(label):
            return {'label': label, 'confidence': .9}
        self.assertEqual(action_text([d('Stop')])[1], 'Stop')
        for labels in [[], ['Left'], ['Right'], ['Left','Right'], ['Up','Thumbs up'], ['Stop','Left']]:
            self.assertEqual(action_text([d(x) for x in labels])[1], 'UNKNOWN')
        self.assertEqual(action_text([d('Stop')], True)[1], 'UNKNOWN')

    def test_no_automatic_progress(self):
        s = TestSession()
        for i in range(100):
            s.feed(i, i, i, {'Stop'})
        self.assertEqual(s.protocol.phase, 'READY')
        self.assertEqual(s.protocol.index, 0)

    def test_duplicate_old_frames(self):
        s = TestSession()
        s.press(10)
        s.feed(1, 9, 13, {'Stop'})
        self.assertEqual(s.protocol.frames, 0)
        s.feed(2, 13, 13, {'Stop'})
        for _ in range(20):
            s.feed(2, 13, 13, {'Stop'})
        self.assertEqual(s.protocol.frames, 1)

    def test_all_manual_rounds(self):
        s = TestSession()
        clock, fid = 0, 0
        for item in range(6):
            for rnd in range(3):
                s.press(clock)
                labels = set() if item == 5 else {s.protocol.gesture[0]}
                for i in range(26):
                    t = clock+3+i*.2
                    fid += 1
                    s.feed(fid, t, t, labels)
                self.assertTrue(s.protocol.last_result['passed'])
                clock += 10
            self.assertEqual(s.protocol.phase, 'ITEM_PASS')
            self.assertEqual(s.protocol.index, item)
            s.press(clock)
            clock += 1
        self.assertEqual(s.protocol.phase, 'COMPLETE')
        self.assertEqual(len(s.protocol.attempts), 18)

    def test_failure_stale_reset_preserves_history(self):
        s = TestSession()
        s.press(0)
        for i in range(26):
            s.feed(i, 3+i*.2, 3+i*.2, {'Thumbs up'})
        self.assertEqual(s.protocol.phase, 'ROUND_FAIL')
        self.assertFalse(s.protocol.last_result['passed'])
        s.invalidate()
        self.assertEqual(s.protocol.phase, 'READY')
        self.assertEqual(len(s.protocol.attempts), 1)
        self.assertEqual(s.protocol.passed_rounds, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
