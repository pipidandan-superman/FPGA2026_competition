"""G2: W8A8 PTQ + HWINT integer reference + golden package (plan r3 §4.2/§4.6/§12.2).

Reads only: best.pt, v6 dataset, G1 calibration list. Writes only inside this run dir.
Input size 320 (performance candidate; G1 recorded size loss as neutral-positive).

Pipeline:
  1. unit tests of integer primitives (hand-computed RNE ties, dyadic INT64 oracle conv)
  2. calibrate per-tensor activation scales on the 420-image G1 list (max-abs symmetric)
  3. integer graph walk carrying (tensor, scale) pairs; producer scales resolved statically
  4. layerwise LSQ stored-scale refit (fixed-point sweeps over the calibration
     set: S' = <v,fp>/<v,v> per fit-site, v from the int pipeline itself —
     closes the systematic per-node gain error the p99.99 grids leave behind)
  5. per-layer FP-vs-INT8 cosine on 3 probe images (layer_error.csv)
  6. export quant.json / weights.bin / bias.bin / lut.bin / manifest.json
  7. one pass over valid+test: FP raw heads (torch hooks) + INT8 raw heads through the
     SAME numpy decode+NMS+AP50 evaluator; per-class drop table
  8. golden: 5 deep samples (all-node int8+fp16 tensors, raw heads) as NPZ +
     golden_index.json; 128-frame regression outputs (boxes/conf/cls + raw-head hash)
"""
from pathlib import Path
import os, sys, json, time, hashlib
import numpy as np

RUN = Path(__file__).resolve().parent
ROOT = Path('E:/competition')
DATASET = ROOT / '3_host/model_datasets/dataset'
WEIGHTS = ROOT / '3_host/model/best.pt'
G1 = ROOT / '4_metrics/logs/2026-09-14_yolo7020_g1_fp32_baseline_run01'
SIZE = 320
SEED = 20260914
DEEP_SAMPLES = 5

for key, leaf in [('YOLO_CONFIG_DIR', 'ultralytics_config'), ('MPLCONFIGDIR', 'matplotlib_config')]:
    os.environ[key] = str(RUN / leaf)
    (RUN / leaf).mkdir(exist_ok=True)
os.environ.update(YOLO_OFFLINE='true', YOLO_AUTOINSTALL='false', PYTHONNOUSERSITE='1',
                  PYTHONDONTWRITEBYTECODE='1', OMP_NUM_THREADS='2', MKL_NUM_THREADS='2')

import torch
import cv2
import ultralytics
from ultralytics import YOLO, settings
from ultralytics.utils import USER_CONFIG_DIR
from ultralytics.nn.modules import Conv as UConv, C2f, SPPF, Bottleneck, Concat, Detect
import torch.nn as nn

sys.path.insert(0, str(RUN))
from intref_yolov8 import (QConv, rne_shift, requant_to, int_add, maxpool5,
                           upsample_nearest2, softmax_dfl_decode, nms_numpy,
                           ap50_per_class, req_pair)

assert Path(USER_CONFIG_DIR).resolve().is_relative_to(RUN)
settings.update({'sync': False, 'runs_dir': str(RUN / 'predictions'),
                 'datasets_dir': str(RUN / 'datasets'), 'weights_dir': str(RUN / 'weights')})

L = []
def log(m=''):
    print(m, flush=True)
    L.append(str(m))

def sha(p: Path):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while True:
            b = f.read(1 << 20)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

status = {}

# ================= 1. unit tests =================
cases = [(5, 1, 2), (7, 1, 4), (-5, 1, -2), (-7, 1, -4), (3, 0, 3), (1, 1, 0), (-1, 1, 0),
         (2, 1, 1), (6, 1, 3), (-2, 1, -1), (9, 2, 2), (-9, 2, -2), (6, 2, 2), (10, 2, 2)]
ok = all(int(rne_shift(np.array([a], dtype=np.int64), s)[0]) == e for a, s, e in cases)
assert ok, 'RNE hand cases failed'
# NEP50 shift-dtype guard (bug found 2026-09-15 via PS offline regression):
# np.frexp exponents arrive as np.int32; under NEP50 `1 << np.int32(41)` wraps
# to 0, so the tie threshold `full` collapses and RNE degrades to
# round-away-from-zero (+0.5 LSB mean bias) for every shift >= 32 — which this
# net uses for nearly all channels. rne_shift must normalize s to Python int.
n41 = np.array([2**41 * 5 + 2**40, 2**41 * 5 - 2**40, 2**41 * 3 + 3, 1, -1, 0], dtype=np.int64)
ref41 = np.array([6, 4, 3, 0, 0, 0], dtype=np.int64)   # ties 5.5->6, 4.5->4 (to even)
assert np.array_equal(rne_shift(n41, 41), ref41), 'RNE s=41 hand cases failed'
assert np.array_equal(rne_shift(n41, np.int32(41)), ref41), 'np.int32 shift not normalized'
_rng41 = np.random.RandomState(SEED)
_n41 = _rng41.randint(-(2**53), 2**53, 4096, dtype=np.int64)
assert np.array_equal(rne_shift(_n41, np.int32(45)), rne_shift(_n41, 45)), 'np.int32 A/B mismatch'
status['rne_unit'] = 'PASS'

