"""Read-only camera signal diagnosis: numeric statistics, no frame files."""
import argparse
import json
from pathlib import Path
import time
import cv2
import numpy as np

p = argparse.ArgumentParser()
p.add_argument('--output', required=True)
p.add_argument('--backend', choices=['DSHOW','MSMF'], default='DSHOW')
p.add_argument('--fourcc', choices=['MJPG','YUY2'])
p.add_argument('--native', action='store_true', help='Use the camera default format without setting capture properties')
a = p.parse_args()
cap = cv2.VideoCapture(0, getattr(cv2,'CAP_'+a.backend))
report = {'backend':a.backend, 'opened':cap.isOpened(), 'frames':[]}
try:
    if not cap.isOpened():
        raise RuntimeError('Camera unavailable')
    if not a.native:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH,640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT,480)
        cap.set(cv2.CAP_PROP_FPS,30)
    report['native_defaults'] = a.native
    if a.fourcc:
        report['fourcc_set_accepted'] = cap.set(cv2.CAP_PROP_FOURCC,cv2.VideoWriter_fourcc(*a.fourcc))
        report['requested_fourcc'] = a.fourcc
    report['properties'] = {n:cap.get(getattr(cv2,'CAP_PROP_'+n)) for n in ['FRAME_WIDTH','FRAME_HEIGHT','FPS','FOURCC','EXPOSURE','AUTO_EXPOSURE','BRIGHTNESS','GAIN']}
    prev = None
    start = time.monotonic()
    for i in range(10):
        t = time.monotonic()
        ok, frame = cap.read()
        if not ok:
            raise RuntimeError('Capture read failed')
        gray = cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY)
        center = gray[gray.shape[0]//4:gray.shape[0]*3//4,gray.shape[1]//4:gray.shape[1]*3//4]
        item = dict(frame=i, read_ms=round((time.monotonic()-t)*1000,2),
                    mean=float(gray.mean()), std=float(gray.std()), minimum=int(gray.min()), maximum=int(gray.max()),
                    black_fraction=float((gray<5).mean()), center_mean=float(center.mean()),
                    mean_abs_change=float(cv2.absdiff(gray,prev).mean()) if prev is not None else None)
        report['frames'].append(item)
        print(json.dumps(item),flush=True)
        prev=gray
    report['elapsed_seconds']=time.monotonic()-start
finally:
    cap.release()
    Path(a.output).write_text(json.dumps(report,indent=2),encoding='utf-8')
