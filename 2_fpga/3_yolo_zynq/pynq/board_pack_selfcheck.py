"""PC 侧：打包板端自检输入并本地预验一次（板端零 cv2/零数据集依赖）。

产物（2_fpga/3_yolo_zynq/pynq/board_pack/）：
  inputs.npz          — [N,S,S,3] uint8 letterbox 后画布（与离线自检同一 letterbox）
  expected.json       — 每帧 raw_head_sha256 + 解码参考（源 = run04 回归记录）
  pack_manifest.json  — inputs.npz/expected.json 的 SHA-256 + 生成信息

预验：直接从 npz 读画布跑 YoloRuntime，对 run04 期望值 128/128 head+box
逐项核对——证明"打包文件本身"可复现离线 PASS，再上板。板端由
board_selfcheck.py 消费同一目录。数据集与 cv2 只在 PC 本脚本出现。
"""
import hashlib
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = Path('E:/competition')
ROM = ROOT / '2_fpga/3_yolo_zynq/rom_data'
G2 = ROOT / '4_metrics/logs/2026-09-15_yolo7020_g2_quant_rne_run04'
DATASET = ROOT / '3_host/model_datasets/dataset'
OUT = HERE / 'board_pack'

sys.path.insert(0, str(HERE))
from yolo_runtime import YoloRuntime
from yolo_decode import decode_all, letterbox_u8_rgb


def sha256_file(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    reg = json.loads((G2 / 'regression_128frames.json').read_text(encoding='utf-8'))
    rt = YoloRuntime(ROM)

    # ---- 1. 画布打包（复用离线自检同一 letterbox 路径） ----
    canvases = np.empty((len(reg), rt.size, rt.size, 3), dtype=np.uint8)
    for k, e in enumerate(reg):
        im = DATASET / e['split'] / 'images' / e['image']
        canvases[k] = letterbox_u8_rgb(cv2.imread(str(im)), rt.size)
    OUT.mkdir(exist_ok=True)
    np.savez_compressed(OUT / 'inputs.npz', canvas=canvases)

    expected = [{'split': e['split'], 'image': e['image'],
                 'raw_head_sha256': e['raw_head_sha256'],
                 'boxes': e['boxes'], 'conf': e['conf'], 'cls': e['cls']}
                for e in reg]
    (OUT / 'expected.json').write_text(
        json.dumps(expected, ensure_ascii=False, indent=1), encoding='utf-8')

    # ---- 2. 本地预验：只经 npz 文件走一遍（模拟板端输入路径） ----
    z = np.load(OUT / 'inputs.npz')
    loaded = z['canvas']
    t0 = time.time()
    n_head = n_box = 0
    fails = []
    for k, e in enumerate(expected):
        regs, clss, rs, cs = rt.run(loaded[k])
        hh = hashlib.sha256()
        for r in regs + clss:
            hh.update(r.tobytes())
        head_ok = hh.hexdigest() == e['raw_head_sha256']
        bx, cf, ki = decode_all(regs, clss, rs, cs)
        box_ok = (np.round(bx, 2).tolist() == e['boxes']
                  and np.round(cf, 4).tolist() == e['conf']
                  and ki.tolist() == e['cls'])
        n_head += head_ok
        n_box += box_ok
        if not (head_ok and box_ok):
            fails.append({'i': k, 'image': e['image'], 'head': head_ok, 'box': box_ok})
        if k < 3 or not (head_ok and box_ok):
            print(f'  [{k:3d}] {e["image"][:28]:28s} head={head_ok} box={box_ok}', flush=True)
    dt = time.time() - t0
    print(f'[pre-verify] head {n_head}/{len(reg)}, box {n_box}/{len(reg)}, '
          f'{dt:.0f}s ({dt/len(reg)*1000:.0f} ms/frame, PC)')
    assert n_head == len(reg) and n_box == len(reg), f'pack pre-verify FAILED: {fails[:5]}'

    # ---- 3. pack manifest（板端校验传输完整性） ----
    pm = {
        'frames': len(reg),
        'input_size': rt.size,
        'rom_source': 'rom_data (g2_quant_rne run04)',
        'rom_files_sha256': {f: v for f, v in rt.pkg.verify_hashes().items()},
        'inputs_sha256': sha256_file(OUT / 'inputs.npz'),
        'expected_sha256': sha256_file(OUT / 'expected.json'),
    }
    (OUT / 'pack_manifest.json').write_text(
        json.dumps(pm, indent=1), encoding='utf-8')
    print(f'[pack] {OUT}  inputs.npz={len(canvases)} frames, '
          f'sha256={pm["inputs_sha256"][:16]}..., pre-verify 128/128 PASS')


if __name__ == '__main__':
    main()
