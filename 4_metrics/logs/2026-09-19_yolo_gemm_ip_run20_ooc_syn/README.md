# run20 — OOC 综合时序判决门 · WNS A+B 收敛（tail V2.2）

**日期**：2026-09-19 · **性质**：run16 WNS=−4.728 决策 **A+B**（用户授权）综合判决门
**判定**：**PASS——100 MHz WNS=+1.392 ≥ 0 ✅（两迭代收敛，资源判据保持精确命中）**

```
EES_SYNTH_RESULT BMG WNS=1.392 WHS=0.219 period=10.000ns
EES_SYNTH_RESULT BMG BRAM36=12 BRAM18=1 (judge: 12 bank + 1 lut)
（Design Timing Summary：TNS=0 / THS=0，12546 端点全过；Fmax≈116 MHz）
```
（证据：`syn_v22_console.log`、`timing_bmg.rpt`、`util_bmg.rpt`；第一迭代
V2.1 存档 `syn_v21_console.log`：WNS=−2.669）

## 迭代轨迹（同一判决门内，判据始终 100 MHz WNS≥0 绝对值）

| 版本 | stage3 结构 | WNS | 关键路径 |
|---|---|---|---|
| V2.0（run16） | 掩码/余数/比较/条件加 64 位串行 | −4.728 | prod_r→BMG addr 14.08ns，38 级 CARRY4×32 |
| V2.1（迭代一） | magic-add 恒等式（65 位加+桶形移位同拍） | −2.669 | prod_r→qn_r 12.66ns，29 级 CARRY4×20 |
| **V2.2（迭代二）** | **并行逐位判决（OR 树，无宽进位链）** | **+1.392** | sh2_r→ru_r 8.60ns，20 级 |

## V2.2 收敛机理（手册 §8 语义零变化）

- 舍入判决改纯逐位式：`ru = prod[s−1] & (rem低位非零 | prod[s])`，
  与定义式（rem>half ∨ tie∧q奇）逐位等价（含正/负/tie 手算例复验 +
  run17b golden 双向交叉 + 711 随机全对）。
- `+ru` 不做 64 位加：stage4 以 **10 位窄加吸收**（255+1=256→127、
  −256+1=−255→−128 边界推挤仍正确饱和，推演在 RTL 头注）。
- 商 `qsh=prod>>>s` 与判决并行；SE 判验（符号扩展检查）+ 饱和 + 地址
  全窄逻辑。**D+5 不变**，阵列镜像五级、TB 延迟检查全部不动。
- 判决路径上综合器把 OR 归约映射为 CARRY4×14（快速进位 OR 模式），
  8.60ns = 逻辑 3.993 + 布线 4.608，余量 1.392ns。

## 资源（与 run16 完全一致，IP 全网表不变）

BRAM36E1=12（W 2×2 + X 2×4）+ RAMB18E1=1（LUT）；DSP48E1 逐点计数
脚本过滤在本流返回 0（run10b/run16 同样，报告脚本缺陷），真实数见
`util_bmg.rpt`。read_ip 阶段 part-lock 5 条 CRITICAL WARNING 与 run16
同源无害。

## 结论

**A+B 决策闭环：100 MHz WNS≥0 达成（+1.392），G2 时序门收官。**
功能侧 run17b/18b/19b 与 IP 化前逐数对齐；尾 D+5、阵列 V2.2、core V1.1
即 B1 上板例化基线。