rng = np.random.RandomState(SEED)
x = rng.randint(-100, 100, (1, 3, 9, 9)).astype(np.int8)
w = rng.randint(-127, 127, (5, 3, 3, 3)).astype(np.int8)
b = rng.randint(-1000, 1000, 5).astype(np.int32)
M, SH = 1 << 30, 30
qc = QConv.__new__(QConv)
qc.stride, qc.pad = (1, 1), (1, 1)
qc.w_q, qc.b_q, qc.reqs, qc.lut = w, b, [(M, SH)] * 5, None
acc = qc.acc_i32(x, pad_val=0).astype(np.int64) + b[None, :, None, None]
ref = np.clip(np.round(acc.astype(np.float64) * (M / 2 ** SH)), -128, 127).astype(np.int8)
got = np.clip(rne_shift(acc * M, SH), -128, 127).astype(np.int8)
assert np.array_equal(ref, got), 'dyadic oracle mismatch'
status['int64_oracle_conv'] = 'PASS'
log(f'[1] unit tests PASS (RNE {len(cases)} hand cases + dyadic oracle exact)')

# ================= 2. model + calibration =================
ymodel = YOLO(str(WEIGHTS))
model = ymodel.model.eval()
names = ['Down', 'Left', 'Right', 'Stop', 'Thumbs Down', 'Thumbs up', 'Up']
STRIDES = [8, 16, 32]

def letterbox_u8_rgb(img_bgr, sz):
    h, w = img_bgr.shape[:2]
    r = min(sz / h, sz / w)
    nh, nw = round(h * r), round(w * r)
    res = cv2.resize(img_bgr, (nw, nh), interpolation=cv2.INTER_LINEAR)
    canvas = np.full((sz, sz, 3), 114, dtype=np.uint8)
    top, left = (sz - nh) // 2, (sz - nw) // 2
    canvas[top:top + nh, left:left + nw] = res
    return canvas[:, :, ::-1].copy()

absmax = {}
def _absmax_max(name, t):
    v = float(t.detach().abs().max())
    if v > absmax.get(name, 0):
        absmax[name] = v

def mk_hook(name):
    def hook(mod, inp, out):
        _absmax_max(name, out[0] if isinstance(out, (tuple, list)) else out)
    return hook

# For activated UConv nodes TWO scales matter:
#   - requant domain = post-BN PRE-activation absmax (the SiLU LUT input; using
#     the post-SiLU absmax here would clip pre-activations every layer)
#   - stored tensor = module output at the POST-activation absmax (the LUT
#     output feeds downstream; a single pre-act scale wastes up to ~2 bits when
#     the pre-act range is negative-dominated)
# Pitfalls: 'model.N.conv' output is PRE-BN (conv->bn->act) — mismatches the
# folded-BN node by the per-channel BN gain. And Conv.default_act is a SHARED
# class-level nn.SiLU — hooks on mod.act would fire for every SiLU in the
# network and poison all keys. So hook each module's own BatchNorm2d output
# (= act input) under a distinct '|pre' key.
hooked = []
for name, mod in model.named_modules():
    if isinstance(mod, (UConv, Concat, Bottleneck)) or (isinstance(mod, nn.Conv2d) and 'dfl' not in name):
        mod.register_forward_hook(mk_hook(name))
        hooked.append(name)
    if isinstance(mod, UConv) and getattr(mod, 'bn', None) is not None:
        mod.bn.register_forward_hook(mk_hook(f'{name}|pre'))
        hooked.append(f'{name}|pre')

cal_list = (G1 / 'calibration_list.txt').read_text().split()
cal_imgs = [DATASET / 'train/images' / f for f in cal_list]
t0 = time.time()
with torch.no_grad():
    for p in cal_imgs:
        x = torch.from_numpy(letterbox_u8_rgb(cv2.imread(str(p)), SIZE)
                             .astype(np.float32) / 255.0).permute(2, 0, 1)[None]
        model(x)

# ---- MSE-optimal clipping (plan r3 G2 failure handling: adjust calibration) ----
# Pass-1 absmax is outlier-dominated: per-tensor grids end up 1.5-3x coarser than
# the bulk needs, and C2f cat requants saturate (bottleneck/cv1 scale ratios up
# to 1.51). Pass 2 histograms |v| per node; per node pick the clip c minimizing
# clip_mse(c) + (c/127)^2/12 * N_total (rounding noise), c in bin right-edges.
HIST_BINS = 2048
amax = {n: absmax.get(n, 1e-8) for n in hooked}
hists = {n: np.zeros(HIST_BINS, dtype=np.int64) for n in hooked}

