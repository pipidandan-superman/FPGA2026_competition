# 2026-09-17 yolo7020 OOC gate v26 — B0 迭代 12（requant V1.2g）

## 结果

**GEMM16_OOC_TIMING_FAIL wns_ns=-0.031 whs_ns=0.075 fmax=149.30 MHz**
（target 150 MHz，create_clock 6.667ns）。资源与历轮持平：
dsp48e1=141 ramb36=20 ramb18=0。

v25 的唯一 owner 家族（requant sum_r_reg→prod DSP PCIN −0.079）已被
V1.2g 操作数重寄存（DSP AREG/BREG 吸收）完全消除。新唯一 owner：
**gemm_array V1.5 行地址融合乘加** oc_g_d1_r_reg[13]/C →
row_addr_d2_r0/PCIN −0.031 —— top10 全部同一族（ooc_v26_top10.rpt）。

病理与 requant v25 完全同构（ooc_v26_rowaddr_path.rpt，-from
oc_g_d1_r_reg -to row_addr_d2_r0/PCIN -input_pins 2 条详径）：
- 16x16 乘+加融合式映射 2-DSP 级联，首 DSP（row_addr_d2_r2）被组合
  穿越：A[13]→multiplier→adder→PCOUT 内部弧 4.036ns；
- 外侧 FDCE C→Q 0.518 + 布线 0.658，末 DSP PCIN setup −1.400；
- 数据径 5.214ns（逻辑 87.3%），required 6.156 / arrival 6.187。

## 修复（迭代 13 / gemm_array V1.10，本档之后执行）

拆分融合式：16x16 乘法自带寄存积 row_prod_d2_r（单 DSP PREG，弧内
无级联）；ybase+n_base 布线并行加 row_sum_d2_r；d3 沿合并
row_addr_d3_r。cfg 项 d1 快照（d1 后不读 cfg，V1.5 NBA 论证由构造
退役）。mod-2^32 结合律逐位等价，d9 呈现拍不变。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/proj/ooc_gate && \
  /f/vivado2025/2025.2/Vivado/bin/vivado.bat -mode batch \
  -source ooc_v26.tcl -nojournal -nolog        # → ooc_v26_drv.log
# 路径细查（routed dcp 已留 proj/ooc_gate/ooc_v26_routed.dcp）:
#   vivado -mode batch -source probe_v26_rowaddr.tcl
```

门链位置：B0 迭代 12 —— M5 run04 + M10 run11 + M12 csr run08 →
**OOC v26 FAIL −0.031** → 迭代 13。

WNS 轨迹：v13 −31.017 → v14 −6.507 → v15 −1.982 → v16 −1.732 →
v17 −1.463 → v19 −4.853 → v20 −1.187 → v21 −0.713 → v22 −0.581 →
v23 −0.457 → v24 −0.224 → v25 −0.079 → **v26 −0.031**。
