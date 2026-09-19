# 2026-09-17 yolo7020 OOC gate v21 — B0 迭代 7（dma V1.1 + dma_wr V1.3 + csr V1.1，Explore/AggressiveExplore）

## 结果

```
GEMM16_OOC_TIMING_FAIL wns_ns=-0.713 whs_ns=0.053 fmax_mhz=135.48 target_mhz=150.0
OOC_V21_RES dsp48e1=141 ramb36=20 ramb18=0
```

WNS 轨迹：v19 −4.853 → v20 −1.187 → **v21 −0.713**（fmax 127.3 → 135.5）。

## v21 批变更（迭代 7）

- dma V1.1 / dma_wr V1.3：4KB 边界拍数改增量 bnd_r（删每拍 12 位
  减法+比较重算，v20 owner addr_r 级联）。
- csr V1.1：LUT 写口寄存（配置期 1 拍延迟，数值不变）。
- P&R 升档：place Explore + phys_opt AggressiveExplore + route
  AggressiveExplore（v20 起保持）。

## top10 owner（v21 → 驱动迭代 8）

1. requant c3 `prod_c_w→sticky_r` **−0.713**（64b 桶形串 64b OR 树）
2. dma_wr `words_r[22]→bnd_r` **−0.634**（V1.3 AW 发火沿 words_r→beats_w
   最小值级联）
3. requant c4 `sticky_r→y_pre_o` **−0.563**（64b 加+双向比较饱和）

→ 迭代 8 = requant V1.2d（掩码 sticky + 范围归约饱和）+ dma V1.2 /
dma_wr V1.4（bnd 末拍结算）。门链：M9 v21 + M9b v21 + M12 csr v21
（run03，首个 engine_top 级 xsim 门）+ M10 v21（run06）。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/proj/ooc_gate && vivado -mode batch -source ooc_v21.tcl -nojournal
```

判决 token 打印至 ooc_v21.log；top10 见 ooc_v21_top10.rpt。
