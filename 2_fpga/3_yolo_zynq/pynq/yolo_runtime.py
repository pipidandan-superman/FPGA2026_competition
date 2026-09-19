"""PS 侧调度执行器（离线解释器形态，numpy-only，无 torch/ultralytics）。

消费 rom_data/{schedule.json + G2 包}，输入 letterbox uint8 RGB，输出三尺度
原始 INT8 头 (reg/cls) + 尺度。整数语义与 G2 intref_yolov8 逐位一致：
  acc int32 = w_q @ im2col(x_q)；n = (acc + b_q [+ z_sum_w]) * M；
  out = sat_i8(rne_shift(n, shift))；激活节点再查 256 项 SiLU LUT。
板上此层逐步替换为 PL 描述符提交；本解释器保留为驱动级 golden/回退路径。
"""
import json
from pathlib import Path
import numpy as np

from intarith import rne_shift, sat_i8, sat_i32, requant_to, maxpool5, upsample_nearest2
from yolo_pkg import YoloPackage


def _dyadic(s_from, s_to):
    """(M, shift)：与 intref req_pair 相同的 frexp 规则（Add 路径用）。"""
    f, e = np.frexp(s_from / s_to)
    while f < 0.5:
        f *= 2
        e -= 1
    while f >= 1.0:
        f /= 2
        e += 1
    M = int(np.round(f * (1 << 31)))
    if M >= (1 << 31):
        M >>= 1
        e += 1
    s = 31 - e
    return (0, 0) if s > 62 else (M, s)


class YoloRuntime:
    def __init__(self, rom_dir):
        self.pkg = YoloPackage(rom_dir)
        self.sched = json.loads((Path(rom_dir) / 'schedule.json').read_text(encoding='utf-8'))
        self.size = self.sched['input']['shape'][-1]

    # ---- conv：im2col + int32 GEMM + 每通道重量化 (+LUT) ----
    def _conv(self, task, x_q):
        w = self.pkg.w(task['node'])                      # int8 [oc,ic,kh,kw]
        b = self.pkg.b(task['node']).astype(np.int64)
        oc, ic, kh, kw = w.shape
        sh, sw = task['stride']
        ph, pw = task['pad']
        first = task.get('first', False)
        pad_val = -128 if first else 0
        N, C, H, W = x_q.shape
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
        acc = (w.reshape(oc, -1).astype(np.int32) @ cols).reshape(1, oc, Ho, Wo)
        bias_eff = b + (np.array(task['z_sum_w'], dtype=np.int64) if first else 0)
        out = np.empty(acc.shape, dtype=np.int8)
        reqs = task['req']
        for c in range(oc):
            M, s = reqs[c]
            n = (acc[:, c].astype(np.int64) + bias_eff[c]) * M
            out[:, c] = sat_i8(rne_shift(n, s))
        if task['has_act']:
            lut = self.pkg.lut(task['node'])
            out = lut[(out.astype(np.int16) + 128).astype(np.uint8)]
        return out

    def _add(self, task, a, b):
        Ma, sa = _dyadic(task['a_scale'], task['out_scale'])
        Mb, sb = _dyadic(task['b_scale'], task['out_scale'])
        A = rne_shift(a.astype(np.int64) * Ma, sa)
        B = rne_shift(b.astype(np.int64) * Mb, sb)
        return sat_i8(sat_i32(A + B))

    def run(self, canvas_u8):
        """canvas_u8: RGB uint8 [S,S,3]（letterbox 114 已完成）-> (regs, clss)。"""
        bufs = {self.sched['input']['buf']:
                (canvas_u8.astype(np.int16) - 128).astype(np.int8)[None].transpose(0, 3, 1, 2).copy()}
        for t in self.sched['tasks']:
            op = t['op']
            if op == 'conv':
                bufs[t['out']] = self._conv(t, bufs[t['in']])
            elif op == 'view':
                lo, hi = t['ch']
                bufs[t['out']] = bufs[t['in']][:, lo:hi].copy()
            elif op == 'add':
                bufs[t['out']] = self._add(t, bufs[t['a']], bufs[t['b']])
            elif op == 'concat':
                parts = [bufs[e['buf']] if abs(e['scale'] - t['out_scale']) <= 1e-15
                         else requant_to(bufs[e['buf']], e['scale'], t['out_scale'])
                         for e in t['inputs']]
                bufs[t['out']] = np.concatenate(parts, axis=1)
            elif op == 'maxpool5':
                bufs[t['out']] = maxpool5(bufs[t['in']])
            elif op == 'upsample2':
                bufs[t['out']] = upsample_nearest2(bufs[t['in']])
            elif op == 'heads':
                regs = [bufs[h['buf']] for h in t['reg']]
                clss = [bufs[h['buf']] for h in t['cls']]
                return regs, clss, [h['scale'] for h in t['reg']], [h['scale'] for h in t['cls']]
            else:
                raise RuntimeError(f'unknown op {op}')
        raise RuntimeError('schedule has no heads task')
