# 2026-09-17 yolo7020 OOC gate v23 — B0 迭代 9（dma V1.3 + dma_wr V1.5 突发参数预计算）

## 结果

```
GEMM16_OOC_TIMING_FAIL wns_ns=-0.457 whs_ns=0.076 fmax_mhz=140.37 target_mhz=150.0
OOC_V23_RES dsp48e1=141 ramb36=20 ramb18=0
```

WNS 轨迹：v21 −0.713 → v22 −0.581 → **v23 −0.457**（fmax 135.5 → 137.97 → 140.37）。

## v23 批变更（迭代 9，位精确纯重定时，黄金全复用）

dma V1.3 / dma_wr V1.5：AW/AR 突发参数预计算拆沿——v22 top10 全体
words_r→addr_r −0.581 / words_r→words_r −0.496（发火沿串行
min(words,16) → min(bnd,·) → 32b 减 → 32b addr 加）改为：
`want2_r=min(words_r,16)` 与 addr_r 推进（+blen_r<<3）挪到上一突发
末拍装载/结算（words_r 自上次发火起稳定 ≥1 拍）；发火沿只剩 10 位
比较 + 一次 32 位减法，addr_r 发火沿纯寄存器搬运。

## top10 owner（v23 → 驱动迭代 10）

**全部 10 条** `u_requant/prod_c_w__2/CLK → q_r_reg[*]`（−0.457…−0.340）
——requant c3 拍 64 输出桶形 `prod >>> s`（DSP P 寄存 CLK→P + 6 级
mux + 64 负载路由）。dma_wr words_r 家族整体退出 top10（修复生效）。

→ 迭代 10 = requant V1.2e（窗口化 c3 解码：q8/qneg/ir，64 位桶形消失）。

门链：M9 v23（run04）+ M9b v23（run06）+ M12 csr v23（run05）+
M10 v23（run08，层完成时刻与 v21/v22 逐拍相同）+ 本跑。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/proj/ooc_gate && vivado -mode batch -source ooc_v23.tcl -nojournal
```

判决 token 打印至 ooc_v23.log；top10 见 ooc_v23_top10.rpt。
