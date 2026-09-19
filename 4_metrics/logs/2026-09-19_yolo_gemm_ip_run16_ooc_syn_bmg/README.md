# run16 — OOC 综合定档门（真 IP 全网表）· BMG IP 重做第六门（收官）

**日期**：2026-09-19 · **性质**：IP 硬指标重做链 run11–run16 第六门（用户序⑥）
**判定**：**资源判据全命中 ✅ / 100 MHz WNS 未达（−4.728 ns，Fmax≈67.9 MHz）→ 预挂用户决策点触发**

```
EES_SYNTH_RESULT BMG WNS=-4.728 WHS=0.219 period=10.000ns
EES_SYNTH_RESULT BMG BRAM36=12 BRAM18=1 (judge: 12 bank + 1 lut)
```
（证据：`syn_bmg_console.log`、`util_bmg.rpt`、`timing_bmg.rpt`）

## 结果明细

| 项 | 实测 | 判据 | 判定 |
|---|---|---|---|
| BRAM36E1 | 12（bank：W 2×2 + X 2×4） | ≈12 | ✅ 精确 |
| RAMB18E1 | 1（SiLU LUT） | 1 | ✅ 精确 |
| DSP48E1 | 68（阵列 64 + 尾乘 4） | 合理域 | ✅ |
| LUT / FF | 7174（13.5%）/ 5086（4.8%） | 无爆炸 | ✅ |
| WHS（保持） | +0.219 | ≥0 | ✅ |
| **WNS（100 MHz）** | **−4.728** | **≥0** | **❌ 决策点** |

- DUT：`yolo_gemm_core` V1.1，5 IP 全网表（synth_ip OOC DCP →
  synth_design 链接，非工程流）。Kc 纯逻辑（无综合参数，区别于
  run10b 的 KC576/KC1024 双跑）。
- 旧值对照：run10b（IP 化前）WNS=−6.383 → 现 −4.728（BMG 同步读
  把 RAM 读时间挪出组合路径，同路径净改善 1.66 ns，但仍不足）。

## 关键路径（timing_bmg.rpt 首路）

```
u_array/u_tail/sh2_r_reg[0] ──组合──> gemm_bm_lut ADDRARDADDR
38 级逻辑（CARRY4×32）：64 位 RNE（移位/掩码/比较/加）+ 饱和 + addr
Data Path 14.078 ns = 逻辑 8.093 + 布线 5.985
```
即：尾 stage3 的 64 位宽算术链直驱 BMG 地址口的 setup 路径——
尾 V2.0 把 LUTRAM 异步读改为 BMG 同步读后，该组合块成为显式寄存器
setup 约束（run13/run15 功能全绿，纯时序问题）。

## 决策点（用户定夺，预案如下，未获授权不执行）

- **A. 尾流水再加深**（stage3 算术寄存一级，D+4→D+5，阵列坐标镜像
  4→5）：RNE 链独占一拍。但该链逻辑+布线合计 ≈14 ns，**单加深一级
  预计仍不闭**（需 <10 ns），大概率要 A+算术收窄组合。
- **B. 64 位 RNE 算术收窄**（利用 acc 33b/M 32b 域做窄位移/比较，
  或商/余数两拍拆分）：能真正闭 100 MHz，但触碰冻结算术契约
  （§8 顺序），改动与重验代价最大。
- **C. 降频至 ≤67 MHz**（PS FCLK 重配或 MMCM）：零 RTL 改动，
  牺牲带宽（GEMM 峰值 ∝ 频率），系统级权衡。
- 注：A 若做，坐标镜像/合并 TB 延迟检查同步 +1（run14/15 模式重演）。

## 过程档案（如实）

1. 首跑 `GENERATE_SYNTH_CHECKPOINT false` 在非工程模式不可用
   （Common 17-54）→ 改非工程正典 `synth_ip` OOC DCP 流后通过。
2. 5 条 CRITICAL WARNING（filemgmt 20-1365）：read_ip 阶段内存工程
   默认 part 与 IP 定制 part 不符 → `generate_target` 被锁；既有
   xc7z020 综合产物照常使用，`synth_design -part xc7z020` 为准
   （BRAM 12+1/DSP 68 即证 IP 真入网表）。对结果无影响，留档。
3. 脚本 DSP/FF 逐点计数过滤（PRIMITIVE_GROUP）在本流返回 0
   （run10b 同样为 0，报告脚本缺陷非综合回归），真实数取
   `util_bmg.rpt`（DSP 68 / FF 5086）。

## 结论

- **重做链六门收官：功能五门全绿（逐数对齐 IP 化前）+ 综合门资源
  判据精确命中；时序门实测 Fmax≈67.9 MHz < 100 MHz 板上目标，
  按预案挂起待用户决策（A/B/C）。**
- 决策落定前不动尾 RTL（冻结纪律）；B1 上板路线（CSR 联合）不受
  本决策阻塞——可按用户节奏先行。
