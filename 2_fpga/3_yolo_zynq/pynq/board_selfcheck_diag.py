"""板端解码差异诊断（PS_SELFCHECK_ONBOARD_HEAD_ONLY 时用，只读）。

背景：head 字节 sha256 与 PC 一致（整数路径位级相同），box 比对失败只能是
ARM/x86 libm 的 exp/除法末位差异。本脚本把板端 float64 解码原值全量导出：
  heads_diag.json — 每帧：head_sha256（复核）、boxes(全精度)、conf、cls、
  逐尺度 softmax 摘要（min/max exp 输入），供 PC 侧与期望值逐项差分定量
  （差多少 ulp / 2dp/4dp 舍入翻转几处 / 类别决策是否远离阈值）。
用法：python3 board_selfcheck_diag.py [--frames 8] [--pack-dir ...] [--rom-dir ...]
"""
import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from yolo_runtime import YoloRuntime
from yolo_decode import decode_all


def default_dir(cands):
    for c in cands:
        if c.is_dir():
            return c
    return cands[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rom-dir', type=Path,
                    default=default_dir([HERE / 'rom_data', HERE.parent / 'rom_data']))
    ap.add_argument('--pack-dir', type=Path, default=HERE / 'board_pack')
    ap.add_argument('--frames', type=int, default=8)
    ap.add_argument('--indices', type=str, default='',
                    help='逗号分隔帧号列表，如 0,1,6；给出时优先于 --frames')
    args = ap.parse_args()

    rt = YoloRuntime(args.rom_dir)
    z = np.load(args.pack_dir / 'inputs.npz')
    expected = json.loads((args.pack_dir / 'expected.json').read_text(encoding='utf-8'))
    if args.indices:
        idxs = [int(x) for x in args.indices.split(',') if x.strip() != '']
    else:
        idxs = list(range(len(expected) if args.frames <= 0
                          else min(args.frames, len(expected))))

    out = []
    for k in idxs:
        e = expected[k]
        t0 = time.time()
        regs, clss, rs, cs = rt.run(z['canvas'][k])
        hh = hashlib.sha256()
        for r in regs + clss:
            hh.update(r.tobytes())
        bx, cf, ki = decode_all(regs, clss, rs, cs)
        # 逐尺度 DFL softmax 前的极值（定位 exp 输入量级，供 libm 差异分析）
        exp_stats = []
        for b in range(3):
            reg = regs[b][0].astype(np.float64) * rs[b]
            exp_stats.append({'scale_min': float(reg.min()), 'scale_max': float(reg.max())})
        out.append({
            'i': k, 'image': e['image'],
            'head_sha256': hh.hexdigest(),
            'head_ok': hh.hexdigest() == e['raw_head_sha256'],
            'n_boxes': int(len(bx)),
            'boxes_full': np.round(bx, 6).tolist(),
            'conf_full': np.round(cf, 6).tolist(),
            'cls': ki.tolist(),
            'exp_range': exp_stats,
            'sec': round(time.time() - t0, 1),
        })
        print(f'[{k:3d}] {e["image"][:28]} n={len(bx)} {out[-1]["sec"]}s', flush=True)

    dst = HERE / 'diag_out'
    dst.mkdir(exist_ok=True)
    p = dst / 'heads_diag.json'
    p.write_text(json.dumps(out, indent=1), encoding='utf-8')
    print(f'[diag] written {p} ({len(idxs)} frames)')


if __name__ == '__main__':
    main()
