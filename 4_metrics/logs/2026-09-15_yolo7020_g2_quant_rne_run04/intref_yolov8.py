"""HWINT integer reference for YOLOv8n gesture model (deployment plan r3 §4.2/§4.6).

Numerical contract (W8A8, v1 — frozen for this package):
  - weights: INT8, per-output-channel symmetric, zero point 0; quant RNE (np.round)
  - activations: INT8, per-tensor symmetric, zero point 0 (first layer input
    stored as uint8->int8 offset with z_x folded into bias, see below)
  - accumulate: INT32; bias INT32 = round(Sx*Sw*(Wf64*gamma/sqrt(var+eps)+b_folded... ) ) exactly:
        W_fold = W * gamma/sqrt(var+eps)          (float64)
        b_fold = beta - mean*gamma/sqrt(var+eps)  (float64)
        w_q[c] = RNE(W_fold[c] / (max_c|W_fold[c]|/127))
        b_q[c] = RNE(b_fold[c] / (Sx*Sw_c))       (Sx = input tensor scale)
  - requant: y_q = sat_int8(RNE(acc * M / 2^shift)), (M,shift) from r=Sx*Sw/Sy,
        r = f*2^e, f in [0.5,1), M = RNE(f*2^31), shift = 31-e; int64 intermediate
  - RNE on signed right shift: floor then adjust to nearest, ties-to-even
  - SiLU: 256-entry LUT over the PRE-activation INT8 domain; the LUT OUTPUT is
    stored at the post-activation calibrated scale S_post (finer than S_pre
    whenever the pre-act range is negative-dominated, recovering ~2 bits):
        out_q = RNE_i8(silu(S_pre*i) / S_post)
    node.s_stored = the scale of the tensor this node emits downstream
    (S_post for activated nodes, out_scale for linear tips)
  - first conv input: uint8 RGB stored as int8 u-128; the -128 zero-point term is
    folded into that layer's bias as -128*sum_c(w_q) (exact integer)
  - Add: y_q = sat_int32(a_q*M1/2^s1 + b_q*M2/2^s2) summed in int32 then saturated once to int8
  - internal C2f concat: adopts FIRST input tensor's scale; other inputs requantized to it
  - top-level Concat: own calibrated scale; inputs requantized
  - MaxPool 5x5 s1: int8 max, border pad -128; Upsample nearest x2: replicate (scale kept)
  - head tip Conv2d (no act): raw logits INT8 at per-branch scale; PS decodes in float64
Everything here is deterministic; no hidden float in the PL-path ops.
"""
from __future__ import annotations
from pathlib import Path
import numpy as np
import torch
import torch.nn.functional as F


def rne_shift(n: np.ndarray, s: int) -> np.ndarray:
    """Round-to-nearest-even divide of int64 array by 2^s (s>=0).

    s MUST be normalized to a Python int first: np.frexp exponents arrive as
    np.int32, and under NEP50 `1 << np.int32(41)` wraps to 0, silently turning
    the tie threshold `full` into 0 and degrading RNE to round-away-from-zero
    (mean +0.5 LSB) for every shift >= 32. Found via PS-runtime offline diff.
    """
    s = int(s)
    if s <= 0:
        if s == 0:
            return n.astype(np.int64)
        v = n.astype(np.int64) << (-s)
        assert np.abs(v).max(initial=0) < 2**63, 'shift-left overflow'
        return v
    q = n >> s                      # arithmetic floor
    rem = n - (q << s)              # (-2^s, 2^s)
    twice = rem * 2
    full = 1 << s                   # tie threshold: |2*rem| == 2^s  <=>  |rem| == half
    q = q + np.where(twice > full, 1, 0) + np.where(twice < -full, -1, 0)
    tie = (twice == full) | (twice == -full)
    q = q + np.where(tie & ((q & 1) == 1), np.where(twice > 0, 1, -1), 0)
    return q


def sat_i8(x):
    return np.clip(x, -128, 127).astype(np.int8)


def sat_i32(x):
    return np.clip(x, -2**31, 2**31 - 1).astype(np.int32)


