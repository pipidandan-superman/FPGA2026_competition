#!/usr/bin/env python3
"""M11 gate post-run checker: head dump vs run04 golden.

Verifies the TB's head_dump.bin (regs[0..2] + clss[0..2], int8, in order)
two ways:
  1. sha256(dump) == regression_128frames.json frame0 raw_head_sha256
     (the M11 gate criterion, baseline section 5 as amended)
  2. byte-exact split into the 6 run04 npz int8 head tensors
     (stronger localization than the hash alone)

Usage:  python m11_headcheck.py [dump_path]   (default head_dump.bin)
Exit 0 + one PASS line on success; nonzero + diagnosis on failure.
"""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
RD = HERE.parent / 'rom_data'
RUN04 = Path(r'E:\competition\4_metrics\logs'
             r'\2026-09-15_yolo7020_g2_quant_rne_run04')
GOLD_NPZ = RUN04 / 'golden' / 'golden_00_images89_jpg.npz'
REG128 = RUN04 / 'regression_128frames.json'

# dump order = regs[0..2] + clss[0..2]; producer node names from schedule
REG_NODES = ['model.22.cv2.0.2', 'model.22.cv2.1.2', 'model.22.cv2.2.2']
CLS_NODES = ['model.22.cv3.0.2', 'model.22.cv3.1.2', 'model.22.cv3.2.2']


def main():
    dump_path = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / 'msim' / 'head_dump.bin'
    data = dump_path.read_bytes()

    reg128 = json.loads(REG128.read_text(encoding='utf-8'))
    # frame 0 record (images89); key layout per run_g2_quant.py
    frames = reg128 if isinstance(reg128, list) else reg128.get('frames')
    f0 = frames[0]
    ref_sha = f0['raw_head_sha256']
    got_sha = hashlib.sha256(data).hexdigest()
    ok_sha = got_sha == ref_sha
    print(f'[m11chk] dump={dump_path.name} bytes={len(data)} '
          f'sha={got_sha[:16]}... ref={ref_sha[:16]}... '
          f'{"MATCH" if ok_sha else "MISMATCH"}')

    npz = np.load(GOLD_NPZ)
    parts, off, ok_split = [], 0, True
    for node in REG_NODES + CLS_NODES:
        t = npz[f'int8_{node}']
        d = data[off:off + t.size]
        if len(d) != t.size or d != t.tobytes():
            bad = (i for i in range(min(len(d), t.size))
                   if d[i] != t.tobytes()[i])
            i = next(bad, -1)
            print(f'[m11chk] tensor {node}: MISMATCH at flat {i} '
                  f'got={d[i] if i >= 0 else "?"} exp={t.ravel()[i]}')
            ok_split = False
        parts.append(f'{node}:{t.size}')
        off += t.size
    print(f'[m11chk] split {off}/{len(data)} bytes vs npz -> '
          + ', '.join(parts))

    if ok_sha and ok_split and off == len(data):
        print(f'M11_HEADCHK_PASS sha256={got_sha} bytes={len(data)}')
        return 0
    print(f'M11_HEADCHK_FAIL sha_ok={ok_sha} split_ok={ok_split} '
          f'consumed={off} len={len(data)}')
    return 1


if __name__ == '__main__':
    sys.exit(main())
