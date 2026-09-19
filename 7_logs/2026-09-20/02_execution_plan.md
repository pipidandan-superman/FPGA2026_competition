# 2026-09-20 执行计划

## 顺序（用户边界指令逐字）

run26 收口 → run27 G4 → run28 BD/比特流/静态检索 → 停。

## run26 收口步骤（已完成 ✅）

1. canonical packer `pynq/b3_conv0_packer.py`：数据源权威链
   （quant.json 偏移 / schedule.json req+z_sum_w / G2 golden canvas /
   replay 数学逐行）→ mirror 0x25F000 + golden_y + meta + selfcheck +
   block0.hex → 证据目录；
2. 静态 CSR/地址检查 `csr_static_check.md`：§9 表 ↔ top.v V1.2 写/读译码
   逐项 + 复位三分规则 + §5 常量与 packer 互证；
3. 证据 README/STATUS + 本日志四件套 + git。

## run27 G4 步骤

- TB `tb_yolo_gemm_b3_g4.sv`：$readmemh 本目录 mirror 切片 + golden_y +
  meta PCTL；单块 b=0/1/3198/3199 + 全量 3200 块 golden 逐字节（含 y slot
  公式 §7.2 reorder 校验）+ accepted beats 259,200 对账；随机
  s_axis_ld_tready / m_axis_y_tready（FIFO 满边界+恢复）；4KiB crossing；
  双跑 SHA 一致；负向：row_valid/n_mask 非全有效拒绝（BTT/对齐=driver 侧）。
- 证据目录 `4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/`。

## run28 步骤

- 批处理前查 Vivado GUI 进程（开着=决策点按边界 3 暂停）；
- BD 删 MM2S→S2MM 回环，接 MM2S→bridge s_axis_ld_*/m_axis_y_*→S2MM；
  例化从 .veo 逐端口核对；重生成 XCI/BD/bit/HWH；静态检索端口连接；
  WNS/WHS@100MHz、资源口径（DSP/LUT/FF/BRAM36/RAMB18）。

## 风险与回退

- G4 随机反压暴露 R5 边界：若失败，存证不覆盖、写暂停日志、停下等用户；
- BD 改动破坏既有基线：只在新 run 目录操作，不动 run21-25 工程快照。