def req_pair(r: float):
    """Multiplier/shift pair approximating r>0 with M/2^shift, M int32."""
    assert r > 0
    f, e = np.frexp(r)              # r = f*2^e, f in [0.5,1)
    while f < 0.5:
        f *= 2
        e -= 1
    while f >= 1.0:
        f /= 2
        e += 1
    M = int(np.round(f * (1 << 31)))
    if M >= (1 << 31):              # rounding pushed to 1.0
        M >>= 1
        e += 1
    shift = 31 - e
    if shift > 62:                  # r < ~2^-32: BN-killed/dead channel. Representable
        return 0, 0                 # product |n*r| < 0.5 for |n| < 2^31 -> rounds to 0 anyway.
    return M, shift


class QConv:
    """One quantized conv node (folded BN, optional SiLU LUT)."""
    def __init__(self, name, torch_conv, torch_bn, has_act, in_scale, out_scale,
                 act_out_scale=None):
        """out_scale = requant domain (pre-activation absmax for activated nodes);
        act_out_scale = stored-tensor scale after the SiLU LUT (post-act absmax).
        Defaults to out_scale when omitted."""
        w = torch_conv.weight.detach().numpy().astype(np.float64)   # [oc,ic,kh,kw]
        b = torch_conv.bias.detach().numpy().astype(np.float64) if torch_conv.bias is not None else np.zeros(w.shape[0])
        if torch_bn is not None:
            g = torch_bn.weight.detach().numpy().astype(np.float64)
            bb = torch_bn.bias.detach().numpy().astype(np.float64)
            mu = torch_bn.running_mean.detach().numpy().astype(np.float64)
            var = torch_bn.running_var.detach().numpy().astype(np.float64)
            eps = float(torch_bn.eps)
            scale_bn = g / np.sqrt(var + eps)
            w = w * scale_bn[:, None, None, None]
            b = bb + (b - mu) * scale_bn
        oc = w.shape[0]
        self.name, self.has_act = name, has_act
        self.stride, self.pad = torch_conv.stride, torch_conv.padding
        self.kh, self.kw = w.shape[2], w.shape[3]
        w_per_oc_max = np.max(np.abs(w).reshape(oc, -1), axis=1)
        self.w_scales = w_per_oc_max / 127.0
        self.w_scales[self.w_scales == 0] = 1e-12
        self.w_q = np.stack([np.round(w[c] / self.w_scales[c]) for c in range(oc)]).astype(np.int8)
        self.b_q = np.round(b / (in_scale * self.w_scales)).astype(np.int64)
        self.b_q = np.clip(self.b_q, -2**31, 2**31 - 1).astype(np.int32)
        self.x_scale, self.y_scale = in_scale, out_scale
        self.reqs = [req_pair((in_scale * self.w_scales[c]) / out_scale) for c in range(oc)]
        if has_act:
            idx = np.arange(-128, 128, dtype=np.float64)
            pre_real = idx * out_scale
            silu = pre_real / (1.0 + np.exp(-pre_real))
            s_act = out_scale if act_out_scale is None else act_out_scale
            # LUT input: pre-act domain; LUT output: post-act stored scale
            self.lut = sat_i8(np.round(silu / s_act))
            self.s_stored = s_act
        else:
            self.lut = None
            self.s_stored = out_scale

    def acc_i32(self, x_q: np.ndarray, pad_val: int = 0):
        """x_q int8 NCHW -> int32 acc NCHW (per-channel bias NOT yet added).
        pad_val = input zero point in stored domain (0 for z=0 layers,
        -128 for the first layer) so zero-point correction stays exact."""
        N, C, H, W = x_q.shape
        oc, ic, kh, kw = self.w_q.shape
        sh, sw = self.stride
        ph, pw = self.pad
        Ho = (H + 2 * ph - kh) // sh + 1
        Wo = (W + 2 * pw - kw) // sw + 1
        xp = np.full((N, C, H + 2 * ph, W + 2 * pw), pad_val, dtype=np.int8)
        if ph or pw:
            xp[:, :, ph:ph + H, pw:pw + W] = x_q
        else:
            xp = x_q.copy()
        cols = np.empty((C * kh * kw, Ho * Wo), dtype=np.int32)
        pos = 0
        for c in range(C):
            for i in range(kh):
                for j in range(kw):
                    patch = xp[:, c, i:i + sh * Ho:sh, j:j + sw * Wo:sw]
                    cols[pos] = patch.reshape(N, -1)[0]
                    pos += 1
        wmat = self.w_q.reshape(oc, -1).astype(np.int32)
        acc = (wmat @ cols)                              # int32 [oc, Ho*Wo]
        return acc.reshape(1, oc, Ho, Wo)

    def forward(self, x_q: np.ndarray, z_sum_w=None):
        """z_sum_w: +128*colsum(w_q) int64[oc] for the first layer (z_x=-128),
        which together with pad_val=-128 makes the zero-point correction exact."""
        first = z_sum_w is not None
        acc = self.acc_i32(x_q, pad_val=-128 if first else 0)
        bias_eff = (self.b_q.astype(np.int64) + z_sum_w) if first else self.b_q.astype(np.int64)
        oc = acc.shape[1]
        out = np.empty(acc.shape, dtype=np.int8)
        for c in range(oc):
            M, s = self.reqs[c]
            n = (acc[:, c].astype(np.int64) + bias_eff[c]) * M
            out[:, c] = sat_i8(rne_shift(n, s))
        if self.lut is not None:
            out = self.lut[(out.astype(np.int16) + 128).astype(np.uint8)]
        return out


