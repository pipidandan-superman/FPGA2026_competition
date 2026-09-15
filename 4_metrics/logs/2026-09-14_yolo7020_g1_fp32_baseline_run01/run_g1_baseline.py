"""G1: FP32 float baseline for YOLOv8n gesture model at 640/416/320.

Read-only with respect to model weights and the v6 dataset export; all outputs
land in this run directory. Follows deployment plan r3 sections 4.4, 10.2 and
13.3 (first software work package).

Stages:
  1. weights manifest (SHA-256 of best.pt / best.onnx)
  2. absolute-path dataset config (original data.yaml untouched) + parse check
  3. dataset manifests: file lists + hashes + per-split per-class box counts
  4. calibration list (stratified from train, fixed seed, ~60 img/class target)
  5. numpy letterbox preprocess reference + equivalence check vs ultralytics
  6. FP32 val() at 640/416/320 on valid and test; size loss recorded separately
"""
from pathlib import Path
import os
import sys
import json
import time
import random
import hashlib

RUN = Path(__file__).resolve().parent
ROOT = Path('E:/competition')
DATASET = ROOT / '3_host/model_datasets/dataset'
WEIGHTS = ROOT / '3_host/model/best.pt'
ONNX = ROOT / '3_host/model/best.onnx'
SIZES = [640, 416, 320]
CAL_PER_CLASS_TARGET = 60
SEED = 20260914

for key, leaf in [('YOLO_CONFIG_DIR', 'ultralytics_config'), ('MPLCONFIGDIR', 'matplotlib_config')]:
    os.environ[key] = str(RUN / leaf)
    (RUN / leaf).mkdir(exist_ok=True)
os.environ.update(YOLO_OFFLINE='true', YOLO_AUTOINSTALL='false',
                  PYTHONNOUSERSITE='1', PYTHONDONTWRITEBYTECODE='1',
                  OMP_NUM_THREADS='2', MKL_NUM_THREADS='2', PYTHONHASHSEED=str(SEED))

import numpy as np
import torch
import ultralytics
from ultralytics import YOLO, settings
from ultralytics.utils import USER_CONFIG_DIR

assert Path(USER_CONFIG_DIR).resolve().is_relative_to(RUN)
settings.update({'sync': False, 'runs_dir': str(RUN / 'predictions'),
                 'datasets_dir': str(RUN / 'datasets'), 'weights_dir': str(RUN / 'weights')})

log_lines = []
def log(msg=''):
    print(msg, flush=True)
    log_lines.append(str(msg))

