"""UI-independent decisions and manually gated test sessions."""
from manual_gesture_protocol import GESTURES, ManualProtocol

SELECTED = [g for g in GESTURES if g[0] not in ('Left', 'Right')]
NAMES = {g[0]: g[1] for g in GESTURES}


def action_text(detections, stale=False):
    if stale:
        return '视频未到达 / 已中断', 'UNKNOWN'
    labels = {d['label'] for d in detections}
    if not labels:
        return '未检测到手势', 'UNKNOWN'
    if len(labels) != 1:
        return '识别冲突（不确定）', 'UNKNOWN'
    label = next(iter(labels))
    if label in ('Left', 'Right'):
        return '左右预测不可靠（不作为有效动作）', 'UNKNOWN'
    if label not in NAMES:
        return '未知类别', 'UNKNOWN'
    confidence = max(d['confidence'] for d in detections)
    return f'{NAMES[label]}  {confidence:.0%}', label


class TestSession:
    def __init__(self):
        self.protocol = ManualProtocol(gestures=SELECTED, minimum_frames=15, minimum_streak=5)
        self.last_fid = None
        self.minimum_arrival = 0.0

    def press(self, now):
        changed = self.protocol.press_space(now)
        if changed:
            self.minimum_arrival = now
        return changed

    def feed(self, fid, arrival, now, labels):
        if fid == self.last_fid or arrival < self.minimum_arrival or now-arrival > 1:
            return None
        self.last_fid = fid
        return self.protocol.tick(now, labels)

    def invalidate(self):
        if self.protocol.phase != 'COMPLETE':
            self.protocol.reset_item()

    def hint(self, now):
        p = self.protocol
        hints = {
            'READY': '准备好后点击开始 / 按空格：3秒准备，5秒保持',
            'ROUND_PASS': '本轮通过；放下手再摆好，点击开始 / 按空格继续',
            'ROUND_FAIL': '本轮未通过；保留失败记录，点击开始 / 按空格重试',
            'ITEM_PASS': '本项连续3轮通过；点击下一项 / 按空格确认',
            'COMPLETE': '全部测试完成，结果已保存；可切回普通显示',
        }
        if p.phase in ('PREPARE', 'OBSERVE'):
            return ('准备' if p.phase == 'PREPARE' else '检测保持') + f' {max(0, p.deadline-now):.1f} 秒'
        return hints[p.phase]