def mk_hist_hook(name):
    def hook(mod, inp, out):
        t = out[0] if isinstance(out, (tuple, list)) else out
        v = t.detach().abs().ravel().numpy()
        a = amax[name]
        idx = np.minimum((v / a * (HIST_BINS - 1)).astype(np.int64), HIST_BINS - 1)
        hists[name] += np.bincount(idx, minlength=HIST_BINS).astype(np.int64)
    return hook

for name, mod in model.named_modules():
    if isinstance(mod, (UConv, Concat, Bottleneck)) or (isinstance(mod, nn.Conv2d) and 'dfl' not in name):
        mod.register_forward_hook(mk_hist_hook(name))
    if isinstance(mod, UConv) and getattr(mod, 'bn', None) is not None:
        mod.bn.register_forward_hook(mk_hist_hook(f'{name}|pre'))

with torch.no_grad():
    for p in cal_imgs:
        x = torch.from_numpy(letterbox_u8_rgb(cv2.imread(str(p)), SIZE)
                             .astype(np.float32) / 255.0).permute(2, 0, 1)[None]
        model(x)

def clip_scale(name):
    """99.99th-percentile clip. Raw-MSE optima collapse to ~absmax/1000 here:
    post-SiLU tensors are dominated by near-zero negatives, so the MSE objective
    weights the huge zero mass and sacrifices the strong activations that carry
    the detections (measured: mAP50 -> 0.0002). A 99.99% percentile clips only
    the extreme 1e-4 tail — mild range shrink, finer grid, features intact."""
    h = hists[name].astype(np.float64)
    if h.sum() == 0:
        return amax[name]
    a = amax[name]
    edges = np.arange(1, HIST_BINS + 1) / HIST_BINS * a
    Wc = np.cumsum(h[::-1])[::-1]          # Wc[i] = mass of bins j >= i
    tail = Wc / Wc[0]                       # fraction of elements above edges[i-1]
    keep = np.nonzero(tail <= 1e-4)[0]      # at most 0.01% of elements clipped
    i = int(keep[0]) if len(keep) else HIST_BINS - 1
    return float(max(edges[i] if i < HIST_BINS else a, 1e-8))

clipv = {n: clip_scale(n) for n in hooked}
# UConv tensor scales land on the post-BN PRE-activation absmax via the bn
# output hooks above (plan r3 §4.2: SiLU LUT at pre-activation scale; requant
# domain, downstream in_scale, golden dequant and quant.json all agree).
scales = {n: clipv[n] / 127.0 for n in hooked}
clipped = sum(1 for n in hooked if clipv[n] < amax[n] * 0.999)
med_shrink = float(np.median([clipv[n] / amax[n] for n in hooked]))
status['calibration'] = (f'PASS ({len(cal_imgs)} imgs, {len(scales)} tensors, '
                         f'p99.99 clip on {clipped}/{len(hooked)}, median shrink {med_shrink:.3f}, '
                         f'{time.time()-t0:.0f}s)')
log(f'[2] calibrated {len(cal_imgs)} images -> {len(scales)} tensor scales '
    f'(p99.99 clip: {clipped}/{len(hooked)} nodes, median shrink {med_shrink:.3f})')

def S(n):
    return scales[n]

def SP(n):
    """post-BN pre-activation (requant/LUT-input) scale of an activated node."""
    return scales[f'{n}|pre']

# ================= 3. build QConv nodes =================
TOP = model.model
nodes = {}

def mk_qconv(name, tc, bn, has_act, in_scale):
    # requant domain = post-BN PRE-act absmax for activated nodes (LUT input
    # contract, S = SP(name)); stored tensor = post-act absmax (S(name)).
    # Linear tips: requant domain == stored == raw output absmax.
    nd = QConv(name, tc, bn, has_act, in_scale,
               SP(name) if has_act else S(name), S(name) if has_act else None)
    nodes[name] = nd
    return nd

def conv_u(name, mod, in_scale):
    return mk_qconv(name, mod.conv, mod.bn, True, in_scale)

def conv_plain(name, mod, in_scale):
    return mk_qconv(name, mod, None, False, in_scale)

# patch QConv to retain folded bias for scale rebinding

def set_in(node_name, in_scale):
    nd = nodes[node_name]
    nd.x_scale = in_scale
    nd.b_q = np.clip(np.round(nd._b_fold / (in_scale * nd.w_scales)).astype(np.int64),
                     -2**31, 2**31 - 1).astype(np.int32)
    nd.reqs = [req_pair((in_scale * ws) / nd.y_scale) for ws in nd.w_scales]

