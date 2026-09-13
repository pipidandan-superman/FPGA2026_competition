"""FPGA UDP gesture viewer with optional PS/AXI action verification."""
import argparse
from collections import deque
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import queue
import sys
import threading
import time
import traceback
import tkinter as tk
from tkinter import messagebox, ttk

from gesture_viewer_core import NAMES, TestSession, action_text
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'udp_video'))
from validated_receiver import Receiver

EXPECTED_SHA = '68db7cacbdd6d9c9a583e1c50a9f5934a3a6b78675b215ec86717827be8bfc79'
LOG_ROOT = Path('E:/competition/4_metrics/logs')


def model_path():
    if getattr(sys, 'frozen', False):
        return Path(sys._MEIPASS) / 'model/best.pt'
    return Path(__file__).resolve().parents[1] / 'model/best.pt'


def load_model():
    import torch
    from ultralytics import YOLO
    weight = model_path()
    if hashlib.sha256(weight.read_bytes()).hexdigest() != EXPECTED_SHA:
        raise RuntimeError('模型文件缺失或SHA256不匹配；请恢复完整发布目录')
    torch.set_num_threads(2)
    model = YOLO(str(weight), task='detect')
    if [model.names[i] for i in range(7)] != ['Down', 'Left', 'Right', 'Stop', 'Thumbs Down', 'Thumbs up', 'Up']:
        raise RuntimeError('模型类别不匹配')
    return model


