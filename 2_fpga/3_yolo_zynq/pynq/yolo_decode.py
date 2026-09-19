"""PS 侧解码链：DFL softmax + sigmoid + NMS（float64，确定性）。

与 G2 intref_yolov8.softmax_dfl_decode / nms_numpy 语义一致（同一评估口径）；
板上 C 实现须满足：远离阈值样例类别/框决策一致，边界差异单独解释（计划 §10.4）。
"""
import numpy as np


def softmax_dfl_decode(raw_reg_q, raw_reg_scale, raw_cls_q, raw_cls_scale, stride,
                       conf_thres=0.001):
    """一个尺度的原始头 -> (xywh 框 px, 分数, 类别)。"""
    reg = raw_reg_q[0].astype(np.float64) * raw_reg_scale
    cls = raw_cls_q[0].astype(np.float64) * raw_cls_scale
    C4, H, W = reg.shape
    n_cls = cls.shape[0]
    reg = reg.reshape(4, 16, H, W)
    e = np.exp(reg - reg.max(axis=1, keepdims=True))
    e /= e.sum(axis=1, keepdims=True)
    ar = np.arange(16, dtype=np.float64)[None, :, None, None]
    dist = (e * ar).sum(axis=1)
    xs = (np.arange(W)[None, None, :] + 0.5) * stride
    ys = (np.arange(H)[None, :, None] + 0.5) * stride
    x1 = xs - dist[0] * stride
    y1 = ys - dist[1] * stride
    x2 = xs + dist[2] * stride
    y2 = ys + dist[3] * stride
    boxes = np.stack([(x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1],
                     axis=-1).reshape(-1, 4)
    scores_sig = 1.0 / (1.0 + np.exp(-cls.reshape(n_cls, -1).T))
    cls_ids = scores_sig.argmax(axis=1)
    conf = scores_sig.max(axis=1)
    keep = conf > conf_thres
    return boxes[keep], conf[keep], cls_ids[keep]


def nms_numpy(boxes_xywh, scores, cls_ids, iou_thr=0.5, max_det=300):
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
    return np.array(keep_out, dtype=int)[:max_det] if keep_out else np.array([], dtype=int)


def decode_all(regs, clss, reg_scales, cls_scales, strides=(8, 16, 32)):
    allb, allc, allk = [], [], []
    for b in range(3):
        bx, cf, ki = softmax_dfl_decode(regs[b], reg_scales[b], clss[b], cls_scales[b],
                                        strides[b])
        allb.append(bx)
        allc.append(cf)
        allk.append(ki)
    bx = np.concatenate(allb)
    cf = np.concatenate(allc)
    ki = np.concatenate(allk)
    keep = nms_numpy(bx, cf, ki)
    return bx[keep], cf[keep], ki[keep]


def letterbox_u8_rgb(img_bgr, sz):
    import cv2
    h, w = img_bgr.shape[:2]
    r = min(sz / h, sz / w)
    nh, nw = round(h * r), round(w * r)
    res = cv2.resize(img_bgr, (nw, nh), interpolation=cv2.INTER_LINEAR)
    canvas = np.full((sz, sz, 3), 114, dtype=np.uint8)
    top, left = (sz - nh) // 2, (sz - nw) // 2
    canvas[top:top + nh, left:left + nw] = res
    return canvas[:, :, ::-1].copy()
