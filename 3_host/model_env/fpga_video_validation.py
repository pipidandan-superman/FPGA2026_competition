"""OV56 video acceptance, then explicitly enabled five-gesture CPU validation."""
import argparse
import hashlib
import json
from pathlib import Path
import queue
import sys
import time
import traceback
import cv2
import numpy as np
import torch
from PIL import ImageFont
from ultralytics import YOLO
from webcam_validation import banner, EXPECTED_SHA
from manual_gesture_protocol import GESTURES, ManualProtocol
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'udp_video'))
from validated_receiver import Receiver

ERRORS=('bad_packet','bad_header','inconsistent_header','crc_error','lost_frames','incomplete_frames')
SELECTED=[x for x in GESTURES if x[0] not in ('Left','Right')]


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--run-dir',required=True)
    args=ap.parse_args()
    run=Path(args.run_dir).resolve()
    assert run.is_relative_to(Path('E:/competition/4_metrics/logs').resolve())
    run.mkdir(parents=True,exist_ok=True)
    if (run/'rx_frames.jsonl').exists():
        raise RuntimeError('Fresh run required')
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25)
    weight=Path(__file__).resolve().parents[2]/'3_host/model/best.pt'
    protocol=ManualProtocol(gestures=SELECTED,minimum_frames=15,minimum_streak=5)
    model=None
    receiver=None
    started=time.monotonic()
    first_frame=None
    window_start=None
    base_stats={}
    last=None
    last_status=0
    last_space=-100
    inference_count=0
    latencies=[]
    reason='running'
    gate_pass=False
    gate_report=None
    window='FPGA Ethernet Video + Model - SPACE / R / Q'
    picture=np.zeros((720,960,3),dtype=np.uint8)
    detection_text='模型尚未启动'
    raw_log=(run/'rx_frames.jsonl').open('x',encoding='utf-8')
    infer_log=(run/'predictions.jsonl').open('x',encoding='utf-8')

    def write(name,data):
        tmp=run/(name+'.tmp')
        tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
        tmp.replace(run/name)

    def event(kind,**data):
        with (run/'events.jsonl').open('a',encoding='utf-8') as f:
            f.write(json.dumps(dict(event=kind,time=time.monotonic()-started,**data))+'\n')

    def received(frame):
        raw_log.write(json.dumps(dict(fid=frame.fid,board_timestamp=frame.timestamp,
                      crc32=frame.crc,received_at=frame.received_at))+'\n')
        raw_log.flush()

    try:
        assert hashlib.sha256(weight.read_bytes()).hexdigest()==EXPECTED_SHA
        torch.set_num_threads(2)
        write('config.json',dict(source='192.168.240.10',port=5000,geometry=[640,480,3],
              byte_order='BGR',mirror=False,weight=str(weight),sha256=EXPECTED_SHA,
              imgsz=640,conf=.45,iou=.7,device='cpu',raw_gate_seconds=60,
              raw_gate_minimum_frames=240,warmup_seconds=3,raw_gate_errors=list(ERRORS),
              minimum_frames_per_trial=15,minimum_streak=5,observe_seconds=5,
              gestures=SELECTED,rounds=3,left_right='logged but never effective action',
              images_saved=False,video_saved=False,frame_max_age_seconds=1))
        receiver=Receiver(on_frame=received)
        receiver.start()
        if not receiver.ready.wait(3) or receiver.error:
            raise RuntimeError(receiver.error or 'Receiver startup timeout')
        cv2.namedWindow(window,cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window,960,1000)
        print('RAW_VIDEO_ONLY: waiting for FPGA UDP frames.',flush=True)
        while time.monotonic()-started < 3600:
            if (run/'STOP').exists():
                reason='stop_file'; break
            if receiver.error:
                raise RuntimeError(receiver.error)
            now=time.monotonic()
            fresh=None
            try: fresh=receiver.frames.get_nowait()
            except queue.Empty: pass
            if fresh and now-fresh.received_at <= 1:
                last=fresh
                if first_frame is None: first_frame=now
                image=np.frombuffer(fresh.data,dtype=np.uint8).reshape(480,640,3)
                shown=image
                if model:
                    t0=time.perf_counter()
                    result=model.predict(image,device='cpu',imgsz=640,rect=False,
                                         conf=.45,iou=.7,verbose=False,save=False)[0]
                    ms=(time.perf_counter()-t0)*1000
                    latencies.append(ms)
                    inference_count+=1
                    detections=[dict(label=result.names[int(b.cls.item())],confidence=float(b.conf.item()),
                                xyxy=[float(v) for v in b.xyxy[0].tolist()]) for b in result.boxes]
                    labels={d['label'] for d in detections}
                    effective=next(iter(labels)) if len(labels)==1 and labels <= {g[0] for g in SELECTED[:-1]} else 'UNKNOWN'
                    previous=protocol.phase
                    row=protocol.tick(time.monotonic(),labels)
                    if row:
                        event('ROUND_RESULT',result=row)
                        write('trials.json',protocol.snapshot())
                    infer_log.write(json.dumps(dict(fid=fresh.fid,arrival=fresh.received_at,
                                    inference_ms=ms,expected=protocol.gesture[0],
                                    phase_before=previous,phase_after=protocol.phase,
                                    raw_detections=detections,effective_action=effective))+'\n')
                    infer_log.flush()
                    shown=result.plot()
                    detection_text=', '.join(f"{d['label']} {d['confidence']:.2f}" for d in detections[:3]) or '无检测'
                picture=cv2.resize(shown,(960,720))
            stats=dict(receiver.parser.stats)
            if first_frame is not None and window_start is None and now-first_frame>=3:
                window_start=now; base_stats=stats.copy()
            delta={k:stats.get(k,0)-base_stats.get(k,0) for k in ERRORS}
            elapsed=now-window_start if window_start else 0
            n=stats.get('complete_frames',0)-base_stats.get('complete_frames',0)
            stale=last is None or now-last.received_at>1
            if not gate_pass and window_start and elapsed>=60 and n>=240 and not any(delta.values()) and not stale:
                gate_pass=True
                gate_report=dict(result='UDP_RAW_NUMERIC_GATE_PASS',seconds=elapsed,frames=n,
                                 fps=n/elapsed,error_deltas=delta,stats=stats,
                                 visual_confirmation='separately confirmed before enabling model')
                write('raw_gate.json',gate_report)
                print('UDP_RAW_NUMERIC_GATE_PASS: waiting for ENABLE_MODEL.',flush=True)
            if stale and model and protocol.phase in ('PREPARE','OBSERVE'):
                event('ROUND_ABORT_STALE',before=protocol.snapshot())
                protocol.reset_item()
                write('trials.json',protocol.snapshot())
            if model is None and gate_pass and not stale and (run/'ENABLE_MODEL').exists():
                model=YOLO(str(weight),task='detect')
                assert [model.names[i] for i in range(7)]==['Down','Left','Right','Stop','Thumbs Down','Thumbs up','Up']
                event('MODEL_ENABLED',raw_gate=gate_report)
                print('MODEL_ENABLED: waiting for SPACE on Stop gesture.',flush=True)
                # Frames captured during loading are not counted as trial observations.
                last_space=time.monotonic()
            if model is None:
                lines=['FPGA网口视频验收：模型尚未启动',
                       f'完整帧 {stats.get("complete_frames",0)} | 验收 {elapsed:.0f}/60秒 | {n/max(elapsed,1):.2f}fps',
                       f'CRC错 {delta["crc_error"]} | 丢帧 {delta["lost_frames"]} | 不完整 {delta["incomplete_frames"]}',
                       '数值验收通过，等待开启模型' if gate_pass else '请挥动手，确认原始画面颜色正常且随动作更新。',
                       '当前仅显示原始BGR画面，不镜像，不保存视频。',
                       '收到完整新帧才更新；网络和模型统计分别记录。',
                       'Q / Esc退出；模型由验收门槛控制，暂不按空格。']
            else:
                label,chinese,instruction=protocol.gesture
                hint='准备好按空格开始本轮：3秒准备、5秒保持'
                if protocol.phase in ('PREPARE','OBSERVE'):
                    hint=('准备' if protocol.phase=='PREPARE' else '检测保持')+f' {max(0,protocol.deadline-now):.1f}秒'
                elif protocol.phase=='ROUND_PASS': hint='本轮通过；放下手再摆好，按空格开始下一轮'
                elif protocol.phase=='ROUND_FAIL': hint='本轮未通过；保持当前项，调整后按空格重试'
                elif protocol.phase=='ITEM_PASS': hint='本项3轮通过；按空格确认下一项或完成'
                lines=[f'FPGA视频模型：{chinese} ({label}) | 连续通过{protocol.passed_rounds}/3',
                       instruction,hint,'原始预测：'+detection_text,
                       f'有效新帧推理 {inference_count} | 接收 {stats.get("complete_frames",0)} | 不重复计分旧帧',
                       '左右仅记录，不作为有效动作；每轮>=15帧，连续正确>=5帧。',
                       '空格开始/确认；R重置本项；Q退出；五类及无手逐项验证。']
            if stale: lines[2]='视频尚未到达或已中断：当前不产生有效动作、不计分。'
            cv2.imshow(window,np.vstack([banner(lines,font),picture]))
            if now-last_status>=1:
                write('status.json',dict(stage='MODEL' if model else 'RAW_VIDEO',
                      stale=stale,raw_gate_pass=gate_pass,raw_window_seconds=elapsed,
                      raw_window_frames=n,raw_error_deltas=delta,rx_stats=stats,
                      last_fid=last.fid if last else None,inference_frames=inference_count,
                      elapsed_seconds=now-started,protocol=protocol.snapshot()))
                last_status=now
            key=cv2.waitKey(10)&0xff
            if key in (27,ord('q'),ord('Q')) or cv2.getWindowProperty(window,cv2.WND_PROP_VISIBLE)<1:
                reason='user_quit'; break
            if model and not stale:
                if key in (ord('r'),ord('R')):
                    event('USER_RESET',before=protocol.snapshot()); protocol.reset_item()
                if key==32:
                    deliberate=now-last_space>=.8; last_space=now
                    if deliberate:
                        before=protocol.snapshot()
                        if protocol.press_space(now): event('USER_SPACE',before=before,after=protocol.snapshot())
                        if protocol.phase=='COMPLETE': reason='guided_sequence_complete'; break
        else: reason='bounded_timeout'
    except Exception as exc:
        reason=repr(exc)
        (run/'error.txt').write_text(traceback.format_exc(),encoding='utf-8')
        traceback.print_exc()
    finally:
        if receiver: receiver.stop()
        raw_log.close(); infer_log.close()
        cv2.destroyAllWindows()
        write('result.json',dict(result='FPGA_PC_MODEL_GUIDED_COMPLETE' if protocol.phase=='COMPLETE' else 'INCOMPLETE',
              stop_reason=reason,raw_gate=gate_report,inference_frames=inference_count,
              receiver_error=receiver.error if receiver else None,
              rx_stats=dict(receiver.parser.stats) if receiver else {},protocol=protocol.snapshot(),
              inference_ms_percentiles={str(p):float(np.percentile(latencies,p)) for p in [50,95,99]} if latencies else {}))
        print(reason,flush=True)


if __name__=='__main__': main()
