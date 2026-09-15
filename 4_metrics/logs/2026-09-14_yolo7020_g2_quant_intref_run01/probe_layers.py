"""Standalone per-layer fidelity probe (diagnostic, read-only).

Isolates for key nodes, given the FP input of that node:
  - input-quant cosine      : cos(Q(x_fp), x_fp)
  - weight-only cosine      : fake-quant per-channel weights, FP conv+bias, vs post-BN pre-act
  - full-node cosine        : QConv integer path (requant + LUT) vs module output
  - saturation fractions    : |x_q|==127 and |y_q|==127 (calibration range vs this image)
plus pre-BN / post-BN / post-SiLU absmax structure per node.
"""
from pathlib import Path
import os, sys, json
import numpy as np

RUN = Path(__file__).resolve().parent
ROOT = Path('E:/competition')
DATASET = ROOT / '3_host/model_datasets/dataset'
WEIGHTS = ROOT / '3_host/model/best.pt'
G1 = ROOT / '4_metrics/logs/2026-09-14_yolo7020_g1_fp32_baseline_run01'
SIZE = 320
os.environ.update(YOLO_OFFLINE='true', YOLO_AUTOINSTALL='false', PYTHONNOUSERSITE='1',
                  PYTHONDONTWRITEBYTECODE='1', OMP_NUM_THREADS='2', MKL_NUM_THREADS='2')
import torch, cv2
from ultralytics import YOLO
from ultralytics.nn.modules import Conv as UConv, C2f, SPPF, Bottleneck, Concat, Detect
import torch.nn as nn
sys.path.insert(0, str(RUN))
from intref_yolov8 import QConv

ymodel = YOLO(str(WEIGHTS))
model = ymodel.model.eval()
named = dict(model.named_modules())

def letterbox_u8_rgb(img_bgr, sz):
    h, w = img_bgr.shape[:2]
    r = min(sz / h, sz / w)
    nh, nw = round(h * r), round(w * r)
    res = cv2.resize(img_bgr, (nw, nh), interpolation=cv2.INTER_LINEAR)
    canvas = np.full((sz, sz, 3), 114, dtype=np.uint8)
    top, left = (sz - nh) // 2, (sz - nw) // 2
    canvas[top:top + nh, left:left + nw] = res
    return canvas[:, :, ::-1].copy()

caps = {}
def mk_cap(name):
    def h(m, i, o):
        t = o[0] if isinstance(o, (tuple, list)) else o
        caps[name] = t.detach().clone()
    return h
for name, mod in model.named_modules():
    if isinstance(mod, (UConv, Concat, Bottleneck)) or (isinstance(mod, nn.Conv2d) and 'dfl' not in name):
        mod.register_forward_hook(mk_cap(name))
    if isinstance(mod, UConv):
        mod.bn.register_forward_hook(mk_cap(f'{name}|pre'))
        mod.conv.register_forward_hook(mk_cap(f'{name}|conv'))

ent = json.load(open(G1 / 'dataset_manifest.json'))['splits']['valid']['entries'][0]
canvas = letterbox_u8_rgb(cv2.imread(str(DATASET / 'valid/images' / ent['image'])), SIZE)
with torch.no_grad():
    model(torch.from_numpy(canvas.astype(np.float32) / 255.).permute(2, 0, 1)[None])

q = json.load(open(RUN / 'quant.json'))
qm = {n['node']: n for n in q['nodes']}

def cos(a, b):
    a, b = a.ravel().astype(np.float64), b.ravel().astype(np.float64)
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))

print(f'probe image: {ent["image"]}')
print('== absmax structure ==')
print(f'{"node":22s} {"pre-BN":>10s} {"post-BN":>10s} {"post-SiLU":>10s} {"pre/post":>9s} {"conv/bn":>9s}')
for n in ['model.0', 'model.1', 'model.2.cv1', 'model.4.cv1', 'model.5', 'model.7',
          'model.12.cv1', 'model.19', 'model.21.cv2', 'model.22.cv3.2.0']:
    conv = caps[f'{n}|conv'][0].abs().max().item()
    pre = caps[f'{n}|pre'][0].abs().max().item()
    post = caps[n][0].abs().max().item()
    print(f'{n:22s} {conv:10.3f} {pre:10.3f} {post:10.3f} {pre/post:9.2f} {conv/pre:9.2f}')

print('== single-layer fidelity given FP input ==')
print(f'{"node":22s} {"in_cos":>8s} {"w_cos":>8s} {"full":>8s} {"sat_in%":>8s} {"sat_out%":>8s}')

def fold_b(node, tm):
    """Folded float bias = conv bias + BN shift (same math as QConv.__init__)."""
    tc = tm.conv if isinstance(tm, UConv) else tm
    bn = tm.bn if isinstance(tm, UConv) else None
    b = tc.bias.detach().numpy().astype(np.float64) if tc.bias is not None else np.zeros(tc.weight.shape[0])
    if bn is not None:
        g = bn.weight.detach().numpy().astype(np.float64)
        bb = bn.bias.detach().numpy().astype(np.float64)
        mu = bn.running_mean.detach().numpy().astype(np.float64)
        var = bn.running_var.detach().numpy().astype(np.float64)
        sb = g / np.sqrt(var + float(bn.eps))
        b = bb + (b - mu) * sb
    return b

