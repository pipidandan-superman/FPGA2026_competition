"""Chinese instructions with user-gated repeated webcam validation."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
import traceback

import cv2
import numpy as np
import torch
from PIL import Image, ImageDraw, ImageFont
from ultralytics import YOLO
from manual_gesture_protocol import GESTURES, ManualProtocol

EXPECTED_SHA = '68db7cacbdd6d9c9a583e1c50a9f5934a3a6b78675b215ec86717827be8bfc79'


def banner(lines, font):
    picture = Image.new('RGB', (960, 280), (18, 23, 30))
    draw = ImageDraw.Draw(picture)
    for index, line in enumerate(lines):
        draw.text((16, 10 + index * 37), line, font=font,
                  fill=(110, 240, 150) if index < 2 else (240, 240, 240))
    return cv2.cvtColor(np.asarray(picture), cv2.COLOR_RGB2BGR)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run-dir', required=True)
    parser.add_argument('--camera', type=int, default=0)
    parser.add_argument('--max-seconds', type=int, default=1800)
    args = parser.parse_args()
    run = Path(args.run_dir).resolve()
    assert run.is_relative_to(Path('E:/competition/4_metrics/logs').resolve())
    run.mkdir(parents=True, exist_ok=True)
    if (run / 'frames.jsonl').exists() or (run / 'result.json').exists():
        raise RuntimeError('Use a new run directory')
    root = Path(__file__).resolve().parents[2]
    weight = root / '3_host/model/best.pt'
    protocol = ManualProtocol()
    cap = model = None
    raw_confirmed = False
    frame_count = infer_count = 0
    latencies = []
    started = time.monotonic()
    last_status = 0
    last_space = -100
    state = 'RAW_PREVIEW'
    reason = 'unknown'
    window = 'Gesture Validation - Manual - SPACE / R / Q'
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 25)

    def write_json(name, data):
        temp = run / (name + '.tmp')
        temp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        temp.replace(run / name)

    def status():
        write_json('status.json', dict(stage=state, frames=frame_count,
                   inference_frames=infer_count, raw_preview_user_confirmed=raw_confirmed,
                   elapsed_seconds=round(time.monotonic()-started, 2),
                   sequence_complete=protocol.phase == 'COMPLETE', **protocol.snapshot()))

    def event(kind, **data):
        with (run / 'events.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps(dict(event=kind, elapsed_seconds=time.monotonic()-started,
                             **data), ensure_ascii=False) + '\n')

    try:
        assert hashlib.sha256(weight.read_bytes()).hexdigest() == EXPECTED_SHA
        torch.set_num_threads(2)
        status()
        cap = cv2.VideoCapture(args.camera, cv2.CAP_DSHOW)
        if not cap.isOpened():
            raise RuntimeError('Camera open failed (DirectShow)')
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        cap.set(cv2.CAP_PROP_FPS, 30)
        write_json('config.json', dict(python=sys.executable, weight=str(weight), sha256=EXPECTED_SHA,
                   device='cpu', imgsz=640, conf=0.45, iou=0.7, rect=False, mirror=False,
                   temporal_filter=False, backend=cap.getBackendName(), camera=args.camera,
                   actual_size=[cap.get(cv2.CAP_PROP_FRAME_WIDTH), cap.get(cv2.CAP_PROP_FRAME_HEIGHT)],
                   sequence=GESTURES, required_consecutive_rounds=3,
                   prepare_seconds=3, observe_seconds=5, minimum_frames=30,
                   positive_match_rate=0.90, no_hand_match_rate=0.98, minimum_streak=10,
                   matching_rule='exact label set; duplicate same-label boxes allowed',
                   advancement='explicit SPACE only, after item passes',
                   failed_round='preserve all attempts; reset consecutive count; manual retry',
                   images_saved=False, video_saved=False))
        cv2.namedWindow(window, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window, 960, 1000)
        print('RAW_PREVIEW: SPACE confirms raw image and loads model.', flush=True)
        event('START')
        with (run / 'frames.jsonl').open('x', encoding='utf-8') as log:
            while time.monotonic()-started < args.max_seconds:
                if (run / 'STOP').exists():
                    reason = 'stop_file'
                    break
                ok, frame = cap.read()
                if not ok or frame is None:
                    raise RuntimeError('Camera read failed')
                frame_count += 1
                detections = []
                annotated = frame
                if model is None:
                    lines = ['原始画面检查：请确认清晰、流畅',
                             '确认后按空格加载模型，进入第 1 项：停止手势',
                             '操作提示始终显示在这里，请按中文说明摆好手势。',
                             '每项连续通过 3 轮后，仍须按空格才换到下一项。',
                             '每轮按空格开始：3 秒准备 + 5 秒保持。',
                             '不镜像：左右以预览画面的左右为准。',
                             'Q / Esc：退出；只记录数值，不保存图像或录像。']
                else:
                    t0 = time.perf_counter()
                    result = model.predict(frame, device='cpu', imgsz=640, rect=False,
                                           conf=0.45, iou=0.7, verbose=False, save=False)[0]
                    latency = (time.perf_counter()-t0)*1000
                    latencies.append(latency)
                    infer_count += 1
                    for box in result.boxes:
                        detections.append(dict(label=result.names[int(box.cls.item())],
                                               confidence=round(float(box.conf.item()), 4),
                                               xyxy=[round(float(v), 1) for v in box.xyxy[0].tolist()]))
                    annotated = result.plot()
                    now = time.monotonic()
                    sampled_phase = protocol.phase
                    row = protocol.tick(now, [d['label'] for d in detections])
                    if row:
                        event('ROUND_RESULT', **row)
                        write_json('trials.json', protocol.snapshot())
                        print('ROUND_RESULT: ' + json.dumps(row), flush=True)
                    phase = protocol.phase
                    state = phase
                    expected, chinese, instruction = protocol.gesture
                    title = f'第 {protocol.index+1}/8 项：{chinese} ({expected})'
                    progress = f'本项连续通过 {protocol.passed_rounds}/3 轮'
                    if phase == 'PREPARE':
                        hint = f'准备 {max(0, protocol.deadline-now):.1f} 秒：摆好动作，随后开始计分'
                    elif phase == 'OBSERVE':
                        hint = f'检测 {max(0, protocol.deadline-now):.1f} 秒：保持姿势，当前项不会自动切换'
                    elif phase == 'ITEM_PASS':
                        hint = '本项已通过！按空格进入下一项；R 重新验证本项'
                        if protocol.index == 7:
                            hint = '全部项目已通过！按空格确认完成并退出'
                    elif phase == 'ROUND_FAIL':
                        hint = '本轮未通过：仍在本项。调整姿势后按空格重试'
                    elif phase == 'ROUND_PASS':
                        hint = '本轮通过：请放下手再摆好，按空格验证下一轮'
                    else:
                        hint = '请先练习动作；准备好后按空格开始本轮'
                    stats = '单轮：5秒内正确率>=90%，至少30帧且连续正确10帧'
                    if expected == 'NO HAND':
                        stats = '单轮：5秒内无检测率>=98%，至少30帧且连续无检测10帧'
                    if protocol.last_result and phase not in ('PREPARE', 'OBSERVE'):
                        stats = (f"上轮正确率 {protocol.last_result['match_rate']:.1%}；"
                                 f"目标 >= {protocol.last_result['required_rate']:.0%}；"
                                 '至少30帧，连续正确10帧')
                    shown = ', '.join(f"{d['label']} {d['confidence']:.2f}" for d in detections[:3]) or '无检测'
                    lines = [title + ' | ' + progress, instruction, hint,
                             '实时识别：' + shown, stats,
                             '空格：开始/确认下一项；R：重置本项；Q / Esc：退出',
                             '一次只做一种手势；不镜像，左右以画面为准；不保存录像']
                    log.write(json.dumps(dict(elapsed_seconds=round(now-started, 4),
                              frame=frame_count, expected_label=expected,
                              phase_before_tick=sampled_phase, phase_after_tick=phase,
                              pipeline_ms=round(latency, 3), detections=detections)) + '\n')
                    log.flush()
                cv2.imshow(window, np.vstack([banner(lines, font), cv2.resize(annotated, (960, 720))]))
                now = time.monotonic()
                if now-last_status >= 1:
                    status()
                    last_status = now
                key = cv2.waitKey(1) & 0xff
                if key in (27, ord('q'), ord('Q')):
                    reason = 'user_quit'
                    break
                if cv2.getWindowProperty(window, cv2.WND_PROP_VISIBLE) < 1:
                    reason = 'window_closed'
                    break
                if key in (ord('r'), ord('R')) and model is not None:
                    event('RESET_CURRENT_ITEM', before=protocol.snapshot())
                    protocol.reset_item()
                    state = protocol.phase
                    write_json('trials.json', protocol.snapshot())
                    status()
                if key == 32:
                    # Ignore OS key-repeat: release SPACE before the next decision.
                    deliberate_press = now-last_space >= 0.8
                    last_space = now
                    if deliberate_press:
                        if model is None:
                            raw_confirmed = True
                            state = 'LOADING_MODEL'
                            status()
                            model = YOLO(str(weight), task='detect')
                            assert [model.names[i] for i in range(7)] == [
                                'Down', 'Left', 'Right', 'Stop', 'Thumbs Down', 'Thumbs up', 'Up']
                            last_space = time.monotonic()
                            state = protocol.phase
                            event('RAW_CONFIRMED_MODEL_LOADED')
                            print('MODEL_LOADED: manual Stop practice, waiting for SPACE.', flush=True)
                            status()
                        else:
                            before = protocol.snapshot()
                            if protocol.press_space(now):
                                event('USER_SPACE', before=before, after=protocol.snapshot())
                                state = protocol.phase
                                write_json('trials.json', protocol.snapshot())
                                status()
                            if protocol.phase == 'COMPLETE':
                                reason = 'manual_sequence_complete'
                                break
            else:
                reason = 'bounded_timeout'
        state = 'COMPLETE' if protocol.phase == 'COMPLETE' else 'STOPPED'
    except Exception as exc:
        state = 'ERROR'
        reason = repr(exc)
        (run / 'error.txt').write_text(traceback.format_exc(), encoding='utf-8')
        traceback.print_exc()
    finally:
        if cap is not None:
            cap.release()
        cv2.destroyAllWindows()
        status()
        write_json('result.json', dict(result='MANUAL_GESTURE_SMOKE_PASS' if state == 'COMPLETE'
                   else 'WEBCAM_RUN_INCOMPLETE', stage=state, stop_reason=reason,
                   capture_frames=frame_count, inference_frames=infer_count,
                   raw_preview_user_confirmed=raw_confirmed,
                   protocol=protocol.snapshot(), accuracy_validated=False,
                   scope='interactive smoke checks, not held-out accuracy',
                   pipeline_ms_percentiles={str(p):float(np.percentile(latencies,p))
                                            for p in [50,95,99]} if latencies else {},
                   images_saved=False, video_saved=False))
        print(state + ': ' + reason, flush=True)
    return int(state == 'ERROR')


if __name__ == '__main__':
    sys.exit(main())
