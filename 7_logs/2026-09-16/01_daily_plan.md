# 2026-09-16 日计划

## M12 A1 批（已授权"先跑a"；A = RTL + 仿真回归，无 Vivado）

1. M8 门 run03：ctrl V1.2（S_RQ 增 rq_rdy_i 等待态）回归，接高电平 ≡ V1.1。
2. M9b 门 run03：dma_wr V1.2 非对齐起始（Y 行 4B 对齐合同扩展）。
3. 阵列 V1.2/V1.2a：Y 真 AXI 写主（行段化器 + u_dma_wr + dsc_ybase +
   排空门控）+ M10 门重跑（TB 换 AXI 写从 BFM）。
4. M11 门 run03：全网 63 conv 回归（TB 同构改造 + headcheck 对 run04）。
5. yolo_csr.v + yolo_engine_top.v + CSR/engine 门（PROD/SIM 同 RTL）。

## 边界

- 任何门 FAIL 停下根因留证；数值合同冻结；B 段（OOC 综合）与板卡操作
  待 A 绿后另行确认/授权。