class App:
    def __init__(self, root, run, smoke_seconds=0, action_control=False,
                 action_host="192.168.240.10"):
        self.root, self.run = root, run
        self.smoke_seconds = smoke_seconds
        self.started = time.monotonic()
        self.event_lock = threading.Lock()
        self.publisher = None
        if action_control:
            from action_link import ActionPublisher
            self.publisher = ActionPublisher(self.event, host=action_host)
        self.receiver = None
        self.stop = threading.Event()
        self.results = queue.Queue(maxsize=1)
        self.worker = None
        self.worker_state = '正在加载模型…'
        self.error = None
        self.closed = False
        self.latest = None
        self.stale_before = True
        self.frame_times = deque(maxlen=50)
        self.inference_count = 0
        self.last_status = 0
        self.last_press = -100
        self.session = None
        self.test_number = 0
        self.history = []
        self.mode = tk.StringVar(value='normal')
        self.current_mode = 'normal'
        root.title('EES331 手势识别上位机 v1.0 — 普通显示 / 测试模式')
        root.geometry('1100x880')
        root.minsize(920, 760)
        root.option_add('*Font', ('Microsoft YaHei UI', 11))
        root.configure(bg='#111827')
        bar = ttk.Frame(root, padding=12)
        bar.pack(fill='x')
        ttk.Label(bar, text='工作模式：').pack(side='left')
        for text, value in [('普通显示', 'normal'), ('测试模式', 'test')]:
            ttk.Radiobutton(bar, text=text, variable=self.mode, value=value, command=self.change_mode).pack(side='left', padx=10)
        ttk.Button(bar, text='重新连接', command=self.reconnect).pack(side='right', padx=5)
        ttk.Button(bar, text='打开结果目录', command=lambda: os.startfile(str(run))).pack(side='right', padx=5)
        self.action = tk.Label(root, text='正在启动…', fg='#6ee7b7', bg='#111827', font=('Microsoft YaHei UI', 24, 'bold'))
        self.action.pack(pady=(10, 4))
        self.raw = tk.Label(root, text='原始预测：—', fg='#cbd5e1', bg='#111827')
        self.raw.pack()
        self.network = tk.Label(root, text='监听 UDP 5000；板端 192.168.240.10', fg='#93c5fd', bg='#111827')
        self.network.pack(pady=5)
        self.video = tk.Label(root, text='等待FPGA视频\n上电通常需要60～90秒\n请关闭旧上位机，避免UDP 5000冲突', bg='#030712', fg='#cbd5e1', width=90, height=24)
        self.video.pack(fill='both', expand=True, padx=14)
        self.test_panel = ttk.Frame(root, padding=10)
        self.test_panel.pack(fill='x')
        self.target = ttk.Label(self.test_panel, text='普通显示：接收到完整有效帧后自动识别；无需按空格。', font=('Microsoft YaHei UI', 13, 'bold'))
        self.target.pack(anchor='w')
        self.instruction = ttk.Label(self.test_panel, text='')
        self.instruction.pack(anchor='w', pady=3)
        self.hint = ttk.Label(self.test_panel, text='')
        self.hint.pack(anchor='w')
        self.last_round = ttk.Label(self.test_panel, text='')
        self.last_round.pack(anchor='w', pady=3)
        controls = ttk.Frame(self.test_panel)
        controls.pack(fill='x')
        self.next_button = ttk.Button(controls, text='开始 / 下一轮 / 下一项（空格）', command=self.press)
        self.next_button.pack(side='left')
        self.reset_button = ttk.Button(controls, text='重置当前项（R）', command=self.reset)
        self.reset_button.pack(side='left', padx=8)
        self.control_status = ttk.Label(root, text=(
            'AXI动作测试：3个新帧同类且置信度≥0.75，左右禁用'
            if action_control else '仅显示预测；启用动作测试请使用 --action-control'),
            foreground='#b45309')
        self.control_status.pack(fill='x', padx=14, pady=8)
        root.bind('<space>', self.press)
        root.bind('<r>', self.reset)
        root.bind('<R>', self.reset)
        root.bind('<Escape>', lambda e: self.close())
        root.protocol('WM_DELETE_WINDOW', self.close)
        root.report_callback_exception = self.callback_error
        self.event('START', model_sha256=EXPECTED_SHA, mode='normal', source='192.168.240.10', port=5000)
        self.start_worker()
        root.after(50, self.update)

    def write(self, name, data):
        tmp = self.run / (name + '.tmp')
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        tmp.replace(self.run / name)

    def event(self, kind, **data):
        with self.event_lock, (self.run/'events.jsonl').open('a', encoding='utf-8') as f:
            f.write(json.dumps(dict(event=kind, elapsed=time.monotonic()-self.started, **data), ensure_ascii=False)+'\n')

    def start_worker(self):
        if self.publisher:
            self.publisher.reset_frames()
        self.stop.clear()
        self.error = None
        self.latest = None
        self.frame_times.clear()
        self.receiver = Receiver()
        self.receiver.start()
        self.worker = threading.Thread(target=self.infer, daemon=True)
        self.worker.start()

    def infer(self):
        try:
            if not self.receiver.ready.wait(3) or self.receiver.error:
                raise RuntimeError(self.receiver.error or '接收线程启动超时')
            self.worker_state = '正在加载模型…'
            model = load_model()
            import numpy as np
            self.worker_state = '模型就绪，等待视频'
            with (self.run/'predictions.jsonl').open('a', encoding='utf-8') as log:
                while not self.stop.is_set():
                    if self.receiver.error:
                        raise RuntimeError(self.receiver.error)
                    try:
                        frame = self.receiver.frames.get(timeout=.2)
                    except queue.Empty:
                        continue
                    if time.monotonic()-frame.received_at > 1:
                        continue
                    image = np.frombuffer(frame.data, dtype=np.uint8).reshape(480, 640, 3)
                    start = time.perf_counter()
                    result = model.predict(image, device='cpu', imgsz=640, rect=False, conf=.45, iou=.7, verbose=False, save=False)[0]
                    ms = (time.perf_counter()-start)*1000
                    detections = [dict(label=result.names[int(b.cls.item())], confidence=float(b.conf.item()), xyxy=b.xyxy[0].tolist()) for b in result.boxes]
                    row = dict(fid=frame.fid, arrival=frame.received_at, inference_ms=ms, detections=detections)
                    if self.publisher:
                        self.publisher.feed(row)
                    log.write(json.dumps(row)+'\n')
                    log.flush()
                    self.inference_count += 1
                    row['image'] = image.copy()
                    try:
                        self.results.put_nowait(row)
                    except queue.Full:
                        try:
                            self.results.get_nowait()
                        except queue.Empty:
                            pass
                        self.results.put_nowait(row)
        except Exception:
            self.error = traceback.format_exc()
            (self.run/'error.txt').write_text(self.error, encoding='utf-8')
            self.worker_state = '启动或推理失败；查看结果目录中的error.txt'

    def fresh(self):
        return self.latest is not None and time.monotonic()-self.latest['arrival'] <= 1 and not self.error

    def save_test(self, reason):
        if self.session:
            snapshot = self.session.protocol.snapshot()
            self.write(f'test_{self.test_number:03d}.json', dict(result='COMPLETE' if snapshot['phase']=='COMPLETE' else 'INCOMPLETE', reason=reason, **snapshot))

    def change_mode(self):
        new = self.mode.get()
        if new == self.current_mode:
            return
        if self.session and self.session.protocol.phase != 'COMPLETE':
            if not messagebox.askyesno('保存未完成测试', '切换模式将结束当前测试并保存未完成记录。是否继续？', parent=self.root):
                self.mode.set(self.current_mode)
                return
        self.save_test('mode_switch')
        self.session = None
        self.current_mode = new
        if new == 'test':
            self.test_number += 1
            self.session = TestSession()
            self.save_test('started')
        self.event('MODE_CHANGED', mode=new, test_number=self.test_number)

    def press(self, event=None):
        now = time.monotonic()
        if self.session and self.fresh() and now-self.last_press >= .8:
            self.last_press = now
            if self.session.press(now):
                self.event('USER_SPACE', test_number=self.test_number, protocol=self.session.protocol.snapshot())
                self.save_test('user_confirmed')
        return 'break'

    def reset(self, event=None):
        if self.session and messagebox.askyesno('重置当前项', '连续通过数归零；历史轮次仍保留。确认重置？', parent=self.root):
            self.session.invalidate()
            self.save_test('user_reset')
            self.event('USER_RESET', test_number=self.test_number)
        return 'break'

    def reconnect(self):
        if self.session:
            self.session.invalidate()
            self.save_test('reconnect')
        self.stop.set()
        self.receiver.stop()
        self.worker.join(timeout=3)
        if self.worker.is_alive():
            messagebox.showinfo('请稍候', '模型仍在加载或推理，请稍后再次点击重新连接。', parent=self.root)
            return
        while not self.results.empty():
            try:
                self.results.get_nowait()
            except queue.Empty:
                break
        self.event('RECONNECT', previous_rx_stats=dict(self.receiver.parser.stats))
        self.start_worker()

    def render(self, row):
        from PIL import Image, ImageDraw, ImageTk
        image = Image.fromarray(row['image'][:, :, ::-1])
        draw = ImageDraw.Draw(image)
        for d in row['detections']:
            x1, y1, x2, y2 = d['xyxy']
            color = '#fbbf24' if d['label'] in ('Left', 'Right') else '#34d399'
            draw.rectangle((x1, y1, x2, y2), outline=color, width=3)
            draw.text((x1+3, max(0, y1-14)), f"{d['label']} {d['confidence']:.2f}", fill=color)
        w, h = max(640, self.video.winfo_width()), max(300, self.video.winfo_height())
        image.thumbnail((w, h))
        self.photo = ImageTk.PhotoImage(image)
        self.video.configure(image=self.photo, text='', width=0, height=0)

    def update(self):
        if self.closed:
            return
        now = time.monotonic()
        try:
            row = self.results.get_nowait()
        except queue.Empty:
            row = None
        if row and now-row['arrival'] <= 1 and not self.error:
            self.latest = row
            self.frame_times.append(row['arrival'])
            if self.session:
                result = self.session.feed(row['fid'], row['arrival'], now, {d['label'] for d in row['detections']})
                if result:
                    self.event('ROUND_RESULT', test_number=self.test_number, result=result)
                    self.save_test('round_finished')
            self.render(row)
        stale = not self.fresh()
        if stale and not self.stale_before:
            if self.session:
                self.session.invalidate()
                self.save_test('video_stale')
            self.event('VIDEO_STALE')
        self.stale_before = stale
        ds = self.latest['detections'] if self.latest else []
        text, effective = action_text(ds, stale)
        self.action.configure(text='当前预测：'+text, fg='#fbbf24' if effective=='UNKNOWN' else '#6ee7b7')
        raw = '，'.join(f"{d['label']} {d['confidence']:.2f}" for d in ds) if not stale else '—（旧结果已失效）'
        self.raw.configure(text='原始预测：'+(raw or '无检测'))
        if stale:
            self.video.configure(image='', text='等待视频 / 视频已中断\n当前不输出动作、不计分\n上电等待60～90秒；必要时点击重新连接', width=90, height=24)
        stats = dict(self.receiver.parser.stats)
        fps = (len(self.frame_times)-1)/(self.frame_times[-1]-self.frame_times[0]) if len(self.frame_times)>1 and not stale else 0
        net = f"UDP 5000 | 完整帧 {stats.get('complete_frames',0)} | 推理显示 {fps:.1f} fps | CRC错 {stats.get('crc_error',0)} | 丢帧 {stats.get('lost_frames',0)} | 不完整 {stats.get('incomplete_frames',0)}"
        if self.error:
            net = '接收/模型失败：请关闭旧上位机后重新连接；详细原因见error.txt'
        elif self.latest is None:
            net += ' | '+self.worker_state
        self.network.configure(text=net)
        if self.publisher:
            control_text = ('动作链路失败：'+self.publisher.error if self.publisher.error else
                            ('AXI动作链路就绪｜'+str(self.publisher.last_result)
                             if self.publisher.ready else '正在连接PS动作服务…'))
            self.control_status.configure(text=control_text)
        if self.session:
            p = self.session.protocol
            self.target.configure(text=f'测试 {p.index+1}/6：{p.gesture[1]} | 连续通过 {p.passed_rounds}/3')
            self.instruction.configure(text=p.gesture[2])
            self.hint.configure(text=self.session.hint(now) if not stale else '视频中断：本项连续通过数已重置，请恢复后重新开始。')
            r = p.last_result
            self.last_round.configure(text=f"上轮：{r['matching_frames']}/{r['frames']} 帧匹配，{'通过' if r['passed'] else '未通过'}；所有失败均保留。" if r else '每轮≥15新帧，连续匹配≥5帧；手势≥90%，无手≥98%。')
        else:
            self.target.configure(text='普通显示：自动识别当前动作，不进行测试评分。')
            self.instruction.configure(text='可随时切换测试模式；测试中途退出将保存未完成记录。')
            self.hint.configure(text='无需空格；预测可能错误，不应用于直接驱动机械臂。')
            self.last_round.configure(text='')
        enabled = self.session is not None and not stale and self.session.protocol.phase not in ('PREPARE','OBSERVE','COMPLETE')
        self.next_button.configure(state='normal' if enabled else 'disabled')
        self.reset_button.configure(state='normal' if self.session and self.session.protocol.phase != 'COMPLETE' else 'disabled')
        if now-self.last_status >= 1:
            self.write('status.json', dict(mode=self.current_mode, stale=stale, effective_action=effective, inference_frames=self.inference_count, rx_stats=stats, error=self.error, protocol=self.session.protocol.snapshot() if self.session else None))
            self.last_status = now
        if self.smoke_seconds and now-self.started >= self.smoke_seconds:
            self.close()
        else:
            self.root.after(40, self.update)

    def callback_error(self, cls, value, tb):
        self.error = ''.join(traceback.format_exception(cls, value, tb))
        (self.run/'ui_error.txt').write_text(self.error, encoding='utf-8')
        messagebox.showerror('程序异常', '详情已保存到结果目录，程序将退出。', parent=self.root)
        self.close()

    def close(self):
        if self.closed:
            return
        self.closed = True
        self.save_test('window_closed')
        self.stop.set()
        self.receiver.stop()
        self.worker.join(timeout=3)
        if self.publisher:
            self.publisher.close()
        action_error = self.publisher.error if self.publisher else None
        self.write('result.json', dict(result='ERROR' if self.error or action_error else 'VIEWER_CLOSED', inference_frames=self.inference_count, rx_stats=dict(self.receiver.parser.stats), error=self.error, action_error=action_error, action_last=self.publisher.last_result if self.publisher else None, model_sha256=EXPECTED_SHA, last_test=self.session.protocol.snapshot() if self.session else None))
        self.root.destroy()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run-dir')
    parser.add_argument('--smoke-seconds', type=float, default=0)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--action-control', action='store_true',
                        help='Enable approved PC->PS->AXI LED/UART verification')
    parser.add_argument('--action-host', default='192.168.240.10')
    args = parser.parse_args()
    run = Path(args.run_dir).resolve() if args.run_dir else LOG_ROOT / (datetime.now().strftime('%Y-%m-%d_%H%M%S_%f')+'_gesture_viewer_run01')
    if not run.is_relative_to(LOG_ROOT.resolve()):
        raise ValueError('日志目录必须在 E:/competition/4_metrics/logs 下')
    run.mkdir(parents=True, exist_ok=False)
    for name in ('ultralytics_config', 'matplotlib_config'):
        (run/name).mkdir()
    os.environ.update(YOLO_CONFIG_DIR=str(run/'ultralytics_config'), MPLCONFIGDIR=str(run/'matplotlib_config'), YOLO_AUTOINSTALL='false', YOLO_OFFLINE='true', PYTHONNOUSERSITE='1')
    # PyInstaller --windowed has no stdout/stderr; retain library diagnostics.
    with (run/'console.txt').open('w', encoding='utf-8', buffering=1) as console:
        sys.stdout = sys.stderr = console
        try:
            if args.self_test:
                from action_link import ActionClient
                from stable_action import StableAction
                from action_protocol import command, decode_command, uart_frame
                gate = StableAction()
                decisions = [gate.feed(i, i*.2, i*.2,
                             [dict(label="Stop", confidence=.9)]) for i in range(1,4)]
                if decisions[:2] != [None, None] or decisions[2]["action"] != 4:
                    raise RuntimeError("Packaged action stability test failed")
                if decode_command(command(1,4)) != (1,1,4) or len(uart_frame(1,4)) != 7:
                    raise RuntimeError("Packaged action protocol test failed")
                self_test_action = dict(marker="FROZEN_ACTION_PROTOCOL_PASS",
                                        frame_hex=uart_frame(1,4).hex())
                import numpy as np
                model = load_model()
                result = model.predict(np.zeros((480,640,3), dtype=np.uint8), imgsz=640, rect=False, conf=.45, iou=.7, device='cpu', verbose=False)[0]
                root = tk.Tk()
                root.withdraw()
                ttk.Radiobutton(root, text='普通显示 / 测试模式').pack()
                root.update()
                root.destroy()
                (run/'self_test.json').write_text(json.dumps(dict(result='FROZEN_MODEL_TK_SMOKE_PASS', action=self_test_action, model_sha256=EXPECTED_SHA, names=result.names, frozen=bool(getattr(sys,'frozen',False)))), encoding='utf-8')
            else:
                root = tk.Tk()
                App(root, run, args.smoke_seconds, args.action_control, args.action_host)
                root.mainloop()
        except Exception:
            (run/'fatal_error.txt').write_text(traceback.format_exc(), encoding='utf-8')
            if not args.self_test:
                messagebox.showerror('启动失败', f'请查看 {run}/fatal_error.txt')
            raise


if __name__ == '__main__':
    import multiprocessing
    multiprocessing.freeze_support()
    main()