def probe(node, producer, first_layer=False):
    m = qm[node]
    tm = named[node]
    is_u = isinstance(tm, UConv)
    if first_layer:
        x_fp = canvas.astype(np.float64) / 255.0
        x_q = (canvas.astype(np.int16) - 128).astype(np.int8)[None].transpose(0, 3, 1, 2).copy()
    else:
        x_fp = caps[producer][0].numpy().astype(np.float64)
        x_q = np.clip(np.round(x_fp / m['in_scale']), -128, 127).astype(np.int8)[None]
    qcv = QConv(node, tm.conv if is_u else tm, tm.bn if is_u else None, is_u,
                m['in_scale'], m['out_scale'], m['stored_scale'] if is_u else None)
    if first_layer:
        zs = (128 * qcv.w_q.reshape(qcv.w_q.shape[0], -1).sum(axis=1)).astype(np.int64)
        y = qcv.forward(x_q, z_sum_w=zs)
    else:
        y = qcv.forward(x_q)
    full = cos(y[0].astype(np.float64) * m['stored_scale'], caps[node][0].numpy().astype(np.float64))
    in_cos = 1.0 if first_layer else cos(x_q[0].astype(np.float64) * m['in_scale'], x_fp)
    # weight-only: dequantized int8 weights through FP conv with folded bias vs true post-BN
    W_dq = torch.from_numpy(qcv.w_q.astype(np.float64) * qcv.w_scales[:, None, None, None]).float()
    x_conv = torch.from_numpy(x_fp.transpose(2, 0, 1)[None] if first_layer else x_fp[None]).float()
    lin_q = torch.nn.functional.conv2d(x_conv, W_dq,
                                       torch.from_numpy(fold_b(node, tm)).float(),
                                       stride=tuple(m['stride']), padding=tuple(m['pad'])).numpy()[0]
    w_cos = cos(lin_q, caps[f'{node}|pre'][0].numpy().astype(np.float64))
    sat_in = float((np.abs(x_q) >= 127).mean() * 100)
    sat_out = float((np.abs(y) >= 127).mean() * 100)
    print(f'{node:22s} {in_cos:8.4f} {w_cos:8.4f} {full:8.4f} {sat_in:8.2f} {sat_out:8.2f}')

def deep_probe(node, producer):
    """Decompose one node's integer path stage by stage."""
    from intref_yolov8 import rne_shift, sat_i8
    m = qm[node]
    tm = named[node]
    x_fp = caps[producer][0].numpy().astype(np.float64)
    x_q = np.clip(np.round(x_fp / m['in_scale']), -128, 127).astype(np.int8)[None]
    qcv = QConv(node, tm.conv, tm.bn, True, m['in_scale'], m['out_scale'], m['stored_scale'])
    acc = qcv.acc_i32(x_q)
    oc = acc.shape[1]
    pre = np.empty(acc.shape, dtype=np.int8)
    for c in range(oc):
        M_, s_ = qcv.reqs[c]
        n_ = (acc[:, c].astype(np.int64) + qcv.b_q[c]) * M_
        pre[:, c] = sat_i8(rne_shift(n_, s_))
    pre_fp = caps[f'{node}|pre'][0].numpy().astype(np.float64)
    sat_pre = float((np.abs(pre) >= 127).mean() * 100)
    pre_cos = cos(pre[0].astype(np.float64) * m['out_scale'], pre_fp)
    # ideal fake-quant emulation: FP folded conv on the SAME quantized input,
    # rounded to the same pre-act grid
    W_dq = torch.from_numpy(qcv.w_q.astype(np.float64) * qcv.w_scales[:, None, None, None]).float()
    lin = torch.nn.functional.conv2d(torch.from_numpy(x_fp[None]).float(), W_dq,
                                     torch.from_numpy(fold_b(node, tm)).float(),
                                     stride=tuple(m['stride']), padding=tuple(m['pad'])).numpy()[0]
    ref_pre = np.clip(np.round(lin / m['out_scale']), -128, 127).astype(np.int8)
    diff_frac = float((ref_pre != pre[0]).mean() * 100)
    max_diff = int(np.abs(ref_pre.astype(int) - pre[0].astype(int)).max())
    # post stage
    y = qcv.lut[(pre[0].astype(np.int16) + 128).astype(np.uint8)]
    ref_post = qcv.lut[(ref_pre.astype(np.int16) + 128).astype(np.uint8)]
    post_cos = cos(y.astype(np.float64) * m['stored_scale'], caps[node][0].numpy().astype(np.float64))
    refpost_cos = cos(ref_post.astype(np.float64) * m['stored_scale'], caps[node][0].numpy().astype(np.float64))
    print(f'{node}: sat_pre%={sat_pre:.2f} pre_cos={pre_cos:.4f} | vs ideal round: diff%={diff_frac:.2f} maxd={max_diff} '
          f'| post_cos={post_cos:.4f} refpost_cos={refpost_cos:.4f}')

deep_probe('model.1', 'model.0')
deep_probe('model.2.cv1', 'model.1')
deep_probe('model.7', 'model.6.cv2')

probe('model.0', None, first_layer=True)
probe('model.1', 'model.0')
probe('model.2.cv1', 'model.1')
probe('model.7', 'model.6.cv2')
probe('model.19', 'model.18.cv2')
probe('model.22.cv2.0.0', 'model.15.cv2')
probe('model.22.cv3.2.0', 'model.21.cv2')
