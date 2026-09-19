# run19 — 合并核心门重演 · WNS A+B（core V1.1 内 tail V2.1/V2.2 + array V2.2）

**日期**：2026-09-19 · **性质**：run16 WNS 决策 A+B 第三门
**判定**：**PASS ×2 迭代（两版尾逐数相同）✅**

```
迭代二（tail V2.2，core_v22_console.log）：
EES_SUMMARY checks=4250 errors=0 proto_err=0
EES_ARR_INFO config=8x16 tiles started=37 done=35 aborted=2 y=4250
EES_ARR_INFO blocks_fed=47 blk_done=12 ld_done=49 (Kc logical)
EES_VIVADO_RESULT PASS
（迭代一 V2.1 尾：同数，core_v21_console.log）
```

## DUT / 流程

- core V1.1（单体封装不动）：bank V2.0.1 + feeder（未动）+
  array **V2.2**（镜像五级）+ tail **V2.1**（magic-add RNE、D+5）。
- TB：`tb/tb_yolo_gemm_core_bmg.sv`（run15 件逐字未动，G1-G9 完整
  调度矩阵）；tcl `sim_gemm_core_v21.tcl`（5 IP wrapper + 9 件 -sv +
  glbl，单 xelab tb_gemm_core_8x16_bmg）。

## 结论

A+B 改动在全 IP 数据通路 + 完整调度下零语义漂移；下一门 run20
（OOC 综合判决：100 MHz WNS ≥ 0）。