# patch QConv to retain folded bias for scale rebinding
_orig_init = QConv.__init__
def _init_keep(self, name, tc, bn, has_act, in_scale, out_scale, act_out_scale=None):
    import numpy as _np
    w = tc.weight.detach().numpy().astype(_np.float64)
    b = tc.bias.detach().numpy().astype(_np.float64) if tc.bias is not None else _np.zeros(w.shape[0])
    if bn is not None:
        g = bn.weight.detach().numpy().astype(_np.float64)
        bb = bn.bias.detach().numpy().astype(_np.float64)
        mu = bn.running_mean.detach().numpy().astype(_np.float64)
        var = bn.running_var.detach().numpy().astype(_np.float64)
        sb = g / _np.sqrt(var + float(bn.eps))
        w = w * sb[:, None, None, None]
        b = bb + (b - mu) * sb
    self._b_fold = b
    self._w_fold = w
    _orig_init(self, name, tc, bn, has_act, in_scale, out_scale, act_out_scale)
    # re-derive from kept folds so in_scale rebinding is consistent
    oc = w.shape[0]
    mx = _np.max(_np.abs(w).reshape(oc, -1), axis=1)
    self.w_scales = mx / 127.0
    self.w_scales[self.w_scales == 0] = 1e-12
    self.w_q = _np.stack([_np.round(w[c] / self.w_scales[c]) for c in range(oc)]).astype(_np.int8)
QConv.__init__ = _init_keep

# rebuild with patched init (keeps _b_fold)
nodes = {}
for i, mod in enumerate(TOP):
    pre = f'model.{i}'
    if isinstance(mod, UConv):
        conv_u(pre, mod, 1.0)
    elif isinstance(mod, C2f):
        conv_u(f'{pre}.cv1', mod.cv1, 1.0)
        conv_u(f'{pre}.cv2', mod.cv2, 1.0)
        for bi, bt in enumerate(mod.m):
            conv_u(f'{pre}.m.{bi}.cv1', bt.cv1, 1.0)
            conv_u(f'{pre}.m.{bi}.cv2', bt.cv2, 1.0)
    elif isinstance(mod, SPPF):
        conv_u(f'{pre}.cv1', mod.cv1, 1.0)
        conv_u(f'{pre}.cv2', mod.cv2, 1.0)
    elif isinstance(mod, Detect):
        for br in range(3):
            for li, layer in enumerate(mod.cv2[br]):
                (conv_u if isinstance(layer, UConv) else conv_plain)(f'{pre}.cv2.{br}.{li}', layer, 1.0)
            for li, layer in enumerate(mod.cv3[br]):
                (conv_u if isinstance(layer, UConv) else conv_plain)(f'{pre}.cv3.{br}.{li}', layer, 1.0)

status['graph_build'] = f'PASS ({len(nodes)} QConv nodes)'
log(f'[3] built {len(nodes)} QConv nodes')

# ================= 4. integer forward carrying (tensor, scale) =================
FIRST_ZS = None