def sha256_file(p: Path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

status = {}
log(f'# G1 FP32 baseline run | torch {torch.__version__} | ultralytics {ultralytics.__version__}')

# ---------- 1. weights manifest ----------
wm = {'best.pt': {'path': str(WEIGHTS), 'bytes': WEIGHTS.stat().st_size, 'sha256': sha256_file(WEIGHTS)},
      'best.onnx': {'path': str(ONNX), 'bytes': ONNX.stat().st_size, 'sha256': sha256_file(ONNX)}}
status['weights_manifest'] = 'PASS'
log('[1] weights manifest: ' + json.dumps({k: v['sha256'][:16] for k, v in wm.items()}))

# ---------- 2. local absolute-path dataset config ----------
names = ['Down', 'Left', 'Right', 'Stop', 'Thumbs Down', 'Thumbs up', 'Up']
local_yaml = RUN / 'gesture_v6_local.yaml'
local_yaml.write_text(
    f"path: {DATASET.as_posix()}\ntrain: train/images\nval: valid/images\ntest: test/images\n"
    f"nc: 7\nnames: {names}\n", encoding='utf-8')
from ultralytics.data.utils import check_det_dataset
cd = check_det_dataset(str(local_yaml))
assert cd['nc'] == 7 and list(cd['names'].values()) == names and Path(cd['path']) == DATASET
status['local_dataset_config'] = 'PASS'
log('[2] local dataset config parsed: path=' + str(cd['path']))

# ---------- 3. dataset manifests ----------
splits = {}
for split in ['train', 'valid', 'test']:
    img_dir = DATASET / split / 'images'
    lbl_dir = DATASET / split / 'labels'
    imgs = sorted(img_dir.glob('*.jpg')) + sorted(img_dir.glob('*.jpeg')) + sorted(img_dir.glob('*.png'))
    entries, class_boxes = [], {i: 0 for i in range(7)}
    empty_labels = 0
    for im in imgs:
        lb = lbl_dir / (im.stem + '.txt')
        cls_in_img = []
        if lb.exists():
            cls_in_img = [int(line.split()[0]) for line in lb.read_text().splitlines() if line.strip()]
            if not cls_in_img:
                empty_labels += 1
            for c in cls_in_img:
                class_boxes[c] += 1
        entries.append({'image': im.name, 'label': lb.name if lb.exists() else None,
                        'classes': cls_in_img,
                        'image_sha256': sha256_file(im)})
    splits[split] = {'count': len(entries), 'class_boxes': class_boxes,
                     'empty_label_files': empty_labels, 'entries': entries}
    log(f'[3] {split}: {len(entries)} images, class_boxes={class_boxes}, empty_labels={empty_labels}')

dm = {'dataset_root': str(DATASET), 'data_yaml_sha256': sha256_file(DATASET / 'data.yaml'),
      'class_map': {str(i): n for i, n in enumerate(names)}, 'splits': splits,
      'notes': 'per-file image hashes included; label hashes omitted (re-derivable); '
               'distribution caveat: 416x416 stretched export, not native camera 640x480'}
status['dataset_manifests'] = 'PASS'

# ---------- 4. calibration list (stratified, fixed seed) ----------
rng = random.Random(SEED)
train_imgs = splits['train']['entries']
by_class = {c: [e for e in train_imgs if c in e['classes']] for c in range(7)}
for c in range(7):
    rng.shuffle(by_class[c])
cal_set, seen = set(), set()
for c in range(7):
    take = [e['image'] for e in by_class[c] if e['image'] not in seen][:CAL_PER_CLASS_TARGET]
    for t in take:
        cal_set.add(t)
    seen.update(take)
# empty/background frames for scene coverage (images whose label lists no class)
bg = [e['image'] for e in train_imgs if not e['classes']]
rng.shuffle(bg)
cal_bg = bg[:20]
cal_all = sorted(cal_set | set(cal_bg))
(RUN / 'calibration_list.txt').write_text('\n'.join(cal_all) + '\n', encoding='utf-8')
for split in ['valid', 'test']:
    (RUN / f'{split}_list.txt').write_text(
        '\n'.join(e['image'] for e in splits[split]['entries']) + '\n', encoding='utf-8')
cal_box_counts = {i: 0 for i in range(7)}
for e in train_imgs:
    if e['image'] in cal_set:
        for c in e['classes']:
            cal_box_counts[c] += 1
status['calibration_list'] = f'PASS ({len(cal_all)} images, +{len(cal_bg)} background)'
log(f'[4] calibration: {len(cal_set)} class-stratified + {len(cal_bg)} bg = {len(cal_all)}, boxes={cal_box_counts}')

# ---------- 5. numpy letterbox reference + equivalence check ----------
def letterbox_ref(img_bgr: np.ndarray, sz: int, pad_value: int = 114) -> np.ndarray:
    """Deploy-contract preprocess: letterbox to sz x sz, BGR->RGB, /255, HWC->CHW float32."""
    h, w = img_bgr.shape[:2]
    r = min(sz / h, sz / w)
    nh, nw = round(h * r), round(w * r)
    resized = np.zeros((nh, nw, 3), dtype=np.uint8)
    # separable bilinear via torch to match ultralytics cv2 resize closely
    import cv2
    resized = cv2.resize(img_bgr, (nw, nh), interpolation=cv2.INTER_LINEAR)
    canvas = np.full((sz, sz, 3), pad_value, dtype=np.uint8)
    top, left = (sz - nh) // 2, (sz - nw) // 2
    canvas[top:top + nh, left:left + nw] = resized
    out = canvas[:, :, ::-1].transpose(2, 0, 1).astype(np.float32) / 255.0
    return np.ascontiguousarray(out)

from ultralytics.data.augment import LetterBox
import cv2
pre_results = []
check_imgs = []
for split in ['valid']:
    for e in splits[split]['entries'][:2]:
        check_imgs.append(DATASET / split / 'images' / e['image'])
check_imgs.append(None)  # synthetic 640x480 camera-aspect case
worst = 0.0
for idx, p in enumerate(check_imgs):
    if p is not None:
        img = cv2.imread(str(p))
    else:
        rng_np = np.random.RandomState(SEED)
        img = rng_np.randint(0, 255, (480, 640, 3), dtype=np.uint8)
    for sz in SIZES:
        ref = letterbox_ref(img, sz)
        lb = LetterBox(sz, auto=False, scaleup=True)
        ulb = lb(image=img.copy())
        ulb_t = ulb[:, :, ::-1].transpose(2, 0, 1).astype(np.float32) / 255.0
        d = float(np.abs(ref - np.ascontiguousarray(ulb_t)).max())
        worst = max(worst, d)
        pre_results.append({'case': str(p.name) if p is not None else 'synthetic_640x480',
                            'size': sz, 'max_abs_diff': d})
status['preprocess_reference'] = 'PASS' if worst <= 1.0 / 255.0 else f'FAIL (worst={worst})'
log(f'[5] preprocess equivalence vs ultralytics LetterBox: worst max_abs_diff={worst:.8f} ({len(pre_results)} cases)')

# ---------- 6. FP32 val at three sizes ----------
model_results = {}
for sz in SIZES:
    for split in ['val', 'test']:
        t0 = time.time()
        m = YOLO(str(WEIGHTS))
        r = m.val(data=str(local_yaml), imgsz=sz, split=split, device='cpu',
                  batch=8, workers=0, verbose=False, plots=False,
                  conf=0.001, iou=0.7, max_det=300)
        split_key = 'valid' if split == 'val' else split
        per_class = {}
        for i, n in enumerate(names):
            if r.box.maps[i] > 0 or True:
                per_class[n] = {'map50': float(r.box.ap50[i]), 'map': float(r.box.ap[i]),
                                'precision': float(r.box.p[i]), 'recall': float(r.box.r[i]),
                                'gt_boxes': int(splits[split_key]['class_boxes'][i])}
        model_results[f'{sz}_{split}'] = {
            'map50': float(r.box.map50), 'map': float(r.box.map),
            'results_dict': {k: float(v) for k, v in r.results_dict.items() if isinstance(v, (int, float))},
            'per_class': per_class, 'seconds': round(time.time() - t0, 1)}
        log(f'[6] {sz}/{split}: mAP50={r.box.map50:.4f} mAP50-95={r.box.map:.4f} ({model_results[f"{sz}_{split}"]["seconds"]}s)')

status['fp32_baseline'] = 'PASS'
size_loss = {}
for sz in SIZES:
    if sz == 640:
        continue
    size_loss[f'FP32_640_vs_FP32_{sz}'] = {
        'valid_map50_drop': round(model_results['640_val']['map50'] - model_results[f'{sz}_val']['map50'], 4),
        'valid_map_drop': round(model_results['640_val']['map'] - model_results[f'{sz}_val']['map'], 4)}
log('[6] size loss (valid): ' + json.dumps(size_loss))

# ---------- outputs ----------
(RUN / 'weights_manifest.json').write_text(json.dumps(wm, indent=2), encoding='utf-8')
(RUN / 'dataset_manifest.json').write_text(json.dumps(dm, indent=2), encoding='utf-8')
(RUN / 'class_map.json').write_text(json.dumps({str(i): n for i, n in enumerate(names)}, indent=2), encoding='utf-8')
(RUN / 'calibration_stats.json').write_text(
    json.dumps({'images': len(cal_all), 'class_stratified': len(cal_set), 'background': len(cal_bg),
                'cal_box_counts': cal_box_counts, 'seed': SEED}, indent=2), encoding='utf-8')
(RUN / 'preprocess_check.json').write_text(json.dumps(pre_results, indent=2), encoding='utf-8')
(RUN / 'metrics_fp32.json').write_text(json.dumps(model_results, indent=2), encoding='utf-8')
(RUN / 'size_loss.json').write_text(json.dumps(size_loss, indent=2), encoding='utf-8')
ver = {'python': sys.executable, 'torch': torch.__version__, 'ultralytics': ultralytics.__version__,
       'numpy': np.__version__, 'seed': SEED, 'cal_target_per_class': CAL_PER_CLASS_TARGET}
(RUN / 'run_env.json').write_text(json.dumps(ver, indent=2), encoding='utf-8')
(RUN / 'console.log').write_text('\n'.join(log_lines) + '\n', encoding='utf-8')

final = {'result': 'G1_FP32_BASELINE_PASS' if status['fp32_baseline'] == 'PASS'
         and status['preprocess_reference'].startswith('PASS') else 'G1_PARTIAL',
         'status': status, 'size_loss': size_loss, 'sizes': SIZES}
(RUN / 'summary.json').write_text(json.dumps(final, indent=2), encoding='utf-8')
log('# FINAL: ' + json.dumps(final['result']) + ' | ' + json.dumps(status))
