"""PC 侧：对板端 heads_diag.json 定量差分（纯解码阶段差异归因）。

前提：诊断帧 head_sha256 与期望一致（整数路径位级相同）→ 板/PC 解码输入
完全相同，任何输出差异 100% 来自 float64 解码（exp/sigmoid/除法/排序）。

每帧输出：
  n_boxes   板/PC 框数是否相等
  perm      行序是否置换（排序后逐值相等 → 纯顺序差异）
  max_dbox  全精度坐标最大 |Δ|（px）
  max_dconf 全精度置信最大 |Δ|
  flips_2dp/4dp  按期望门（框 2dp/置信 4dp 舍入后精确相等）被翻转的元素数
"""
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
PYNQ = Path('E:/competition/2_fpga/3_yolo_zynq/pynq')
ROM = Path('E:/competition/2_fpga/3_yolo_zynq/rom_data')
PACK = PYNQ / 'board_pack'

sys.path.insert(0, str(PYNQ))
from yolo_runtime import YoloRuntime
from yolo_decode import decode_all


def rounded(bx, cf, ki):
    return np.round(bx, 2).tolist(), np.round(cf, 4).tolist(), ki.tolist()


def main():
    diag = json.loads((HERE / 'heads_diag.json').read_text(encoding='utf-8'))
    expected = json.loads((PACK / 'expected.json').read_text(encoding='utf-8'))
    rt = YoloRuntime(ROM)
    canvases = np.load(PACK / 'inputs.npz')['canvas']

    for d in diag:
        e = expected[d['i']]
        assert d['head_ok'], f'frame {d["i"]}: head sha mismatch — 不可比'
        # PC 全精度参考（同头字节）
        regs, clss, rs, cs = rt.run(canvases[d['i']])
        pbx, pcf, pci = decode_all(regs, clss, rs, cs)
        bbx = np.array(d['boxes_full'], dtype=np.float64).reshape(-1, 4)
        bcf = np.array(d['conf_full'], dtype=np.float64)

        # 期望门下板端翻转数
        ebx, ecf, eki = rounded(bbx, bcf, np.array(d['cls'], dtype=int))
        flips_box = sum(1 for a, b in zip(ebx, e['boxes']) if a != b) if len(ebx) == len(e['boxes']) else -1
        flips_conf = sum(1 for a, b in zip(ecf, e['conf']) if a != b) if len(ecf) == len(e['conf']) else -1

        same_n = (len(bbx) == len(pbx))
        if same_n and len(bbx):
            max_dbox = float(np.abs(bbx - pbx).max())
            max_dconf = float(np.abs(bcf - pcf).max())
            # 置换判定：按(类别,x,y,w,h,conf)排序后逐值比
            key_b = np.stack([d['cls'], bbx[:, 0], bbx[:, 1], bbx[:, 2], bbx[:, 3], bcf], 1)
            key_p = np.stack([pci.tolist(), pbx[:, 0], pbx[:, 1], pbx[:, 2], pbx[:, 3], pcf], 1)
            perm = bool(np.allclose(np.array(sorted(map(tuple, key_b.tolist()))),
                                    np.array(sorted(map(tuple, key_p.tolist()))), atol=1e-9))
        else:
            max_dbox = max_dconf = None
            perm = False

        print(f'frame {d["i"]:3d} {d["image"][:26]:26s} '
              f'n_board={len(bbx)} n_pc={len(pbx)} same_n={same_n} perm={perm} '
              f'max_dbox={max_dbox} max_dconf={max_dconf} '
              f'flips(box2dp/conf4dp)={flips_box}/{flips_conf}')
        if not same_n:
            print(f'         board cls={d["cls"]}')
            print(f'         pc    cls={pci.tolist()}')


if __name__ == '__main__':
    main()
