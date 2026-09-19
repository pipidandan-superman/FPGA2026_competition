"""离线调度编译器（PC 侧，一次性）：模型拓扑 + G2 包 -> schedule.json。

- 输入：3_host/model/best.pt（仅取拓扑/结构属性）、rom_data 部署包（quant.json）。
- 输出：rom_data/schedule.json —— 任务列表 + 张量缓冲表，PS 运行时与后续 RTL
  调度器的共同输入。执行语义与 G2 run_g2_quant.int_forward 逐任务对应。
- 板上运行时不依赖 torch/ultralytics：全部结构信息（shape、split 通道、concat
  源、stride/pad、首层 z 折叠项）在本阶段固化进 schedule。
"""
import json
import os
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = Path('E:/competition')
ROM = ROOT / '2_fpga/3_yolo_zynq/rom_data'
WEIGHTS = ROOT / '3_host/model/best.pt'

os.environ.update(YOLO_OFFLINE='true', YOLO_AUTOINSTALL='false', PYTHONNOUSERSITE='1',
                  PYTHONDONTWRITEBYTECODE='1', OMP_NUM_THREADS='2', MKL_NUM_THREADS='2')
import torch
import torch.nn as nn
from ultralytics import YOLO
from ultralytics.nn.modules import Conv as UConv, C2f, SPPF, Concat, Detect

sys.path.insert(0, str(HERE))
from yolo_pkg import YoloPackage

pkg = YoloPackage(ROM)
SIZE = pkg.size
model = YOLO(str(WEIGHTS)).model.eval()
TOP = model.model

bufs = []


def newbuf(shape, producer):
    bid = len(bufs)
    bufs.append({'id': bid, 'shape': [int(s) for s in shape], 'producer': producer})
    return bid


tasks = []