def requant_to(x_q: np.ndarray, s_from: float, s_to: float) -> np.ndarray:
    """Requant int8 tensor from scale s_from to s_to (used by Add/Concat paths)."""
    M, s = req_pair(s_from / s_to)
    n = x_q.astype(np.int64) * M
    return sat_i8(rne_shift(n, s))


def int_add(a_q, a_s, b_q, b_s, out_s):
    """a+b requantized to out_s (sum in int32, saturate once)."""
    Ma, sa = req_pair(a_s / out_s)
    Mb, sb = req_pair(b_s / out_s)
    A = rne_shift(a_q.astype(np.int64) * Ma, sa)
    B = rne_shift(b_q.astype(np.int64) * Mb, sb)
    return sat_i8(sat_i32(A + B))


def maxpool5(x_q: np.ndarray) -> np.ndarray:
    """5x5 stride1 maxpool, pad -128."""
    N, C, H, W = x_q.shape
    k = 5
    p = k // 2
    xp = np.full((N, C, H + 2 * p, W + 2 * p), -128, dtype=np.int8)
    xp[:, :, p:p + H, p:p + W] = x_q
    Ho, Wo = H + 2 * p - k + 1, W + 2 * p - k + 1
    out = np.full((N, C, Ho, Wo), -128, dtype=np.int8)
    for i in range(k):
        for j in range(k):
            np.maximum(out, xp[:, :, i:i + Ho, j:j + Wo], out=out)
    return out


def upsample_nearest2(x_q: np.ndarray) -> np.ndarray:
    return x_q.repeat(2, axis=2).repeat(2, axis=3)


