"""M9 dma 激励生成器 + 黄金（AXI BFM 数据权威）。

合同（rtl/yolo_dma.v）：线性块取数 AXI4 读主（64b INCR，单 id），
命令（8 对齐地址，≥1 字节）→ 突发链：每 AR 拍数 =
min(剩余字数, MAX_BURST=16, 距 4KB 边界拍数)——突发不跨 4KB 行；
字节流小端序逐字节交付 sink（1B/拍，带背压）；done 脉冲。

数据权威（BFM）：读数据 = 地址哈希 F(word_addr)（64b murmur 式
finalize，Verilog/Python 逐位一致），字节 i = F>>8i——任意地址
错误/字节乱序/丢失/重复都表现为校验和错。

命令计划（seed 909，≥30 条）：长度 8/24/64/128/136/264/2048/
4096/12288/65536/123456 + 随机对齐偏移小命令；地址故意贴 4KB
边界（残差 4088/4096-64 等）逼出突发切分。总字节 ~21 万。

黄金：每命令字节计数 + 64b 加法校验和（mod 2^64）。结构断言：
≥1 命令跨 4KB（链切分）、len==8、len==128（单满突发）、
len==136（突发+1）、总字节 ≥10 万、全部 8 对齐。
"""
import hashlib
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SEED = 909
M64 = (1 << 64) - 1
MAX_BURST = 16
K1 = 0x9E3779B97F4A7C15
K2 = 0xBF58476D1CE4E5B9


def f_word(wa):
    """BFM 读数据：word 地址哈希（与 TB Verilog 逐位一致）。"""
    x = (wa * K1) & M64
    x ^= x >> 31
    x = (x * K2) & M64
    x ^= x >> 27
    return x


def burst_chain(addr, nbytes):
    """结构预测：RTL 同式突发切分（拍数=min(字数,16,距4KB拍数)）。"""
    words = (nbytes + 7) >> 3
    chain = []
    while words > 0:
        bnd = (4096 - (addr & 0xFFF)) >> 3
        want = min(words, MAX_BURST)
        b = min(bnd, want)
        chain.append((addr, b))
        addr += b * 8
        words -= b
    return chain


def main():
    rng = np.random.default_rng(SEED)
    base = 0x1000_0000
    plan = [8, 24, 64, 128, 136, 264, 2048, 4096, 12288, 65536, 123456]
    cmds = []
    # 大长度贴边界残差：4088（切 1 拍后跨界）、0（整行）、64（行尾）
    for L, res in zip(plan, [4088, 0, 64, 4080, 8, 2048 - 64, 4096 - 128,
                             4096 - 8, 4096 - 64, 4096 - 1024, 4096 - 512]):
        cmds.append(dict(addr=base + res + 0x1_0000 * len(cmds), n=L))
    # 随机小命令补足 ≥30
    for _ in range(22):
        res = 8 * int(rng.integers(0, 512))       # 8 对齐随机残差
        n = 8 * int(rng.integers(1, 33))          # 1..32 字
        cmds.append(dict(addr=base + 0x2_0000 + res, n=n))

    gold = []
    cross4k = 0
    for c in cmds:
        chain = burst_chain(c['addr'], c['n'])
        if any((a & 0xFFF) + b * 8 > 4096 for a, b in chain[1:]):
            cross4k += 1
        if ((c['addr'] & 0xFFF) + c['n'] > 0x1000
                and len(chain) > 1):
            cross4k += 1
        s = 0
        for i in range(c['n']):
            wa = c['addr'] + 8 * (i >> 3)
            s += (f_word(wa) >> (8 * (i & 7))) & 0xFF
        gold.append(dict(count=c['n'], sum64=s & M64,
                         bursts=len(chain)))

    # ---- 断言 ----
    lens = [c['n'] for c in cmds]
    total = sum(lens)
    assert len(cmds) >= 30, len(cmds)
    assert total >= 100000, total
    assert 8 in lens and 128 in lens and 136 in lens
    assert all(c['addr'] % 8 == 0 for c in cmds)
    assert any(((c['addr'] & 0xFFF) + c['n']) > 0x1000 for c in cmds)
    assert any(len(burst_chain(c['addr'], c['n'])) > 1 for c in cmds)
    assert max(g['bursts'] for g in gold) > 64, 'need a multi-burst command'

    out = HERE / 'stim' / 'dma'
    out.mkdir(parents=True, exist_ok=True)
    files = {
        'n_cmds.hex': f'{len(cmds):08X}\n',
        'cmd_addr.hex': ''.join(f'{c["addr"]:08X}\n' for c in cmds),
        'cmd_len.hex': ''.join(f'{c["n"]:08X}\n' for c in cmds),
        'g_count.hex': ''.join(f'{g["count"]:08X}\n' for g in gold),
        'g_sum64.hex': ''.join(f'{g["sum64"]:016X}\n' for g in gold),
    }
    for fn, text in files.items():
        (out / fn).write_text(text, encoding='ascii')

    cov = {'commands': len(cmds), 'total_bytes': total,
           'cross4k_commands': cross4k,
           'max_bursts_one_cmd': max(g['bursts'] for g in gold),
           'len_min': min(lens), 'len_max': max(lens)}
    manifest = {
        'name': 'dma', 'seed': SEED,
        'contract': 'linear block fetch; bursts min(words,16,4KB-boundary);'
                    ' little-endian byte stream; backpressured sink',
        'gold_ref': 'AXI BFM data function F(word_addr) murmur-finalize '
                    '(Verilog TB bit-identical); per-command count + '
                    'additive checksum mod 2^64',
        'f_word': 'x=wa*K1; x^=x>>31; x*=K2; x^=x>>27 (mod 2^64); '
                  'K1=9E3779B97F4A7C15 K2=BF58476D1CE4E5B9',
        'coverage': cov,
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] dma: {cov["commands"]} cmds '
          f'(bytes={cov["total_bytes"]} cross4k={cov["cross4k_commands"]} '
          f'max_bursts={cov["max_bursts_one_cmd"]}), manifest written')


if __name__ == '__main__':
    main()
