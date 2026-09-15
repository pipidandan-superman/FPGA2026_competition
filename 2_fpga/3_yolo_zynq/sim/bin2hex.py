"""bin -> hex 转换：$readmemh 用（每行一个值，大写十六进制，补码已编码）。

用法：python bin2hex.py <in.bin> <out.hex> <width_bytes>
  width_bytes: 1=int8, 4=int32
"""
import sys
from pathlib import Path

import numpy as np


def main():
    src, dst, wb = sys.argv[1], sys.argv[2], int(sys.argv[3])
    dt = np.int8 if wb == 1 else np.int32
    a = np.frombuffer(Path(src).read_bytes(), dtype=dt)
    lines = [format(int(v) & ((1 << (8 * wb)) - 1), 'X').zfill(2 * wb) for v in a]
    Path(dst).write_text('\n'.join(lines) + '\n', encoding='ascii')
    print(f'[bin2hex] {src} -> {dst}  ({len(a)} words x {wb}B)')


if __name__ == '__main__':
    main()