def softmax_dfl_decode(raw_reg_q, raw_reg_scale, raw_cls_q, raw_cls_scale, stride, conf_thres=0.001):
    """PS-side decode (float64) of one scale's raw heads -> (boxes xywh in px, scores, class_ids)."""
    reg = raw_reg_q[0].astype(np.float64) * raw_reg_scale      # [64, H, W]
    cls = raw_cls_q[0].astype(np.float64) * raw_cls_scale      # [7, H, W]
    C4, H, W = reg.shape
    n_cls = cls.shape[0]
    reg = reg.reshape(4, 16, H, W)
    e = np.exp(reg - reg.max(axis=1, keepdims=True))
    e /= e.sum(axis=1, keepdims=True)
    ar = np.arange(16, dtype=np.float64)[None, :, None, None]
    dist = (e * ar).sum(axis=1)                                # [4,H,W] = l,t,r,b
    xs = (np.arange(W)[None, None, :] + 0.5) * stride
    ys = (np.arange(H)[None, :, None] + 0.5) * stride
    x1 = xs - dist[0] * stride
    y1 = ys - dist[1] * stride
    x2 = xs + dist[2] * stride
    y2 = ys + dist[3] * stride
    boxes = np.stack([(x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1], axis=-1).reshape(-1, 4)
    scores_sig = 1.0 / (1.0 + np.exp(-cls.reshape(n_cls, -1).T))   # [HW, n_cls]
    cls_ids = scores_sig.argmax(axis=1)
    conf = scores_sig.max(axis=1)
    keep = conf > conf_thres
    return boxes[keep], conf[keep], cls_ids[keep]


def nms_numpy(boxes_xywh, scores, cls_ids, iou_thr=0.5, max_det=300):
    """Class-aware NMS on xywh (matches ultralytics semantics closely enough for
    identical-evaluator comparison; same code path for FP32 and INT8)."""
    xy = boxes_xywh[:, :2]
    wh = boxes_xywh[:, 2:]
    areas = wh[:, 0] * wh[:, 1]
    keep_out = []
    for c in np.unique(cls_ids):
        idx = np.where(cls_ids == c)[0][np.argsort(-scores[np.where(cls_ids == c)[0]])]
        while len(idx) > 0:
            i = idx[0]
            keep_out.append(i)
            if len(idx) == 1:
                break
            rest = idx[1:]
            xx1 = np.maximum(xy[i, 0] - wh[i, 0] / 2, xy[rest, 0] - wh[rest, 0] / 2)
            yy1 = np.maximum(xy[i, 1] - wh[i, 1] / 2, xy[rest, 1] - wh[rest, 1] / 2)
            xx2 = np.minimum(xy[i, 0] + wh[i, 0] / 2, xy[rest, 0] + wh[rest, 0] / 2)
            yy2 = np.minimum(xy[i, 1] + wh[i, 1] / 2, xy[rest, 1] + wh[rest, 1] / 2)
            inter = np.maximum(0, xx2 - xx1) * np.maximum(0, yy2 - yy1)
            iou = inter / np.maximum(areas[i] + areas[rest] - inter, 1e-9)
            idx = rest[iou <= iou_thr]
    keep_out = np.array(keep_out, dtype=int)[:max_det] if keep_out else np.array([], dtype=int)
    return keep_out


def ap50_per_class(dets, gts, n_cls=7, iou_thr=0.5):
    """All-point AP50. dets/gts: lists per image of (boxes_xywh, conf, cls)."""
    import math
    per_class = {}
    for c in range(n_cls):
        scores, is_tp, npos = [], [], 0
        for (db, dc, di), (gb, _, gc) in zip(dets, gts):
            gmask = gc == c
            npos += int(gmask.sum())
            dmask = di == c
            if not dmask.any():
                continue
            b, s = db[dmask], dc[dmask]
            order = np.argsort(-s)
            matched = np.zeros(int(gmask.sum()), dtype=bool)
            for k in order:
                scores.append(s[k])
                cand = b[k]
                gbs = gb[gmask]
                if len(gbs) == 0:
                    is_tp.append(False)
                    continue
                xx1 = np.maximum(cand[0] - cand[2] / 2, gbs[:, 0] - gbs[:, 2] / 2)
                yy1 = np.maximum(cand[1] - cand[3] / 2, gbs[:, 1] - gbs[:, 3] / 2)
                xx2 = np.minimum(cand[0] + cand[2] / 2, gbs[:, 0] + gbs[:, 2] / 2)
                yy2 = np.minimum(cand[1] + cand[3] / 2, gbs[:, 1] + gbs[:, 3] / 2)
                iou = np.maximum(0, xx2 - xx1) * np.maximum(0, yy2 - yy1) / np.maximum(cand[2] * cand[3] + gbs[:, 2] * gbs[:, 3] - (np.maximum(0, xx2 - xx1) * np.maximum(0, yy2 - yy1)), 1e-9)
                best = np.argmax(iou)
                if iou[best] >= iou_thr and not matched[best]:
                    is_tp.append(True)
                    matched[best] = True
                else:
                    is_tp.append(False)
        if npos == 0 or not scores:
            per_class[c] = {'ap50': None, 'npos': npos}
            continue
        order = np.argsort(-np.array(scores))
        tp = np.array(is_tp, dtype=bool)[order]
        tp_cum = np.cumsum(tp)
        fp_cum = np.cumsum(~tp)
        recall = tp_cum / npos
        prec = tp_cum / np.maximum(tp_cum + fp_cum, 1e-9)
        mrec = np.concatenate(([0.0], recall, [1.0]))
        mpre = np.concatenate(([1.0], prec, [0.0]))
        for i in range(len(mpre) - 1, 0, -1):
            mpre[i - 1] = max(mpre[i - 1], mpre[i])
        ap = np.sum((mrec[1:] - mrec[:-1]) * mpre[1:])
        per_class[c] = {'ap50': float(ap), 'npos': npos}
    valid = [v['ap50'] for v in per_class.values() if v['ap50'] is not None]
    return per_class, (float(np.mean(valid)) if valid else 0.0)
