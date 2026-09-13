"""Real OV56 video -> pinned YOLO -> stability gate -> UDP/AXI -> PL COM4.

No synthetic predictions and no serial writes. Human gesture/LED acceptance
is separate from the machine byte/sequence checks saved by this entrypoint.
"""
import argparse
import json
from pathlib import Path
import queue
import subprocess
import threading
import time
from gesture_viewer import load_model, EXPECTED_SHA
from action_link import ActionPublisher
from action_protocol import UartFrames, uart_frame
from validated_receiver import Receiver, Reassembler, HEADER


class Synchronized(Reassembler):
    def __init__(self):
        super().__init__()
        self.synced = False
    def feed(self, packet, now):
        if not self.synced:
            if len(packet) == HEADER.size+1440 and HEADER.unpack_from(packet)[5] == 0:
                self.synced = True
            else:
                self.stats['startup_packets_discarded'] += 1
                return None
        return super().feed(packet, now)


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--run-dir',type=Path,required=True)
    p.add_argument('--seconds',type=float,default=180)
    args=p.parse_args()
    if not args.run_dir.resolve().is_relative_to(Path('E:/competition/4_metrics/logs')) or not 30 <= args.seconds <= 600:
        p.error('Use a new evidence directory and duration 30..600')
    args.run_dir.mkdir(parents=True,exist_ok=False)
    (args.run_dir/'yolo_config').mkdir()
    import os
    os.environ.update(YOLO_CONFIG_DIR=str(args.run_dir/'yolo_config'),YOLO_AUTOINSTALL='false',YOLO_OFFLINE='true')
    events=(args.run_dir/'events.jsonl').open('x',buffering=1)
    predictions=(args.run_dir/'predictions.jsonl').open('x',buffering=1)
    lock=threading.Lock()
    confirmed=[]
    def emit(kind,**data):
        row=dict(event=kind,monotonic=time.monotonic(),**data)
        with lock:
            events.write(json.dumps(row)+'\n')
            if kind in ('ACTION_INITIAL_CLEAR','ACTION_CONFIRMED','ACTION_CLOSE_CLEAR'):
                confirmed.append(row)
        print(json.dumps(row),flush=True)
    receiver=publisher=proc=None
    status=dict(state='INCOMPLETE')
    serial_log=(args.run_dir/'serial_console.txt').open('x',buffering=1)
    try:
        model=load_model()
        import numpy as np
        import cv2
        # CPU warmup is not inference acceptance and never enters the publisher.
        model.predict(np.zeros((480,640,3),dtype=np.uint8),device='cpu',imgsz=640,rect=False,verbose=False)
        emit('MODEL_LOADED',sha256=EXPECTED_SHA,names=model.names)
        ready=threading.Event()
        proc=subprocess.Popen(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(Path(__file__).with_name('serial_capture.ps1')),'-Port','COM4','-Output',str(args.run_dir/'com4.bin'),'-Seconds',str(args.seconds+15)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        def drain():
            for line in proc.stdout:
                serial_log.write(line); serial_log.flush()
                if 'SERIAL_CAPTURE_READY' in line: ready.set()
        reader=threading.Thread(target=drain,daemon=True)
        reader.start()
        if not ready.wait(5): raise RuntimeError('COM4 not ready')
        receiver=Receiver()
        receiver.parser=Synchronized()
        receiver.start()
        if not receiver.ready.wait(3) or receiver.error: raise RuntimeError('UDP receiver not ready')
        publisher=ActionPublisher(emit)
        started=time.monotonic()
        count=0
        saved={}
        emit('REAL_MODEL_WINDOW_BEGIN',seconds=args.seconds)
        while time.monotonic()-started<args.seconds:
            if receiver.error or publisher.error:
                raise RuntimeError(repr((receiver.error,publisher.error)))
            try: frame=receiver.frames.get(timeout=.2)
            except queue.Empty: continue
            if time.monotonic()-frame.received_at>=1: continue
            image=np.frombuffer(frame.data,dtype=np.uint8).reshape(480,640,3)
            before=time.monotonic()
            result=model.predict(image,device='cpu',imgsz=640,rect=False,conf=.45,iou=.7,verbose=False,save=False)[0]
            detections=[dict(label=result.names[int(b.cls.item())],confidence=float(b.conf.item()),xyxy=b.xyxy[0].tolist()) for b in result.boxes]
            row=dict(fid=frame.fid,arrival=frame.received_at,inference_finished=time.monotonic(),inference_ms=(time.monotonic()-before)*1000,detections=detections)
            predictions.write(json.dumps(row)+'\n')
            publisher.feed(row)
            count+=1
            for label in {d['label'] for d in detections if d['confidence']>=.75}:
                n=saved.get(label,0)
                if n<3:
                    cv2.imwrite(str(args.run_dir/(label.replace(' ','_')+'_'+str(frame.fid)+'.jpg')),image)
                    saved[label]=n+1
            if count%25==0: emit('INFERENCE_PROGRESS',frames=count,latest=detections)
        publisher.close()
        receiver.stop()
        proc.wait(timeout=25)
        reader.join(2)
        raw=(args.run_dir/'com4.bin').read_bytes()
        parsed=UartFrames()
        frames=parsed.feed(raw)
        expected=[uart_frame(row['seq'],row['action']) for row in confirmed]
        actions=sorted({row['action'] for row in confirmed if row['event']=='ACTION_CONFIRMED' and row.get('decision',{}).get('reason')=='stable'})
        bad=('bad_header','bad_packet','crc_error','lost_frames','inconsistent_header','incomplete_frames')
        passed=(not publisher.error and not receiver.error and proc.returncode==0 and frames==expected and raw==b''.join(expected) and not parsed.errors and not parsed.discarded and not parsed.buffer and bool(actions) and all(receiver.parser.stats[k]==0 for k in bad))
        status=dict(state='PASS' if passed else 'FAIL',marker='REAL_MODEL_AXI_UART_CHECK',inference_frames=count,stable_actions=actions,confirmed=len(confirmed),serial_bytes=len(raw),expected_bytes=sum(map(len,expected)),publisher_error=publisher.error,rx_stats=dict(receiver.parser.stats),physical_led='USER_CONFIRMATION_REQUIRED',model_sha256=EXPECTED_SHA)
    except BaseException as exc:
        status=dict(state='FAIL',error=repr(exc))
    finally:
        if publisher is not None and publisher.thread.is_alive(): publisher.close()
        if receiver is not None: receiver.stop()
        if proc is not None and proc.poll() is None:
            proc.terminate(); proc.wait(timeout=5)
        emit('FINAL',**status)
        (args.run_dir/'result.json').write_text(json.dumps(status,indent=2))
        events.close(); predictions.close(); serial_log.close()
    return 0 if status['state']=='PASS' else 1

if __name__=='__main__': raise SystemExit(main())
