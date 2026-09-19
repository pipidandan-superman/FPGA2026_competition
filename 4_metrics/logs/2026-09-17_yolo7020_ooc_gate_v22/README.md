# 2026-09-17 yolo7020 OOC gate v22 — B0 迭代 8（requant V1.2d + dma V1.2 + dma_wr V1.4）

## 结果

```
GEMM16_OOC_TIMING_FAIL wns_ns=-0.581 whs_ns=0.096 fmax_mhz=137.97 target_mhz=150.0
OOC_V22_RES dsp48e1=141 ramb36=20 ramb18=0
```

WNS 轨迹：v20 −1.187 → v21 −0.713 → **v22 −0.581**（fmax 135.5 → 137.97）。

## v22 批变更（迭代 8，全部位精确纯重定时，黄金全复用）

- requant V1.2d：① c3 owner（−0.713）sticky 改掩码 AND+OR 树（c2 沿
  预寄存 mask_r，仅依赖 s_r1，与 DSP 乘法并联）；② c4 档（−0.563）
  64 位加+比较饱和改范围归约（q[63:7] 全 0/全 1 ⟺ 在域）+ 9 位加。
- dma V1.2 / dma_wr V1.4：bnd 结算沿从 AR/AW 发火挪到突发末拍（发火装
  blen_r 5 位；v21 dma_wr owner words_r→bnd_r −0.634）。

## top10 owner（v22 → 驱动迭代 9）

**全部 10 条为同一家族** `u_dma_wr/words_r[23] → addr_r[*]/words_r[*]`
（−0.581 … −0.372）——AW 发火沿串行本体：
`min(words_r,16)` 24 位比较 → `min(bnd_r,·)` → 32 位减法回装 words_r，
加法侧再串 32 位 addr_r 进位链。迭代 7/8 的 requant 与 bnd owner 全部
退出 top10（修复生效）。

→ 迭代 9 = dma V1.3 / dma_wr V1.5（突发参数预计算拆沿：want2_r 与
addr_r 推进挪到上一突发末拍；发火沿只剩 10 位比较 + 一次 32 位减法）。

门链：M5 v22（run02，含 run02a ovf 判据 bug 拦截记录）+ M9 v22（run03）
+ M9b v22（run05）+ M12 csr v22（run04）+ M10 v22（run07）+ 本跑。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/proj/ooc_gate && vivado -mode batch -source ooc_v22.tcl -nojournal
```

判决 token 打印至 ooc_v22.log；top10 见 ooc_v22_top10.rpt。
