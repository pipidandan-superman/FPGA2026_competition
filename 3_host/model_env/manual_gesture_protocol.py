"""Camera-independent, explicitly gated repeated gesture checks."""
from collections import Counter


GESTURES = [
    ('Stop', '停止', '张开五指，掌心正对摄像头，整只手保持在画面内。'),
    ('Thumbs up', '拇指向上', '握拳，只伸出拇指并竖直向上；不要伸出食指。'),
    ('Thumbs Down', '拇指向下', '握拳，只伸出拇指并竖直向下。'),
    ('Up', '食指向上', '其余手指收起，只伸食指，指尖朝画面上方。'),
    ('Down', '食指向下', '其余手指收起，只伸食指，指尖朝画面下方。'),
    ('Left', '食指向左', '其余手指收起，只伸食指，指尖朝预览画面左边。'),
    ('Right', '食指向右', '其余手指收起，只伸食指，指尖朝预览画面右边。'),
    ('NO HAND', '无手', '双手完全移出摄像头画面，保持背景不变。'),
]


class ManualProtocol:
    def __init__(self, rounds=3, prepare_seconds=3.0, observe_seconds=5.0,
                 gestures=None, minimum_frames=30, minimum_streak=10):
        self.gestures = GESTURES if gestures is None else gestures
        self.minimum_frames = minimum_frames
        self.minimum_streak = minimum_streak
        self.rounds = rounds
        self.prepare_seconds = prepare_seconds
        self.observe_seconds = observe_seconds
        self.index = 0
        self.phase = 'READY'
        self.passed_rounds = 0
        self.deadline = None
        self.attempts = []
        self.accepted_items = []
        self.last_result = None
        self.frames = self.matches = self.streak = self.best_streak = 0
        self.labels = Counter()

    @property
    def gesture(self):
        return self.gestures[self.index]

    def press_space(self, now):
        if self.phase == 'ITEM_PASS':
            self.accepted_items.append(self.gesture[0])
            if self.index == len(self.gestures) - 1:
                self.phase = 'COMPLETE'
            else:
                self.index += 1
                self.passed_rounds = 0
                self.last_result = None
                self.phase = 'READY'
            return True
        if self.phase in ('READY', 'ROUND_PASS', 'ROUND_FAIL'):
            self.phase = 'PREPARE'
            self.deadline = now + self.prepare_seconds
            self.frames = self.matches = self.streak = self.best_streak = 0
            self.labels = Counter()
            return True
        return False

    def reset_item(self):
        self.passed_rounds = 0
        self.phase = 'READY'
        self.last_result = None
        self.deadline = None

    def tick(self, now, labels):
        if self.phase == 'PREPARE' and now >= self.deadline:
            self.phase = 'OBSERVE'
            self.deadline = now + self.observe_seconds
        if self.phase != 'OBSERVE':
            return None
        if now >= self.deadline:
            rate = self.matches / self.frames if self.frames else 0.0
            threshold = 0.98 if self.gesture[0] == 'NO HAND' else 0.90
            passed = self.frames >= self.minimum_frames and rate >= threshold and self.best_streak >= self.minimum_streak
            row = dict(label=self.gesture[0], attempt=len(self.attempts)+1,
                       frames=self.frames, matching_frames=self.matches,
                       match_rate=rate, required_rate=threshold,
                       longest_matching_streak=self.best_streak,
                       detected_labels=dict(self.labels), passed=passed)
            self.attempts.append(row)
            self.last_result = row
            self.passed_rounds = self.passed_rounds + 1 if passed else 0
            self.phase = ('ITEM_PASS' if self.passed_rounds >= self.rounds
                          else 'ROUND_PASS' if passed else 'ROUND_FAIL')
            return row
        labels = set(labels)
        correct = not labels if self.gesture[0] == 'NO HAND' else labels == {self.gesture[0]}
        self.frames += 1
        self.matches += int(correct)
        self.streak = self.streak + 1 if correct else 0
        self.best_streak = max(self.best_streak, self.streak)
        self.labels.update(labels)
        return None

    def snapshot(self):
        return dict(phase=self.phase, item_index=self.index, expected_label=self.gesture[0],
                    instruction=self.gesture[2], consecutive_passed_rounds=self.passed_rounds,
                    required_rounds=self.rounds, accepted_items=list(self.accepted_items),
                    attempts=list(self.attempts), last_result=self.last_result)
