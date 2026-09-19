"""PS 运行时离线自检：包驱动整数推理 vs G2 128 帧回归记录（逐位一致门）。

验证三件事：
  1. rom_data 包自洽（manifest SHA-256 全对，包单独可跑，无 torch 依赖）；
  2. schedule.json 执行器输出与 G2 int_forward 原始头逐字节一致（raw_head_sha256）；
  3. 解码链框/分数/类别与回归记录一致（舍入后精确相等）。
"""
import json
import hashlib
import sys
import time
from pathlib import Path

import numpy as np
import cv2

HERE = Path(__file__).resolve().parent
ROOT = Path('E:/competition')
PYNQ = ROOT / '2_fpga/3_yolo_zynq/pynq'
ROM = ROOT / '2_fpga/3_yolo_zynq/rom_data'
G2 = ROOT / '4_metrics/logs/2026-09-15_yolo7020_g2_quant_rne_run04'
DATASET = ROOT / '3_host/model_datasets/dataset'

sys.path.insert(0, str(PYNQ))
from yolo_runtime import YoloRuntime
from yolo_decode import decode_all, letterbox_u8_rgb

L = []


def log(m=''):
    print(m, flush=True)
    L.append(str(m))


hv = YoloRuntime(ROM).pkg.verify_hashes()
assert all(hv.values()), f'package hash mismatch: {hv}'
log(f'[1] package hashes: {len(hv)}/{len(hv)} match')

rt = YoloRuntime(ROM)
log(f'[2] schedule: {len(rt.sched["tasks"])} tasks, {len(rt.sched["buffers"])} buffers, '
    f'input {rt.size}x{rt.size}')

reg = json.loads((G2 / 'regression_128frames.json').read_text(encoding='utf-8'))
t0 = time.time()
n_head_ok = n_box_ok = 0
fails = []
for k, e in enumerate(reg):
    im = DATASET / e['split'] / 'images' / e['image']
    canvas = letterbox_u8_rgb(cv2.imread(str(im)), rt.size)
    regs, clss, rs, cs = rt.run(canvas)
    hh = hashlib.sha256()
    for r in regs + clss:
        hh.update(r.tobytes())
    head_ok = hh.hexdigest() == e['raw_head_sha256']
    bx, cf, ki = decode_all(regs, clss, rs, cs)
    bx = np.round(bx, 2).tolist()
    cf = np.round(cf, 4).tolist()
    ki = ki.tolist()
    box_ok = (bx == e['boxes'] and cf == e['conf'] and ki == e['cls'])
    n_head_ok += head_ok
    n_box_ok += box_ok
    if not (head_ok and box_ok):
        fails.append({'i': k, 'image': e['image'], 'head': head_ok, 'box': box_ok})
    if k < 3 or (not (head_ok and box_ok)):
        log(f'  [{k:3d}] {e["split"]:5s} {e["image"][:28]:28s} head={head_ok} box={box_ok}')

dt = time.time() - t0
log(f'[3] regression: {n_head_ok}/{len(reg)} raw-head byte-exact, '
    f'{n_box_ok}/{len(reg)} decode-exact, {dt:.0f}s ({dt/len(reg)*1000:.0f} ms/frame)')
if fails:
    log(f'    FAILS: {fails[:10]}')

(HERE / 'console.log').write_text('\n'.join(L) + '\n', encoding='utf-8')
result = {'head_exact': n_head_ok, 'decode_exact': n_box_ok, 'frames': len(reg),
          'fails': fails, 'ms_per_frame': dt / len(reg) * 1000}
(HERE / 'offline_check.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
log('# FINAL: ' + ('PS_RUNTIME_OFFLINE_PASS' if not fails else 'PS_RUNTIME_OFFLINE_FAIL'))
