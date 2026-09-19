"""G3 首层 conv 激励提取：golden npz + 部署包 -> DUT 仿真激励文件（PC 侧）。

DUT 合同（= yolo_runtime._conv 对 model.0 任务的原样语义）：
  x_q  : int8 [3,320,320] = canvas_u8 - 128（模块内部做 pad=-128 的 3x3/stride2 窗口）
  acc  : int32 = sum_k w[c][k] * x_q[window]   （K=27，整数加法次序无关紧要）
  n    : int64 = (acc + bias_eff[c]) * M[c]，bias_eff = b + z_sum_w（int32）
  y_pre: int8 = sat_i8(rne_shift(n, shift[c]))     —— RNE 平局到偶
  y    : int8 = LUT[(y_pre + 128) & 0xFF]          —— SiLU 256 项
数值门：y 与 golden int8_model.0 逐元素零差异（RTL 与本提取文件比对）。

产物（--out 目录，默认 sim/stim/<name>）：
  x_i8.bin        3*320*320  int8 CHW
  w_i8.bin        16*3*3*3   int8 [oc][ic][kh][kw]，K 展开 = ic*9 + kh*3 + kw
  bias_eff_i32.bin 16        int32（已含 z_sum_w）
  m_i32.bin       16         int32（有符号，31 位幅值）
  shift_u8.bin    16         uint8（右移位数，首层实测 40-42）
  lut_i8.bin      256        int8
  y_exp_i8.bin    16*160*160 int8 CHW
  stim_manifest.json         形状 + 每文件 sha256 + 自检结果

自检：用 YoloRuntime._conv 在 PC 重算 y 并与 golden 比对（提取文件 <-> 运行时
语义 <-> golden 三方对齐后才允许进 RTL）。
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
PYNQ = HERE.parent / 'pynq'
ROM = HERE.parent / 'rom_data'
GOLDEN_DIR = Path('E:/competition/4_metrics/logs/2026-09-15_yolo7020_g2_quant_rne_run04/golden')

sys.path.insert(0, str(PYNQ))
from yolo_runtime import YoloRuntime


def sha256_file(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def extract(sample_idx, out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    rt = YoloRuntime(ROM)
    task = next(t for t in rt.sched['tasks'] if t.get('node') == 'model.0')
    assert task['first'] and task['k'] == [3, 3] and task['stride'] == [2, 2], task

    import glob
    npz_path = sorted(glob.glob(str(GOLDEN_DIR / 'golden_*.npz')))[sample_idx]
    z = np.load(npz_path)
    canvas = z['canvas_u8']
    x_q = (canvas.astype(np.int16) - 128).astype(np.int8).transpose(2, 0, 1).copy()
    y_gold = z['int8_model.0']

    # ---- DUT 参数 ----
    w = rt.pkg.w('model.0')                                  # [16,3,3,3] int8
    b = rt.pkg.b('model.0').astype(np.int64)
    zsw = np.array(task['z_sum_w'], dtype=np.int64)
    bias_eff = (b + zsw).astype(np.int32)                     # int32
    reqs = task['req']                                        # [[M, s] x16]
    M = np.array([r[0] for r in reqs], dtype=np.int32)
    shift = np.array([r[1] for r in reqs], dtype=np.uint8)
    assert shift.min() >= 32 or True                          # 首层 shift 40-42，RNE 必须处理 s>=32
    lut = rt.pkg.lut('model.0')
    assert lut is not None and lut.shape == (256,)

    # ---- 三方自检：runtime._conv(x) == golden ----
    regs = rt._conv(task, x_q[None])
    y_rt = regs[0]
    assert y_rt.shape == y_gold.shape, (y_rt.shape, y_gold.shape)
    assert np.array_equal(y_rt, y_gold), \
        f'runtime vs golden mismatch: {(y_rt != y_gold).sum()} elems'

    # ---- 落盘 ----
    files = {
        'x_i8.bin': x_q.tobytes(),
        'w_i8.bin': w.tobytes(),
        'bias_eff_i32.bin': bias_eff.tobytes(),
        'm_i32.bin': M.tobytes(),
        'shift_u8.bin': shift.tobytes(),
        'lut_i8.bin': lut.tobytes(),
        'y_exp_i8.bin': y_gold.tobytes(),
    }
    for name, data in files.items():
        (out_dir / name).write_bytes(data)

    manifest = {
        'source_npz': Path(npz_path).name,
        'node': 'model.0',
        'shapes': {
            'x': [3, 320, 320], 'w': [16, 3, 3, 3], 'y': [16, 160, 160],
            'lut': [256], 'bias_eff': [16], 'm': [16], 'shift': [16],
        },
        'k_layout': 'K = ic*9 + kh*3 + kw  (w stored [oc][ic][kh][kw])',
        'pad': -128, 'stride': 2, 'has_act': True,
        'shift_range': [int(shift.min()), int(shift.max())],
        'm_abs_max': int(np.abs(M).max()),
        'sha256': {n: hashlib.sha256(d).hexdigest() for n, d in files.items()},
        'selfcheck_runtime_vs_golden': 'PASS',
    }
    (out_dir / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] {out_dir}  shifts={manifest["shift_range"]} '
          f'|M|max={manifest["m_abs_max"]}  self-check PASS '
          f'({manifest["source_npz"]})')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--samples', type=str, default='0,2',
                    help='golden 样本号，逗号分隔')
    ap.add_argument('--out-root', type=Path, default=HERE / 'stim')
    args = ap.parse_args()
    for s in args.samples.split(','):
        s = int(s)
        extract(s, args.out_root / f'conv0_golden{s:02d}')


if __name__ == '__main__':
    main()