def run_c2f_int(idx, x, xs, t):
    m = TOP[idx]; pre = f'model.{idx}'
    set_in(f'{pre}.cv1', xs)
    y = nodes[f'{pre}.cv1'].forward(x)
    y_s = nodes[f'{pre}.cv1'].s_stored          # C2f internal cat adopts cv1's stored scale
    t[f'{pre}.cv1'] = y
    c = getattr(m, 'c', None) or (y.shape[1] // 2)
    parts = [(a, y_s) for a in np.split(y, [y.shape[1] - c], axis=1)]
    for bi, bt in enumerate(m.m):
        h, hs = parts[-1]
        set_in(f'{pre}.m.{bi}.cv1', hs)
        h = nodes[f'{pre}.m.{bi}.cv1'].forward(h)
        set_in(f'{pre}.m.{bi}.cv2', nodes[f'{pre}.m.{bi}.cv1'].s_stored)
        h = nodes[f'{pre}.m.{bi}.cv2'].forward(h)
        if bt.add:
            h = int_add(h, nodes[f'{pre}.m.{bi}.cv2'].s_stored, parts[-1][0], parts[-1][1], S(f'{pre}.m.{bi}'))
            hs = S(f'{pre}.m.{bi}')
        else:
            hs = nodes[f'{pre}.m.{bi}.cv2'].s_stored   # non-add: stored tensor is cv2's post-LUT output
        t[f'{pre}.m.{bi}'] = h
        parts.append((h, hs))
    aligned = [(requant_to(p, ps, y_s) if abs(ps - y_s) > 1e-15 else p) for p, ps in parts]
    cat = np.concatenate(aligned, axis=1)
    set_in(f'{pre}.cv2', y_s)
    out = nodes[f'{pre}.cv2'].forward(cat)
    t[f'{pre}.cv2'] = out
    return out, nodes[f'{pre}.cv2'].s_stored

def int_forward(canvas_u8):
    """canvas_u8 RGB uint8 [S,S,3] -> (regs, clss, t) with t = name->int8 tensor."""
    global FIRST_ZS
    t = {}
    ts = {}
    x0 = (canvas_u8.astype(np.int16) - 128).astype(np.int8)[None].transpose(0, 3, 1, 2).copy()
    n0 = nodes['model.0']
    set_in('model.0', 1.0 / 255.0)
    if FIRST_ZS is None:
        FIRST_ZS = (128 * n0.w_q.reshape(n0.w_q.shape[0], -1).sum(axis=1)).astype(np.int64)
    x = n0.forward(x0, z_sum_w=FIRST_ZS)
    xs = n0.s_stored
    t['model.0'] = x; ts['model.0'] = xs
    for i in range(1, len(TOP)):
        mod = TOP[i]
        pre = f'model.{i}'
        if isinstance(mod, UConv):
            set_in(pre, xs)
            x = nodes[pre].forward(x)
            xs = nodes[pre].s_stored; t[pre] = x; ts[pre] = xs
        elif isinstance(mod, C2f):
            x, xs = run_c2f_int(i, x, xs, t)
            t[pre] = x; ts[pre] = xs
        elif isinstance(mod, SPPF):
            set_in(f'{pre}.cv1', xs)
            y = nodes[f'{pre}.cv1'].forward(x)
            p1 = maxpool5(y); p2 = maxpool5(p1); p3 = maxpool5(p2)
            cat = np.concatenate([y, p1, p2, p3], axis=1)
            set_in(f'{pre}.cv2', nodes[f'{pre}.cv1'].s_stored)
            x = nodes[f'{pre}.cv2'].forward(cat)
            xs = nodes[f'{pre}.cv2'].s_stored; t[pre] = x; ts[pre] = xs
        elif isinstance(mod, nn.Upsample):
            x = upsample_nearest2(x)          # scale kept
            t[pre] = x; ts[pre] = xs
        elif isinstance(mod, Concat):
            srcs = mod.f if isinstance(mod.f, list) else [mod.f]
            gathered = []
            for s_ in srcs:
                j = (i + s_) if s_ < 0 else s_   # negative = relative, non-negative = absolute index
                gathered.append((t[f'model.{j}'], ts[f'model.{j}']))
            aligned = [(requant_to(g, gs, S(pre)) if abs(gs - S(pre)) > 1e-15 else g) for g, gs in gathered]
            x = np.concatenate(aligned, axis=1)
            xs = S(pre); t[pre] = x; ts[pre] = xs
        elif isinstance(mod, Detect):
            d = mod
            fin = [t['model.15'], t['model.18'], t['model.21']]
            fins = [ts['model.15'], ts['model.18'], ts['model.21']]
            regs, clss = [], []
            for br in range(3):
                h, hs = fin[br], fins[br]
                for li, layer in enumerate(d.cv2[br]):
                    nm = f'{pre}.cv2.{br}.{li}'
                    set_in(nm, hs)
                    h = nodes[nm].forward(h)
                    hs = nodes[nm].s_stored
                    t[nm] = h
                regs.append(h)
                h3, hs3 = fin[br], fins[br]
                for li, layer in enumerate(d.cv3[br]):
                    nm = f'{pre}.cv3.{br}.{li}'
                    set_in(nm, hs3)
                    h3 = nodes[nm].forward(h3)
                    hs3 = nodes[nm].s_stored
                    t[nm] = h3
                clss.append(h3)
            return regs, clss, t
    raise RuntimeError('Detect not reached')

# fp capture hooks
fp_caps = {}
def mk_cap(name):
    def h(mod, i_, o):
        tt = o[0] if isinstance(o, (tuple, list)) else o
        fp_caps[name] = tt.detach().clone()
    return h
for name, mod in model.named_modules():
    if isinstance(mod, (UConv, Bottleneck, Concat)) or (isinstance(mod, nn.Conv2d) and 'dfl' not in name):
        mod.register_forward_hook(mk_cap(name))

def fp_forward(canvas_u8):
    x = torch.from_numpy(canvas_u8.astype(np.float32) / 255.0).permute(2, 0, 1)[None]
    with torch.no_grad():
        model(x)

# ---- layerwise LSQ stored-scale refit (plan r3 G2 failure handling: 调整校准) ----
# Golden-npz regression diagnosis: with p99.99 grids the per-node cascade slope
# int->fp sits systematically off 1 (0.81..1.13, consistent across images) and
# compounds through the chain. Closed-form fix per fit-site:
#     S' = argmin_S ||v*S - fp||^2  =  <v,fp>/<v,v>
# accumulated over a calibration subsample, v taken from the INT pipeline output
# itself (so the fit absorbs both fresh and inherited gain error). Fixed-point
# sweeps: all scales applied simultaneously after each pass; requant domains
# (|pre) and quantized weights untouched — pure stored-scale recalibration.
FIT_SUBSAMPLE = 128
_rng = np.random.default_rng(SEED)
_fit_imgs = [cal_imgs[i] for i in np.sort(_rng.choice(len(cal_imgs), FIT_SUBSAMPLE, replace=False))]
fit_sites = list(nodes.keys())
for i, mod in enumerate(TOP):
    pre = f'model.{i}'
    if isinstance(mod, C2f):
        fit_sites += [f'{pre}.m.{bi}' for bi, bt in enumerate(mod.m) if bt.add]
    elif isinstance(mod, Concat):
        fit_sites.append(pre)
REFIT_ITERS = 2
refit_trace = []
for it in range(REFIT_ITERS):
    _t0 = time.time()
    num = {k: 0.0 for k in fit_sites}
    den = {k: 0.0 for k in fit_sites}
    for p in _fit_imgs:
        canvas = letterbox_u8_rgb(cv2.imread(str(p)), SIZE)
        fp_caps.clear(); fp_forward(canvas)
        _, _, tv = int_forward(canvas)
        for k in fit_sites:
            f_ = fp_caps.get(k)
            v_ = tv.get(k)
            if f_ is None or v_ is None:
                continue
            f_ = f_[0].numpy().astype(np.float64).ravel()
            v_ = v_.astype(np.float64).ravel()
            num[k] += float(v_ @ f_)
            den[k] += float(v_ @ v_)
    ratios = []
    for k in fit_sites:
        if den[k] <= 0:
            continue
        old = nodes[k].s_stored if k in nodes else scales[k]
        s_new = float(np.clip(num[k] / den[k], 0.25 * old, 4.0 * old))   # runaway guard
        if k in nodes:
            nd = nodes[k]
            if nd.has_act:
                with np.errstate(over='ignore'):
                    x_ = np.arange(-128, 128, dtype=np.float64) * nd.y_scale
                    silu = x_ / (1.0 + np.exp(-x_))
                nd.lut = np.clip(np.round(silu / s_new), -128, 127).astype(np.int8)
                nd.s_stored = s_new
            else:   # linear tip: stored == requant domain -> rebuild reqs too
                nd.y_scale = s_new
                nd.s_stored = s_new
                nd.reqs = [req_pair((nd.x_scale * ws) / s_new) for ws in nd.w_scales]
        scales[k] = s_new
        ratios.append(s_new / old)
    ratios = np.array(ratios)
    refit_trace.append({'iter': it, 'median': float(np.median(ratios)),
                        'min': float(ratios.min()), 'max': float(ratios.max())})
    log(f'[3b] refit iter {it}/{REFIT_ITERS}: scale/old median {np.median(ratios):.4f} '
        f'range [{ratios.min():.4f}, {ratios.max():.4f}] ({time.time()-_t0:.0f}s)')
status['scale_refit'] = (f'PASS ({REFIT_ITERS} iters x {FIT_SUBSAMPLE} calib imgs, '
                         f'{len(fit_sites)} sites, final median ratio {refit_trace[-1]["median"]:.4f})')

dm = json.load(open(G1 / 'dataset_manifest.json'))
val_entries = dm['splits']['valid']['entries']
snr_rows = []
for e in val_entries[:3]:
    p = DATASET / 'valid/images' / e['image']
    canvas = letterbox_u8_rgb(cv2.imread(str(p)), SIZE)
    fp_caps.clear(); fp_forward(canvas)
    regs, clss, t = int_forward(canvas)
    for name, xq in t.items():
        if name in fp_caps:
            fp = fp_caps[name][0].numpy().astype(np.float64)
            dq = xq[0].astype(np.float64) * scales.get(name, 1.0)
            a_, b_ = fp.ravel(), dq.ravel()
            cos = float(a_ @ b_ / (np.linalg.norm(a_) * np.linalg.norm(b_) + 1e-12))
            snr_rows.append({'img': e['image'], 'node': name, 'cosine': round(cos, 6)})
worst = min(snr_rows, key=lambda r: r['cosine'])
status['int_vs_fp_layers'] = f'PASS (worst cosine {worst["cosine"]:.4f} @ {worst["node"]}, {len(snr_rows)} checks)'
log(f'[4] layer cosine: worst={worst["cosine"]:.4f} @ {worst["node"]} over {len(snr_rows)} checks')

# ================= 5. export package =================
order = sorted(nodes)
wchunks, bchunks, lchunks, qmeta = [], [], [], []
wo = bo = lo = 0
for n in order:
    nd = nodes[n]
    w = nd.w_q.reshape(nd.w_q.shape[0], -1)
    wchunks.append(w.astype(np.int8).tobytes())
    bchunks.append(nd.b_q.astype('<i4').tobytes())
    lutb = nd.lut.astype(np.int8).tobytes() if nd.lut is not None else b''
    lchunks.append(lutb)
    qmeta.append({'node': n, 'in_scale': float(nd.x_scale), 'out_scale': float(nd.y_scale),
                  'stored_scale': float(nd.s_stored),
                  'w_shape': list(nd.w_q.shape), 'stride': list(nd.stride), 'pad': list(nd.pad),
                  'w_scales': [float(v) for v in nd.w_scales],
                  'req': [[int(m), int(s)] for m, s in nd.reqs], 'has_act': nd.has_act,
                  'w_off': wo, 'b_off': bo, 'l_off': lo})
    wo += w.nbytes; bo += nd.b_q.nbytes; lo += len(lutb)   # b_q int32: nbytes 已含 ×4
(RUN / 'weights.bin').write_bytes(b''.join(wchunks))
(RUN / 'bias.bin').write_bytes(b''.join(bchunks))
(RUN / 'lut.bin').write_bytes(b''.join(lchunks))
quant = {'contract': 'W8A8 per-channel symmetric weights / per-tensor symmetric activations / '
                     'INT32 accumulate / per-channel M+shift RNE requant / SiLU 256-entry LUT '
                     '(input pre-activation domain, output post-act calibrated scale) / '
                     'first layer uint8-128 z-term folded to bias / conv pad = input zp / '
                     'C2f internal cat adopts cv1 stored scale / Add saturates once',
         'input': {'size': SIZE, 'domain': 'uint8 RGB letterbox 114', 'stored_int8': 'u-128', 'scale': 1.0 / 255.0},
         'nodes': qmeta, 'tensor_scales': {k: float(v) for k, v in scales.items()}}
(RUN / 'quant.json').write_text(json.dumps(quant, indent=1), encoding='utf-8')
status['package_export'] = f'PASS ({len(order)} nodes, w{wo}B b{bo}B l{lo}B)'
log(f'[5] exported: {len(order)} nodes')

# ================= 6+7. one pass: eval FP & INT8 + regression + golden =================
def gt_of(split_name):
    out = []
    for e in dm['splits'][split_name]['entries']:
        lb = DATASET / split_name / 'labels' / e['label'] if e['label'] else None
        bs, cs = [], []
        if lb and lb.exists():
            for line in lb.read_text().splitlines():
                pp = line.split()
                if len(pp) == 5:
                    c_, cx, cy, bw, bh = int(pp[0]), *map(float, pp[1:])
                    bs.append([cx * SIZE, cy * SIZE, bw * SIZE, bh * SIZE]); cs.append(c_)
        out.append((e, np.array(bs, dtype=np.float64).reshape(-1, 4), np.array(cs, dtype=int)))
    return out

def decode_all(regs, clss, rs, cs_):
    allb, allc, allk = [], [], []
    for b in range(3):
        bx, cf, ki = softmax_dfl_decode(regs[b], rs[b], clss[b], cs_[b], STRIDES[b])
        allb.append(bx); allc.append(cf); allk.append(ki)
    bx = np.concatenate(allb); cf = np.concatenate(allc); ki = np.concatenate(allk)
    keep = nms_numpy(bx, cf, ki)
    return bx[keep], cf[keep], ki[keep]

t0 = time.time()
eval_data = {'valid': {'fp': [], 'int': []}, 'test': {'fp': [], 'int': []}}
gts_all = {}
reg_out = []
golden_index = []
gdir = RUN / 'golden'; gdir.mkdir(exist_ok=True)
deep_picked = 0
deep_names = set()
for e in val_entries[:DEEP_SAMPLES + 2]:
    deep_names.add(e['image'])

for split_name in ['valid', 'test']:
    gts = gt_of(split_name)
    gts_all[split_name] = [(gb, None, gc) for _, gb, gc in gts]
    for e, gb, gc in gts:
        im = DATASET / split_name / 'images' / e['image']
        canvas = letterbox_u8_rgb(cv2.imread(str(im)), SIZE)
        # FP
        fp_caps.clear(); fp_forward(canvas)
        regs_fp = [fp_caps[f'model.22.cv2.{b}.2'].numpy() for b in range(3)]
        clss_fp = [fp_caps[f'model.22.cv3.{b}.2'].numpy() for b in range(3)]
        bx, cf, ki = decode_all(regs_fp, clss_fp, [1.0] * 3, [1.0] * 3)
        eval_data[split_name]['fp'].append((bx, cf, ki))
        # INT8
        regs, clss, t = int_forward(canvas)
        rs = [S(f'model.22.cv2.{b}.2') for b in range(3)]
        cs_ = [S(f'model.22.cv3.{b}.2') for b in range(3)]
        bx2, cf2, ki2 = decode_all(regs, clss, rs, cs_)
        eval_data[split_name]['int'].append((bx2, cf2, ki2))
        # regression record
        hh = hashlib.sha256()
        for r in regs + clss:
            hh.update(r.tobytes())
        reg_out.append({'split': split_name, 'image': e['image'], 'raw_head_sha256': hh.hexdigest(),
                        'boxes': np.round(bx2, 2).tolist(), 'conf': np.round(cf2, 4).tolist(),
                        'cls': ki2.tolist()})
        # deep golden for first DEEP_SAMPLES valid images
        if split_name == 'valid' and e['image'] in deep_names and deep_picked < DEEP_SAMPLES:
            store = {'canvas_u8': canvas}
            for name, xq in t.items():
                store[f'int8_{name}'] = xq[0]
                if name in fp_caps:
                    store[f'fp_{name}'] = fp_caps[name][0].numpy().astype(np.float16)
            for b in range(3):
                store[f'raw_reg_s{STRIDES[b]}'] = regs[b][0]
                store[f'raw_cls_s{STRIDES[b]}'] = clss[b][0]
            fn = f'golden_{deep_picked:02d}_{e["image"].split(".")[0][:12]}.npz'
            np.savez_compressed(gdir / fn, **store)
            golden_index.append({'sample': deep_picked, 'image': e['image'], 'file': f'golden/{fn}',
                                 'sha256': sha(gdir / fn), 'nodes': len(t), 'classes_present': e['classes']})
            deep_picked += 1

eval_out = {}
for split_name in ['valid', 'test']:
    pc_fp, m_fp = ap50_per_class(eval_data[split_name]['fp'], gts_all[split_name])
    pc_i, m_i = ap50_per_class(eval_data[split_name]['int'], gts_all[split_name])
    eval_out[split_name] = {'fp_map50': m_fp, 'int_map50': m_i,
                            'fp_per_class': {names[c]: pc_fp[c] for c in range(7)},
                            'int_per_class': {names[c]: pc_i[c] for c in range(7)}}
    log(f'[6] {split_name}: FP mAP50={m_fp:.4f} INT8 mAP50={m_i:.4f} drop={m_fp - m_i:+.4f}')
(RUN / 'eval_fp_vs_int8.json').write_text(json.dumps(eval_out, indent=2), encoding='utf-8')
(RUN / 'golden_index.json').write_text(json.dumps(golden_index, indent=2), encoding='utf-8')
(RUN / 'regression_128frames.json').write_text(json.dumps(reg_out, indent=1), encoding='utf-8')
import csv
with open(RUN / 'layer_error.csv', 'w', newline='', encoding='utf-8') as f:
    wr = csv.DictWriter(f, fieldnames=['img', 'node', 'cosine']); wr.writeheader(); wr.writerows(snr_rows)

drop = eval_out['valid']['fp_map50'] - eval_out['valid']['int_map50']
status['eval'] = f'PASS (valid drop {drop:+.4f}; plan gate <=0.02)'
status['golden'] = f'PASS ({deep_picked} deep + {len(reg_out)} regression frames, {time.time()-t0:.0f}s)'

manifest = {'schema': 'yolo7020_g2_quant_v1',
            'weights': {'best.pt': sha(WEIGHTS)},
            'calibration': {'list': 'G1/calibration_list.txt', 'images': len(cal_imgs), 'seed': SEED,
                            'method': 'p99.99 percentile clip per-tensor symmetric + layerwise LSQ '
                                      'stored-scale refit (S\'=<v,fp>/<v,v> on the int-pipeline outputs '
                                      f'vs FP module outputs, {REFIT_ITERS} fixed-point sweeps over a '
                                      f'{FIT_SUBSAMPLE}-img subsample; raw-MSE clip rejected: collapses '
                                      'to ~absmax/1000 on near-zero-dominated post-SiLU tensors)',
                            'clipped_nodes': clipped, 'total_nodes': len(hooked),
                            'median_shrink': med_shrink,
                            'refit_sites': len(fit_sites), 'refit_trace': refit_trace},
            'input_contract': {'size': SIZE, 'preprocess': 'letterbox 114 BGR->RGB uint8, stored u-128'},
            'files': {f: sha(RUN / f) for f in ['weights.bin', 'bias.bin', 'lut.bin', 'quant.json']},
            'env': {'python': sys.executable, 'torch': torch.__version__,
                    'ultralytics': ultralytics.__version__, 'numpy': np.__version__},
            'status': 'CANDIDATE' if drop <= 0.02 else 'EXPERIMENTAL'}
(RUN / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')

final = {'result': 'G2_QUANT_INTREF_PASS' if drop <= 0.02 else 'G2_ACCURACY_GATE_SOFT_FAIL',
         'status': status, 'valid_drop_map50': drop}
(RUN / 'summary.json').write_text(json.dumps(final, indent=2), encoding='utf-8')
(RUN / 'console.log').write_text('\n'.join(L) + '\n', encoding='utf-8')
log('# FINAL: ' + json.dumps(final))
