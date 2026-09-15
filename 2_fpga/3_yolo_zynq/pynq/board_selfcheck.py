"""板端自检：rom_data 包 + schedule 执行器在真实 PS（ARM）上跑回归帧。

零 cv2/零 torch/零数据集依赖——输入直接来自 PC 打包的 board_pack/inputs.npz
（letterbox 已完成），期望值来自 expected.json（源 = G2 真 RNE run04 回归记录）。

判分口径与 PS_RUNTIME_OFFLINE_PASS 一致：
  head：三尺度原始 INT8 头拼接字节 sha256 == run04 raw_head_sha256（硬门）
  box ：float64 解码（框 2dp / 置信 4dp / 类别）与回归记录精确相等
ARM/x86 libm 末位差异若存在，会表现为 head 全过而 box 个别不等——JSON 中
分开记录，head_only_pass 字段单独可查。

用法（板上）：
  python3 board_selfcheck.py                 # 前 8 帧子集
  python3 board_selfcheck.py --frames 0      # 全部 128 帧
目录约定：脚本所在目录 = 部署目录，内含 rom_data/ board_pack/ 与本套库文件。
只读运行，不装服务、不改系统文件；证据写 --outdir（默认 ./selfcheck_result）。
"""
import argparse
import hashlib
import json
import platform
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from yolo_runtime import YoloRuntime
from yolo_decode import decode_all


def read_text(p):
    return Path(p).read_text(encoding='utf-8').strip()


def env_info():
    e = {
        'python': sys.version.split()[0],
        'numpy': np.__version__,
        'platform': platform.platform(),
        'machine': platform.machine(),
        'hostname': platform.node(),
    }
    for key, p in [('uname', '/proc/version'), ('cpuinfo_model', '/proc/cpuinfo'),
                   ('meminfo', '/proc/meminfo'), ('boot_id', '/proc/sys/kernel/random/boot_id')]:
        try:
            t = read_text(p)
            if key == 'cpuinfo_model':
                t = next((l.split(':', 1)[1].strip()
                          for l in t.splitlines() if l.startswith('model name')), '')
            elif key == 'meminfo':
                t = next((l for l in t.splitlines() if l.startswith('MemTotal')), '')
            e[key] = t
        except Exception:
            e[key] = None
    return e


def sha256_file(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def default_dir(candidates):
    for c in candidates:
        if c.is_dir():
            return c
    return candidates[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rom-dir', type=Path,
                    default=default_dir([HERE / 'rom_data', HERE.parent / 'rom_data']))
    ap.add_argument('--pack-dir', type=Path, default=HERE / 'board_pack')
    ap.add_argument('--frames', type=int, default=8,
                    help='前 N 帧；0 = 全部')
    ap.add_argument('--outdir', type=Path, default=HERE / 'selfcheck_result')
    args = ap.parse_args()

    t_start = time.time()
    log_lines = []

    def log(m=''):
        print(m, flush=True)
        log_lines.append(str(m))

    # ---- 1. 传输完整性：npz/expected 与 pack manifest 哈希一致 ----
    pm = json.loads((args.pack_dir / 'pack_manifest.json').read_text(encoding='utf-8'))
    got_npz = sha256_file(args.pack_dir / 'inputs.npz')
    got_exp = sha256_file(args.pack_dir / 'expected.json')
    transfer_ok = (got_npz == pm['inputs_sha256'] and got_exp == pm['expected_sha256'])
    log(f'[1] transfer: inputs.npz {got_npz[:16]}... exp {got_exp[:16]}... match={transfer_ok}')
    assert transfer_ok, 'board_pack 哈希不符——传输损坏，禁止继续'

    # ---- 2. 部署包自检：manifest SHA-256 ----
    rt = YoloRuntime(args.rom_dir)
    hv = rt.pkg.verify_hashes()
    pkg_ok = all(hv.values())
    log(f'[2] rom_data package: {sum(hv.values())}/{len(hv)} sha256 match ({pkg_ok})')
    assert pkg_ok, f'rom_data 哈希不符: {hv}'

    # ---- 3. 回归帧 ----
    z = np.load(args.pack_dir / 'inputs.npz')
    canvases = z['canvas']
    expected = json.loads((args.pack_dir / 'expected.json').read_text(encoding='utf-8'))
    n = len(expected) if args.frames <= 0 else min(args.frames, len(expected))
    rows = []
    t_first = None
    for k in range(n):
        e = expected[k]
        t0 = time.time()
        regs, clss, rs, cs = rt.run(canvases[k])
        hh = hashlib.sha256()
        for r in regs + clss:
            hh.update(r.tobytes())
        head_ok = hh.hexdigest() == e['raw_head_sha256']
        bx, cf, ki = decode_all(regs, clss, rs, cs)
        box_ok = (np.round(bx, 2).tolist() == e['boxes']
                  and np.round(cf, 4).tolist() == e['conf']
                  and ki.tolist() == e['cls'])
        dt = time.time() - t0
        if t_first is None:
            t_first = dt
        rows.append({'i': k, 'image': e['image'], 'head': head_ok, 'box': box_ok,
                     'sec': round(dt, 2)})
        log(f'  [{k:3d}/{n}] {e["image"][:28]:28s} head={head_ok} box={box_ok} {dt:6.1f}s')

    n_head = sum(r['head'] for r in rows)
    n_box = sum(r['box'] for r in rows)
    head_only_pass = (n_head == n)
    overall_pass = (n_head == n and n_box == n)

    # ---- 4. 证据落盘 ----
    args.outdir.mkdir(parents=True, exist_ok=True)
    ts = time.strftime('%Y%m%d_%H%M%S')
    verdict = ('PS_SELFCHECK_ONBOARD_PASS' if overall_pass else
               'PS_SELFCHECK_ONBOARD_HEAD_ONLY' if head_only_pass else
               'PS_SELFCHECK_ONBOARD_FAIL')
    result = {
        'verdict': verdict,
        'frames_planned': n,
        'frames_head_ok': n_head,
        'frames_box_ok': n_box,
        'head_only_pass': head_only_pass,
        'first_frame_sec': round(t_first or 0, 2),
        'mean_frame_sec': round(sum(r['sec'] for r in rows) / max(n, 1), 2),
        'rom_files_sha256': hv,
        'pack_sha256': {'inputs.npz': got_npz, 'expected.json': got_exp},
        'env': env_info(),
        'rows': rows,
        'wall_sec': round(time.time() - t_start, 1),
    }
    (args.outdir / f'result_{ts}.json').write_text(
        json.dumps(result, indent=1), encoding='utf-8')
    (args.outdir / f'console_{ts}.log').write_text('\n'.join(log_lines) + '\n',
                                                   encoding='utf-8')
    log(f'[3] regression: head {n_head}/{n}, box {n_box}/{n}, '
        f'first {result["first_frame_sec"]}s mean {result["mean_frame_sec"]}s')
    log(f'[RESULT] {verdict} frames={n} head={n_head}/{n} box={n_box}/{n} '
        f'wall={result["wall_sec"]}s')
    log(f'[evidence] {args.outdir / ("result_" + ts + ".json")}')
    return 0 if overall_pass else 1


if __name__ == '__main__':
    sys.exit(main())
