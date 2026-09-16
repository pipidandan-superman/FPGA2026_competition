"""M9b dma_wr 激励生成器 + 黄金（AXI 写 BFM 数据权威）。

合同（rtl/yolo_dma_wr.v V1.2）：线性块写 AXI4 写主（64b INCR，单 id），
命令（任意字节对齐地址，≥1 字节）→ 突发链：每 AW 拍数 =
min(剩余覆盖字数, MAX_BURST=16, 距 4KB 边界拍数)——突发不跨 4KB 行；
awaddr = 命令地址下对齐 8B（AXI awsize 对齐要求），装配从 head=
addr[2:0] 起（源字节 k -> 首 word lane head+k），首字 wstrb 掩 head
lanes，尾字 wstrb 低位有效；单在途 AW（上一突发 WLAST 后才发下一
AW）；每突发一个 B；done = 末字发出且发一收一的 B 计数对齐。
覆盖字数 = ceil((head+len)/8)。head=0 时与 V1.1 行为逐位一致。

数据权威（DDR 侧）：地址 a 处的字节 == F(word(a))>>8*(a%8)
（64b murmur 式 finalize，Verilog/Python 逐位一致）——基地址错、
lane 交换、字节序错、head 掩错、丢失/重复/错位全部表现为值错/
双写位/缺写位。命令间地址允许重叠（wr_bit 为命令相对索引、逐命令
清零，重叠不产生假失败；值按地址键哈希，与写入命令无关）。

命令计划（seed 912，V2 非对齐扩展，≥40 条）：
A 组 8 对齐大长度（8/24/64/128/136/264/2048/4096/12288/65536/
123456，贴 4KB 残差）——head=0 回归基线；B 组 head=0..7 全覆盖
小命令；C 组大长度非对齐（123456@head5 跨多 4KB、65536@head3、
12288@head7 贴行尾、136@head1）；D 组随机小命令（任意残差 1..64B）。
总字节 ~21 万。

黄金：每命令 DDR 侧字节计数 + 64b 加法校验和（mod 2^64）。
结构断言：≥1 命令跨 4KB（链切分）、len==8、len==128（单满突发）、
len==136（突发+1）、总字节 ≥10 万、head 0..7 全部出现、非对齐
命令 ≥10、存在 >64 突发的多突发命令（B 排空逻辑压力）。
"""
import hashlib
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SEED = 912
M64 = (1 << 64) - 1
MAX_BURST = 16
K1 = 0x9E3779B97F4A7C15
K2 = 0xBF58476D1CE4E5B9


def f_word(wa):
    """BFM 数据：word 地址哈希（与 TB Verilog 逐位一致）。"""
    x = (wa * K1) & M64
    x ^= x >> 31
    x = (x * K2) & M64
    x ^= x >> 27
    return x


def burst_chain(addr, nbytes):
    """结构预测：RTL 同式突发切分（V1.2：awaddr 下对齐，覆盖字数 =
    ceil((head+n)/8)，拍数=min(字数,16,距 4KB 拍数)）。"""
    head = addr & 7
    words = (head + nbytes + 7) >> 3
    a = addr & ~7
    chain = []
    while words > 0:
        bnd = (4096 - (a & 0xFFF)) >> 3
        want = min(words, MAX_BURST)
        b = min(bnd, want)
        chain.append((a, b))
        a += b * 8
        words -= b
    return chain


def main():
    rng = np.random.default_rng(SEED)
    base = 0x1000_0000
    cmds = []
    # A 组（回归基线，8 对齐）大长度贴边界残差
    plan = [8, 24, 64, 128, 136, 264, 2048, 4096, 12288, 65536, 123456]
    for L, res in zip(plan, [4088, 0, 64, 4080, 8, 2048 - 64, 4096 - 128,
                             4096 - 8, 4096 - 64, 4096 - 1024, 4096 - 512]):
        cmds.append(dict(addr=base + res + 0x1_0000 * len(cmds), n=L))
    # B 组：head=0..7 全覆盖（len 1..9 逼首字掩码与尾字交互）
    for h in range(8):
        cmds.append(dict(addr=base + 0x8_0000 + 0x100 * h + h,
                         n=1 + h))
    # C 组：大长度非对齐（跨多 4KB + head 掩码与突发切分交互）
    for L, res, h in [(123456, 4096 - 512, 5), (65536, 4096 - 1024, 3),
                      (12288, 4096 - 8, 7), (136, 4096 - 64, 1)]:
        cmds.append(dict(addr=base + 0x10_0000 + res + h, n=L))
    # D 组：随机小命令补足（任意残差、任意字节长度 1..64）
    for _ in range(22):
        res = int(rng.integers(0, 4096))
        n = int(rng.integers(1, 65))
        cmds.append(dict(addr=base + 0x20_0000 + res, n=n))

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
            a = c['addr'] + i
            s += (f_word(a & ~7) >> (8 * (a & 7))) & 0xFF
        gold.append(dict(count=c['n'], sum64=s & M64,
                         bursts=len(chain)))

    # ---- 断言 ----
    lens = [c['n'] for c in cmds]
    heads = sorted({c['addr'] & 7 for c in cmds})
    total = sum(lens)
    assert len(cmds) >= 40, len(cmds)
    assert total >= 100000, total
    assert 8 in lens and 128 in lens and 136 in lens
    assert heads == list(range(8)), heads      # head 全覆盖
    assert sum(1 for c in cmds if c['addr'] & 7) >= 10
    assert any(((c['addr'] & 0xFFF) + c['n']) > 0x1000 for c in cmds)
    assert any(len(burst_chain(c['addr'], c['n'])) > 1 for c in cmds)
    assert max(g['bursts'] for g in gold) > 64, 'need a multi-burst command'

    out = HERE / 'stim' / 'dma_wr'
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
           'unaligned_commands': sum(1 for c in cmds if c['addr'] & 7),
           'head_values': heads,
           'max_bursts_one_cmd': max(g['bursts'] for g in gold),
           'len_min': min(lens), 'len_max': max(lens)}
    manifest = {
        'name': 'dma_wr', 'seed': SEED,
        'contract': 'linear block write, any byte alignment (V1.2 head '
                    'offset): awaddr = addr&~7, assembler starts at lane '
                    'head, first-word wstrb masks head lanes; bursts '
                    'min(ceil((head+len)/8),16,4KB-boundary); little-endian '
                    'assembly (source byte k -> lane head+k); one '
                    'outstanding AW; one B per burst; done after B-count '
                    'aligns',
        'gold_ref': 'DDR-side: every strobed byte at address a == '
                    'F(word(a))>>8*(a%8); per-command count + additive '
                    'checksum mod 2^64 + written-once bijection walk '
                    '(command-relative bitmap, overlap-safe)',
        'f_word': 'x=wa*K1; x^=x>>31; x*=K2; x^=x>>27 (mod 2^64); '
                  'K1=9E3779B97F4A7C15 K2=BF58476D1CE4E5B9',
        'coverage': cov,
        'sha256': {fn: hashlib.sha256(t.encode('ascii')).hexdigest()
                   for fn, t in files.items()},
    }
    (out / 'stim_manifest.json').write_text(
        json.dumps(manifest, indent=1), encoding='utf-8')
    print(f'[stim] dma_wr: {cov["commands"]} cmds '
          f'(bytes={cov["total_bytes"]} cross4k={cov["cross4k_commands"]} '
          f'unaligned={cov["unaligned_commands"]} heads={heads} '
          f'max_bursts={cov["max_bursts_one_cmd"]}), manifest written')


if __name__ == '__main__':
    main()
