# run18 — 阵列三档门重演 · WNS A+B（array V2.2 镜像五级）

**日期**：2026-09-19 · **性质**：run16 WNS 决策 A+B 第二门
**判定**：**PASS ×3 ×2 迭代（V2.1 尾与 V2.2 尾各一跑，逐数相同）✅**

```
迭代二（tail V2.2，arr_v22b_console.log）：
EES_SUMMARY checks=846  errors=0 proto_err=0   (4x4  tiles 62/60/2)
EES_SUMMARY checks=4250 errors=0 proto_err=0   (8x16 tiles 37/35/2)
EES_SUMMARY checks=6881 errors=0 proto_err=0   (16x16 tiles 30/28/2)
EES_VIVADO_RESULT PASS ×3
（迭代一 V2.1 尾：同数，arr_v22_console.log）
```

## DUT 变更（array V2.1 → V2.2，唯一改动）

- 坐标镜像 yr/yn 四级 → **五级**（`y_row_o/y_col_o` 改自 yr5/yn5 呈现），
  与尾 V2.1 D+5 的 y_valid 同相。TB 逐拍严格坐标检查（`y_row/y_col !==
  eq_r/eq_n` 记错）零失配即证同相。

## 流程

- TB：`tb/tb_yolo_gemm_array_bmg.sv`（run14 件逐字未动，G1-G9 刺激/
  golden/判据原样）；三档 4×4/8×16/16×16 同 TB 例化。
- tcl：`sim_gemm_array_v22.tcl`（pe_pack + LUT wrapper + 5 件 -sv +
  glbl，xelab ×3）。

## 结论

镜像五级在全档全矩阵下与 D+5 尾严格对齐；下一门 run19（core V1.1
单体含 tail V2.1 + array V2.2，G1-G9 完整调度）→ run20（OOC 综合）。