def shape_after(in_shape, nd):
    _, _, kh, kw = nd['w_shape']
    sh, sw = nd['stride']
    ph, pw = nd['pad']
    return [(in_shape[1] + 2 * ph - kh) // sh + 1,
            (in_shape[2] + 2 * pw - kw) // sw + 1]


def conv_task(name, in_buf, in_shape, first=False):
    nd = pkg.node(name)
    oc = nd['w_shape'][0]
    Ho, Wo = shape_after(in_shape, nd)
    ob = newbuf([oc, Ho, Wo], name)
    t = {'op': 'conv', 'node': name, 'in': in_buf, 'out': ob,
         'out_shape': [oc, Ho, Wo], 'stride': nd['stride'], 'pad': nd['pad'],
         'k': nd['w_shape'][2:4], 'has_act': nd['has_act'], 'first': first,
         'req': nd['req']}
    tasks.append(t)
    return ob, [oc, Ho, Wo]


def view_task(name, in_buf, in_shape, ch_lo, ch_hi, producer):
    ob = newbuf([ch_hi - ch_lo] + list(in_shape[1:]), producer)
    tasks.append({'op': 'view', 'node': name, 'in': in_buf, 'out': ob,
                  'ch': [ch_lo, ch_hi]})
    return ob, [ch_hi - ch_lo] + list(in_shape[1:])


def add_task(name, a_buf, a_s, b_buf, b_s, out_s, shape):
    ob = newbuf(shape, name)
    tasks.append({'op': 'add', 'node': name, 'a': a_buf, 'a_scale': a_s,
                  'b': b_buf, 'b_scale': b_s, 'out': ob, 'out_scale': out_s})
    return ob


def pool_task(name, in_buf, in_shape):
    C, H, W = in_shape
    ob = newbuf([C, H, W], name)
    tasks.append({'op': 'maxpool5', 'node': name, 'in': in_buf, 'out': ob})
    return ob


def up_task(name, in_buf, in_shape):
    C, H, W = in_shape
    ob = newbuf([C, H * 2, W * 2], name)
    tasks.append({'op': 'upsample2', 'node': name, 'in': in_buf, 'out': ob})
    return ob, [C, H * 2, W * 2]


def cat_task(name, inputs, out_scale, shape):
    """inputs: [(buf, scale)]。尺度全一致时执行器跳过重量化（与 int_forward 相同）。"""
    ob = newbuf(shape, name)
    tasks.append({'op': 'concat', 'node': name,
                  'inputs': [{'buf': b, 'scale': s} for b, s in inputs],
                  'out': ob, 'out_scale': out_scale})
    return ob


outs = {}   # 'model.N' -> (buf, shape, scale)；顶层顺序输出即下一模块输入

b_in = newbuf([3, SIZE, SIZE], 'input')
n0 = pkg.node('model.0')
z_sum_w = (128 * pkg.w('model.0').reshape(n0['w_shape'][0], -1)
           .sum(axis=1)).astype(np.int64).tolist()
b0, s0 = conv_task('model.0', b_in, [3, SIZE, SIZE], first=True)
tasks[-1]['z_sum_w'] = z_sum_w
outs['model.0'] = (b0, s0, pkg.stored_scale('model.0'))

for i in range(1, len(TOP)):
    mod = TOP[i]
    pre = f'model.{i}'
    src = outs[f'model.{i - 1}']      # v8 顶层为顺序执行，i 的输入 = i-1 的输出
    if isinstance(mod, UConv):
        ob, sh = conv_task(pre, src[0], src[1])
        outs[pre] = (ob, sh, pkg.stored_scale(pre))
    elif isinstance(mod, C2f):
        b_cv1, s_cv1 = conv_task(f'{pre}.cv1', src[0], src[1])
        sc_cv1 = pkg.stored_scale(f'{pre}.cv1')
        c = s_cv1[0] // 2
        pa, sa = view_task(f'{pre}.split0', b_cv1, s_cv1, 0, c, f'{pre}.cv1[0:{c}]')
        pb, sb = view_task(f'{pre}.split1', b_cv1, s_cv1, c, 2 * c, f'{pre}.cv1[{c}:]')
        parts = [(pa, sa, sc_cv1), (pb, sb, sc_cv1)]
        for bi, bt in enumerate(mod.m):
            h_buf, h_shape, h_s = parts[-1]
            b1, s1 = conv_task(f'{pre}.m.{bi}.cv1', h_buf, h_shape)
            b2, s2 = conv_task(f'{pre}.m.{bi}.cv2', b1, s1)
            sc2 = pkg.stored_scale(f'{pre}.m.{bi}.cv2')
            if bt.add:
                out_s = pkg.tensor_scales[f'{pre}.m.{bi}']
                ba = add_task(f'{pre}.m.{bi}', b2, sc2, parts[-1][0], parts[-1][2],
                              out_s, s2)
                parts.append((ba, s2, out_s))
            else:
                parts.append((b2, s2, sc2))
        cat_ch = sum(p[1][0] for p in parts)
        b_cat = cat_task(f'{pre}.cat', [(p[0], p[2]) for p in parts], sc_cv1,
                         [cat_ch] + s_cv1[1:])
        b_cv2, s_cv2 = conv_task(f'{pre}.cv2', b_cat, [cat_ch] + s_cv1[1:])
        outs[pre] = (b_cv2, s_cv2, pkg.stored_scale(f'{pre}.cv2'))
    elif isinstance(mod, SPPF):
        b1, s1 = conv_task(f'{pre}.cv1', src[0], src[1])
        sc1 = pkg.stored_scale(f'{pre}.cv1')
        pools = [b1]
        for pi in range(3):
            nb = pool_task(f'{pre}.pool{pi}', pools[-1], s1)
            pools.append(nb)
        b_cat = cat_task(f'{pre}.cat', [(p, sc1) for p in pools], sc1,
                         [4 * s1[0]] + s1[1:])
        b2, s2 = conv_task(f'{pre}.cv2', b_cat, [4 * s1[0]] + s1[1:])
        outs[pre] = (b2, s2, pkg.stored_scale(f'{pre}.cv2'))
    elif isinstance(mod, nn.Upsample):
        ob, sh = up_task(pre, src[0], src[1])
        outs[pre] = (ob, sh, src[2])
    elif isinstance(mod, Concat):
        srcs = mod.f if isinstance(mod.f, list) else [mod.f]
        gathered, ch = [], 0
        for s_ in srcs:
            j = (i + s_) if s_ < 0 else s_
            bufj, shj, scj = outs[f'model.{j}']
            gathered.append((bufj, scj))
            ch += shj[0]
        ref_shape = outs[f'model.{(i + srcs[0]) if srcs[0] < 0 else srcs[0]}'][1]
        out_s = pkg.tensor_scales[pre]
        b_cat = cat_task(pre, gathered, out_s, [ch] + ref_shape[1:])
        outs[pre] = (b_cat, [ch] + ref_shape[1:], out_s)
    elif isinstance(mod, Detect):
        heads = {'reg': [], 'cls': []}
        fins = [outs['model.15'], outs['model.18'], outs['model.21']]
        for br in range(3):
            h, hs_, hsc = fins[br]
            for li in range(len(mod.cv2[br])):
                nm = f'{pre}.cv2.{br}.{li}'
                h, hs_ = conv_task(nm, h, hs_)
                hsc = pkg.stored_scale(nm)
            heads['reg'].append({'buf': h, 'scale': hsc, 'shape': hs_})
            h, hs_, hsc = fins[br]
            for li in range(len(mod.cv3[br])):
                nm = f'{pre}.cv3.{br}.{li}'
                h, hs_ = conv_task(nm, h, hs_)
                hsc = pkg.stored_scale(nm)
            heads['cls'].append({'buf': h, 'scale': hsc, 'shape': hs_})
        tasks.append({'op': 'heads', 'node': pre, 'reg': heads['reg'], 'cls': heads['cls']})
    else:
        raise RuntimeError(f'unhandled module {pre}: {type(mod)}')

schedule = {
    'schema': 'yolo7020_sched_v1',
    'input': {'buf': b_in, 'shape': [3, SIZE, SIZE], 'scale': pkg.input_scale,
              'stored': 'uint8-128', 'letterbox': 114},
    'buffers': bufs,
    'tasks': tasks,
    'strides': [8, 16, 32],
    'source': {'package': 'rom_data', 'quant_contract': pkg.quant['contract']},
}
(ROM / 'schedule.json').write_text(json.dumps(schedule, indent=1), encoding='utf-8')
print(f'schedule.json: {len(tasks)} tasks, {len(bufs)} buffers, input {SIZE}')
for t in tasks[:6]:
    print(' ', t['op'], t['node'], '->', t.get('out'))
