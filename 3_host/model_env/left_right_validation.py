"""Fixed-count left/right baseline: mirrored display, unchanged model input."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys
import time
import traceback

import cv2
import numpy as np
import torch
from PIL import ImageFont
from ultralytics import YOLO
from webcam_validation import banner, EXPECTED_SHA


def display_label(raw):
    return {'Left': 'Right', 'Right': 'Left'}.get(raw, raw)


def mirror_box(box, width):
    x1, y1, x2, y2 = box
    return [width-x2, y1, width-x1, y2]


def classify(raw_labels, target):
    labels = {display_label(x) for x in raw_labels}
    if not labels:
        return 'no_detection'
    if {'Left', 'Right'} <= labels:
        return 'left_right_conflict'
    if labels == {target}:
        return 'correct'
    if display_label(target) in labels:
        return 'wrong_direction'
    return 'other_or_mixed'


class FixedTrials:
    def __init__(self):
        self.index = 0
        self.phase = 'READY'
        self.deadline = 0
        self.counts = Counter()
        self.results = []

    @property
    def target(self):
        return 'Left' if self.index < 5 else 'Right'

    def space(self, now):
        if self.phase == 'ROUND_DONE':
            if self.index == 9:
                self.phase = 'COMPLETE'
            else:
                self.index += 1
                self.phase = 'READY'
            return True
        if self.phase == 'READY':
            self.counts = Counter()
            self.phase = 'PREPARE'
            self.deadline = now+3
            return True
        return False

    def tick(self, now, labels):
        if self.phase == 'PREPARE' and now >= self.deadline:
            self.phase = 'OBSERVE'
            self.deadline = now+5
        if self.phase != 'OBSERVE':
            return False, None
        if now < self.deadline:
            self.counts[classify(labels, self.target)] += 1
            return True, None
        n = sum(self.counts.values())
        row = dict(trial=self.index+1, user_target=self.target,
                   raw_expected_label=display_label(self.target),
                   frames=n, counts=dict(self.counts),
                   rates={k: self.counts[k]/n if n else 0 for k in
                          ['correct', 'no_detection', 'left_right_conflict',
                           'wrong_direction', 'other_or_mixed']},
                   sample_sufficient=n >= 30)
        self.results.append(row)
        self.phase = 'ROUND_DONE'
        return False, row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run-dir', required=True)
    args = parser.parse_args()
    run = Path(args.run_dir).resolve()
    assert run.is_relative_to(Path('E:/competition/4_metrics/logs').resolve())
    run.mkdir(parents=True, exist_ok=True)
    if (run/'frames.jsonl').exists():
        raise RuntimeError('Use a fresh run')
    root = Path(__file__).resolve().parents[2]
    weight = root/'3_host/model/best.pt'
    calibration_path = root/'4_metrics/logs/2026-09-12_model_webcam_run07/result.json'
    calibration_bytes = calibration_path.read_bytes()
    calibration = json.loads(calibration_bytes)
    assert calibration['result'] == 'DIRECTION_CALIBRATION_COMPLETE'
    assert {x['physical_prompt']: x['user_annotated_raw_direction']
            for x in calibration['annotations']} == {
                'own_right': 'image_left', 'own_left': 'image_right'}
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 25)
    trials = FixedTrials()
    cap = model = None
    frame_count = inference_count = 0
    started = time.monotonic()
    last_space = -100
    last_status = 0
    latencies = []
    reason = 'unknown'
    window = 'Left Right Baseline - MIRROR - SPACE / Q'

    def write(name, data):
        temp = run/(name+'.tmp')
        temp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        temp.replace(run/name)

    def status():
        write('status.json', dict(phase=trials.phase if model else 'MIRROR_PREVIEW',
              trial=trials.index+1, user_target=trials.target,
              raw_expected_label=display_label(trials.target), frames=frame_count,
              inference_frames=inference_count, completed_rounds=len(trials.results),
              elapsed_seconds=time.monotonic()-started, stop_reason=reason))

    def event(kind, **data):
        with (run/'events.jsonl').open('a', encoding='utf-8') as out:
            out.write(json.dumps(dict(event=kind, elapsed=time.monotonic()-started, **data))+'\n')

    try:
        assert hashlib.sha256(weight.read_bytes()).hexdigest() == EXPECTED_SHA
        torch.set_num_threads(2)
        cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
        if not cap.isOpened():
            raise RuntimeError('DirectShow camera open failed')
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        cap.set(cv2.CAP_PROP_FPS, 30)
        write('config.json', dict(model=str(weight), sha256=EXPECTED_SHA,
              python=sys.executable, device='cpu', conf=0.45, iou=0.7, imgsz=640,
              rect=False, camera=0, backend=cap.getBackendName(),
              actual_size=[cap.get(cv2.CAP_PROP_FRAME_WIDTH),cap.get(cv2.CAP_PROP_FRAME_HEIGHT)],
              model_input_mirror=False, preview_mirror=True,
              raw_to_user_direction={'Left':'Right','Right':'Left'},
              coordinate_calibration=str(calibration_path),
              calibration_sha256=hashlib.sha256(calibration_bytes).hexdigest(),
              prepare_seconds=3, observe_seconds=5, trials_per_direction=5,
              sequence=['Left']*5+['Right']*5, temporal_filter=False,
              class_conflict_suppression=False, images_saved=False, video_saved=False,
              counts_partition='correct/no_detection/left_right_conflict/wrong_direction/other_or_mixed',
              ground_truth='user follows prompt; not independently annotated'))
        cv2.namedWindow(window, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window, 960, 1000)
        status()
        print('MIRROR_PREVIEW: SPACE confirms coordinate mapping and loads model.', flush=True)
        with (run/'frames.jsonl').open('x', encoding='utf-8') as out:
            while time.monotonic()-started < 1800:
                if (run/'STOP').exists():
                    reason = 'stop_file'
                    break
                ok, frame = cap.read()
                if not ok or frame is None:
                    raise RuntimeError('Camera read failed')
                frame_count += 1
                shown_frame = cv2.flip(frame, 1)
                if model is None:
                    lines = ['已校准：身体左 = 原图 Right；身体右 = 原图 Left',
                             '此窗口是镜像预览；动作始终按你身体的左/右做。',
                             '按空格加载模型，先做身体向左；不要跟随模型改动作。',
                             '先向左5轮，再向右5轮；每轮都由你按空格开始。',
                             '每轮3秒准备、5秒保持；成功失败都记录，不重试刷分。',
                             '请保持同一只手、距离、光照；只伸食指，其他指收起。',
                             'Q / Esc退出；不保存图像或视频；模型输入保持原图。']
                else:
                    t0 = time.perf_counter()
                    prediction = model.predict(frame, device='cpu', imgsz=640, rect=False,
                                               conf=0.45, iou=0.7, verbose=False, save=False)[0]
                    latency = (time.perf_counter()-t0)*1000
                    latencies.append(latency)
                    inference_count += 1
                    detections = []
                    for box in prediction.boxes:
                        raw = prediction.names[int(box.cls.item())]
                        xyxy = [round(float(v), 1) for v in box.xyxy[0].tolist()]
                        confidence = float(box.conf.item())
                        mapped = display_label(raw)
                        detections.append(dict(raw_label=raw, user_label=mapped,
                                               confidence=confidence, raw_xyxy=xyxy))
                        a,b,c,d = [int(v) for v in mirror_box(xyxy, frame.shape[1])]
                        cv2.rectangle(shown_frame, (a,b), (c,d), (80,220,80), 2)
                        cv2.putText(shown_frame, f'Body:{mapped} / Raw:{raw} {confidence:.2f}', (a,max(18,b-5)),
                                    cv2.FONT_HERSHEY_SIMPLEX, .48, (80,220,80), 1)
                    now = time.monotonic()
                    scoring, row = trials.tick(now, [x['raw_label'] for x in detections])
                    if row:
                        write('trials.json', trials.results)
                        event('ROUND_RESULT', result=row)
                        print('ROUND_RESULT: '+json.dumps(row), flush=True)
                    out.write(json.dumps(dict(elapsed_seconds=now-started, frame=frame_count,
                              trial=trials.index+1, user_target=trials.target,
                              scoring=scoring, phase=trials.phase,
                              pipeline_ms=latency, detections=detections))+'\n')
                    out.flush()
                    direction = '左' if trials.target == 'Left' else '右'
                    phase = trials.phase
                    hint = '准备好后按空格开始本轮；请按动作要求，不要追随预测改方向'
                    if phase in ('PREPARE','OBSERVE'):
                        hint = ('准备' if phase == 'PREPARE' else '计分，保持动作') + f'：{max(0,trials.deadline-now):.1f}秒'
                    elif phase == 'ROUND_DONE':
                        hint = '本轮已记录。按空格查看下一轮要求，再按空格开始'
                        if trials.index == 9:
                            hint = '10轮均已记录。按空格确认结束并保存汇总'
                    raw_text = ', '.join(f"{x['raw_label']} {x['confidence']:.2f}" for x in detections[:3]) or '无'
                    body_names = {'Left': '身体向左', 'Right': '身体向右'}
                    user_text = ', '.join(body_names.get(x['user_label'], '其他手势:'+x['user_label'])
                                          for x in detections[:3]) or '未检测到方向'
                    if {'Left','Right'} <= {x['raw_label'] for x in detections}:
                        user_text = '左右同时出现（冲突，不算正确）'
                    counts_text = '只统计固定10轮；失败也进入下一轮，不改变模型或阈值。'
                    if phase == 'ROUND_DONE':
                        rates = trials.results[-1]['rates']
                        counts_text = f"本轮：正确{rates['correct']:.1%}，冲突{rates['left_right_conflict']:.1%}，漏检{rates['no_detection']:.1%}"
                    lines = [f'目标：身体向{direction} | 原图应为{display_label(trials.target)} | 第{trials.index%5+1}/5轮',
                             f'只伸食指指向身体{direction}侧；保持同一只手、距离和光照。',
                             hint, f'原图模型输出（未改标签）：{raw_text}',
                             f'换算后的身体方向：{user_text}', counts_text,
                             '空格确认/开始；Q退出；本轮结束后放下手，下一轮重新摆好。']
                cv2.imshow(window, np.vstack([banner(lines, font), cv2.resize(shown_frame,(960,720))]))
                now = time.monotonic()
                if now-last_status > 1:
                    status()
                    last_status = now
                key = cv2.waitKey(1) & 0xff
                if key in (27,ord('q'),ord('Q')) or cv2.getWindowProperty(window,cv2.WND_PROP_VISIBLE)<1:
                    reason = 'user_quit'
                    break
                if key == 32:
                    deliberate = now-last_space >= .8
                    last_space = now
                    if deliberate:
                        if model is None:
                            model = YOLO(str(weight),task='detect')
                            assert [model.names[i] for i in range(7)] == ['Down','Left','Right','Stop','Thumbs Down','Thumbs up','Up']
                            last_space = time.monotonic()
                            event('MIRROR_DIRECTION_USER_CONFIRMED')
                            print('MODEL_LOADED: waiting for SPACE for left trial 1.', flush=True)
                        else:
                            old_phase = trials.phase
                            if trials.space(now):
                                event('USER_SPACE', before=old_phase, after=trials.phase, trial=trials.index+1)
                            if trials.phase == 'COMPLETE':
                                reason = 'fixed_ten_trials_complete'
                                break
                        status()
            else:
                reason = 'bounded_timeout'
    except Exception as exc:
        reason = repr(exc)
        (run/'error.txt').write_text(traceback.format_exc(),encoding='utf-8')
        traceback.print_exc()
    finally:
        if cap is not None:
            cap.release()
        cv2.destroyAllWindows()
        status()
        write('result.json',dict(result='FIXED_LR_BASELINE_COMPLETE' if trials.phase=='COMPLETE'
              else 'FIXED_LR_BASELINE_INCOMPLETE', stop_reason=reason,
              frames=frame_count, inference_frames=inference_count, trials=trials.results,
              pipeline_ms_percentiles={str(p):float(np.percentile(latencies,p)) for p in [50,95,99]} if latencies else {},
              accuracy_validated=False, temporal_filter=False))
        print(reason, flush=True)


if __name__ == '__main__':
    main()
