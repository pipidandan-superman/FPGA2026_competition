"""调试：PS 运行时 vs G2 golden npz 的首个分歧节点（用 npz 内 canvas_u8 免除 letterbox 变量）。"""
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = Path('E:/competition')
PYNQ = ROOT / '2_fpga/3_yolo_zynq/pynq'
ROM = ROOT / '2_fpga/3_yolo_zynq/rom_data'
G2 = ROOT / '4_metrics/logs/2026-09-14_yolo7020_g2_quant_intref_run01'

sys.path.insert(0, str(PYNQ))
from yolo_runtime import YoloRuntime

gi = json.loads((G2 / 'golden_index.json').read_text(encoding='utf-8'))
e = gi[0]
z = np.load(G2 / e['file'])
canvas = z['canvas_u8']
print(f"golden[0] {e['image']} canvas {canvas.shape} {canvas.dtype}")

rt = YoloRuntime(ROM)
bufs = {rt.sched['input']['buf']:
        (canvas.astype(np.int16) - 128).astype(np.int8)[None].transpose(0, 3, 1, 2).copy()}
gkeys = {k[5:] for k in z.files if k.startswith('int8_')}

# 按 task 顺序执行并即时比对（producer 名与 golden int8_<name> 对应）
checked = 0
for t in rt.sched['tasks']:
    op = t['op']
    if op == 'conv':
        bufs[t['out']] = rt._conv(t, bufs[t['in']])
    elif op == 'view':
        lo, hi = t['ch']
        bufs[t['out']] = bufs[t['in']][:, lo:hi].copy()
    elif op == 'add':
        bufs[t['out']] = rt._add(t, bufs[t['a']], bufs[t['b']])
    elif op == 'concat':
        parts = [bufs[x['buf']] if abs(x['scale'] - t['out_scale']) <= 1e-15
                 else __import__('intarith').requant_to(bufs[x['buf']], x['scale'], t['out_scale'])
                 for x in t['inputs']]
        bufs[t['out']] = np.concatenate(parts, axis=1)
    elif op == 'maxpool5':
        bufs[t['out']] = __import__('intarith').maxpool5(bufs[t['in']])
    elif op == 'upsample2':
        bufs[t['out']] = __import__('intarith').upsample_nearest2(bufs[t['in']])
    elif op == 'heads':
        continue
    name = t['node']
    gname = name if name in gkeys else None
    if gname is None:
        continue
    mine = bufs[t['out']]
    gold = z[f'int8_{gname}']
    checked += 1
    same = mine.shape == gold.shape and np.array_equal(mine, gold[None] if gold.ndim == 3 else gold)
    if not same:
        d = (mine.astype(np.int32) - (gold[None] if gold.ndim == 3 else gold).astype(np.int32))
        nz = int((d != 0).sum())
        print(f'FIRST DIFF @ {name} (op {op}): shape mine {mine.shape} gold {gold.shape}, '
              f'{nz}/{d.size} elems differ, max|d|={np.abs(d).max()}, first idx '
              f'{np.argwhere(d != 0)[:3].tolist()}')
        print('  task:', json.dumps({k: v for k, v in t.items() if k not in ("z_sum_w", "req")})[:220])
        break
else:
    print(f'all {checked} golden nodes match')

# 对照包内 node 元数据，打印首差节点邻域 in/out scale
