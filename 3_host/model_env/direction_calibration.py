"""Unscored, manually annotated direction calibration. Never remap labels."""
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
from PIL import Image, ImageDraw, ImageFont
from ultralytics import YOLO
from webcam_validation import EXPECTED_SHA


class Gate:
    def __init__(self):
        self.index = 0
        self.phase = 'READY'
        self.deadline = 0
        self.observed_direction = None

    def key(self, key, now):
        if self.phase == 'READY' and key == 32:
            self.phase, self.deadline = 'PREPARE', now+3
        elif self.phase == 'REVIEW' and key in (ord('a'), ord('d')):
            self.observed_direction = 'image_left' if key == ord('a') else 'image_right'
            self.phase = 'CONFIRMED'
        elif self.phase == 'CONFIRMED' and key == 32:
            if self.index == 1:
                self.phase = 'COMPLETE'
            else:
                self.index = 1
                self.observed_direction = None
                self.phase = 'READY'

    def tick(self, now):
        if self.phase == 'PREPARE' and now >= self.deadline:
            self.phase, self.deadline = 'OBSERVE', now+5
        elif self.phase == 'OBSERVE' and now >= self.deadline:
            self.phase = 'REVIEW'


def header(lines, font, height=250):
    img = Image.new('RGB', (1280,height), (20,25,32))
    draw = ImageDraw.Draw(img)
    for i,line in enumerate(lines):
        draw.text((14,8+i*38),line,font=font,fill=(120,240,170) if i<2 else (240,240,240))
    return cv2.cvtColor(np.asarray(img),cv2.COLOR_RGB2BGR)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--run-dir',required=True)
    args=parser.parse_args()
    run=Path(args.run_dir).resolve()
    assert run.is_relative_to(Path('E:/competition/4_metrics/logs').resolve())
    run.mkdir(parents=True,exist_ok=True)
    if (run/'frames.jsonl').exists():
        raise RuntimeError('Use a fresh run')
    weight=Path(__file__).resolve().parents[2]/'3_host/model/best.pt'
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25)
    gate=Gate()
    cap=model=None
    frozen=None
    last_detections=[]
    counts=Counter()
    samples=0
    results=[]
    total=0
    started=time.monotonic()
    last_status=0
    last_key=-100
    reason='running'
    window='Direction Calibration - RAW | MIRROR - SPACE / A / D / Q'

    def write(name,data):
        tmp=run/(name+'.tmp')
        tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
        tmp.replace(run/name)

    def status():
        write('status.json',dict(phase=gate.phase if model else 'PREVIEW',
              item=gate.index+1,physical_prompt='own_right' if gate.index==0 else 'own_left',
              capture_frames=total,sampled_frames=samples,elapsed_seconds=time.monotonic()-started,
              completed_annotations=len(results),stop_reason=reason))

    try:
        assert hashlib.sha256(weight.read_bytes()).hexdigest()==EXPECTED_SHA
        torch.set_num_threads(2)
        cap=cv2.VideoCapture(0,cv2.CAP_DSHOW)
        if not cap.isOpened():
            raise RuntimeError('Camera open failed')
        cap.set(cv2.CAP_PROP_FRAME_WIDTH,640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT,480)
        cap.set(cv2.CAP_PROP_FPS,30)
        write('config.json',dict(model=str(weight),sha256=EXPECTED_SHA,camera=0,
              backend=cap.getBackendName(),model_input_flip=False,
              left_pane='raw',right_pane='horizontal_flip_display_only',
              label_remapping=False,accuracy_scoring=False,conf=0.45,iou=0.7,imgsz=640,
              device='cpu',sequence=['own_right','own_left'],
              annotation='A/D annotate frozen final sampled frame in RAW pane only',
              images_saved=False,video_saved=False))
        cv2.namedWindow(window,cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window,1280,780)
        print('PREVIEW: raw and mirror panes; SPACE loads model.',flush=True)
        with (run/'frames.jsonl').open('x',encoding='utf-8') as out:
            while time.monotonic()-started<1800:
                if (run/'STOP').exists():
                    reason='stop_file'
                    break
                ok,frame=cap.read()
                if not ok or frame is None:
                    raise RuntimeError('Camera read failed')
                total+=1
                now=time.monotonic()
                if model:
                    gate.tick(now)
                if gate.phase not in ('REVIEW','CONFIRMED'):
                    detections=[]
                    raw=frame.copy()
                    if model:
                        prediction=model.predict(frame,device='cpu',imgsz=640,rect=False,
                                                 conf=0.45,iou=0.7,verbose=False,save=False)[0]
                        for box in prediction.boxes:
                            label=prediction.names[int(box.cls.item())]
                            xyxy=[float(v) for v in box.xyxy[0].tolist()]
                            confidence=float(box.conf.item())
                            detections.append(dict(raw_label=label,confidence=confidence,raw_xyxy=xyxy))
                            x1,y1,x2,y2=map(int,xyxy)
                            cv2.rectangle(raw,(x1,y1),(x2,y2),(60,240,100),2)
                            cv2.putText(raw,f'raw:{label} {confidence:.2f}',(x1,max(18,y1-5)),
                                        cv2.FONT_HERSHEY_SIMPLEX,.6,(60,240,100),2)
                        out.write(json.dumps(dict(elapsed_seconds=now-started,frame=total,
                                  physical_prompt='own_right' if gate.index==0 else 'own_left',
                                  sampled=gate.phase=='OBSERVE',detections=detections))+'\n')
                        out.flush()
                    # Flip only the clean image. Raw labels remain in left pane/header.
                    panes=np.hstack([cv2.resize(raw,(640,480)),cv2.resize(cv2.flip(frame,1),(640,480))])
                    if gate.phase=='OBSERVE':
                        samples+=1
                        counts.update({d['raw_label'] for d in detections})
                        frozen=(panes.copy(),total)
                        last_detections=detections
                else:
                    if frozen is None:
                        raise RuntimeError('No calibration frame captured')
                    panes=frozen[0]
                    detections=last_detections
                direction='右' if gate.index==0 else '左'
                if model is None:
                    lines=['方向校准：左窗原始画面，右窗镜像画面（不评分）',
                           '标签保持模型原文，不进行 Left/Right 对调。',
                           '按空格加载模型；随后先做你实际向右的动作。',
                           '每项3秒准备、5秒采集，结束冻结画面等待你确认。',
                           '只伸食指；不要根据预测结果改方向。Q / Esc退出。',
                           '冻结后：看左窗原始画面，指尖朝图像左按A，朝图像右按D。']
                else:
                    hint='摆好手势后按空格开始；不以模型标签判断是否做对。'
                    if gate.phase in ('PREPARE','OBSERVE'):
                        hint=('准备' if gate.phase=='PREPARE' else '采集，保持动作')+f'：{max(0,gate.deadline-now):.1f} 秒'
                    elif gate.phase=='REVIEW':
                        hint='画面已冻结：左窗指尖朝图像左按A，朝图像右按D。'
                    elif gate.phase=='CONFIRMED':
                        hint='方向已记录。按空格进入下一项说明。' if gate.index==0 else '方向已记录。按空格结束校准。'
                    shown=', '.join(f"{d['raw_label']} {d['confidence']:.2f}" for d in detections[:3]) or '无检测'
                    lines=[f'第{gate.index+1}/2项：食指指向你实际的{direction}侧（身体方向）',
                           hint, '模型原始标签：'+shown,
                           '左窗是原图及原始标签；右窗仅镜像预览，不附加方向判断。',
                           '采集结束后必须按A/D标注，再按空格才能换项。',
                           '空格确认/开始；A=原图指尖向左，D=原图指尖向右；Q退出。']
                panel_header=header(['左窗：原始图像  ← 图像左 / 图像右 →             右窗：水平镜像预览'],font,45)
                cv2.imshow(window,np.vstack([header(lines,font),panel_header,panes]))
                if now-last_status>1:
                    status()
                    last_status=now
                key=cv2.waitKey(1)&0xff
                if key in (27,ord('q'),ord('Q')) or cv2.getWindowProperty(window,cv2.WND_PROP_VISIBLE)<1:
                    reason='user_quit'
                    break
                if key in (32,ord('a'),ord('A'),ord('d'),ord('D')):
                    deliberate=now-last_key>=.8
                    last_key=now
                    if deliberate:
                        if model is None and key==32:
                            model=YOLO(str(weight),task='detect')
                            assert [model.names[i] for i in range(7)]==['Down','Left','Right','Stop','Thumbs Down','Thumbs up','Up']
                            last_key=time.monotonic()
                            print('MODEL_LOADED: waiting for own-right action.',flush=True)
                        elif model:
                            previous=gate.phase
                            old_index=gate.index
                            gate.key(ord(chr(key).lower()) if key!=32 else key,now)
                            if previous=='REVIEW' and gate.phase=='CONFIRMED':
                                results.append(dict(physical_prompt='own_right' if gate.index==0 else 'own_left',
                                      user_annotated_raw_direction=gate.observed_direction,
                                      annotated_frame=frozen[1],raw_detections=last_detections,
                                      sampled_frames=samples,label_presence_counts=dict(counts),
                                      annotation_scope='frozen final sampled frame, not all frames'))
                                write('annotations.json',results)
                                print('ANNOTATED: '+json.dumps(results[-1]),flush=True)
                            if gate.index!=old_index:
                                counts=Counter()
                                samples=0
                                frozen=None
                            if gate.phase=='COMPLETE':
                                reason='direction_calibration_complete'
                                break
                        status()
            else:
                reason='bounded_timeout'
    except Exception as exc:
        reason=repr(exc)
        (run/'error.txt').write_text(traceback.format_exc(),encoding='utf-8')
        traceback.print_exc()
    finally:
        if cap is not None:
            cap.release()
        cv2.destroyAllWindows()
        status()
        write('result.json',dict(result='DIRECTION_CALIBRATION_COMPLETE' if gate.phase=='COMPLETE'
              else 'DIRECTION_CALIBRATION_INCOMPLETE',stop_reason=reason,
              annotations=results,accuracy_scoring=False,label_remapping=False))
        print(reason,flush=True)


if __name__=='__main__':
    main()
