# M9 dma 门 run04 — dma V1.3 突发参数预计算拆沿（2026-09-17, B0 迭代 9）

## 结果：TB_DMA_PASS（与 run01/02/03 逐计数一致）

```
TB_DMA_PASS bytes=210904 cmds=33 ars=1666 (stall-tolerant, 4KB-split, checksummed)
```

## RTL 变更（rtl/yolo_dma.v V1.2 → V1.3）

v22 ooc dma_wr 同源 owner（words_r→addr_r −0.581 / words_r→words_r
−0.496）读侧同构预防性修复：**AR 突发参数预计算拆沿**——
`want2_r = min(words_r,16)` 与 addr_r 推进（`+blen_r<<3`）均改在上一
突发末拍（`r_fire && beats_r==1 && 非命令末字`）装载/结算；words_r 自
上次 AR 发火起稳定 ≥1 拍、addr_r/blen_r 全突发稳定，末拍只剩单 24 位
比较与单 32 位进位链。**AR 发火沿只剩 min(bnd_r, want2_r) 10 位比较 +
一次 32 位减法**，addr_r 发火沿纯寄存器搬运（araddr_o 仅在 S_AR 被采样，
提前推进不可见）。命令接受沿 want2_r 由 cmd 总线直算（OOC 输入端口
无输入延迟约束，B1 整合时按真实 input delay 复核）。

突发序列/AR 地址/周期行为逐拍不变——本 run 逐计数一致即证明。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/msim_it7 && bash run_m9_v23.sh
```

激励 = 冻结集 sim/stim/dma（seed 909，run01 同一集，sha256 见
stim_sha256.txt）。原始日志：m9_v23.log / m9_v23_vlog.log。

门链位置：B0 迭代 9——**M9 run04** → M9b run06 → M12 csr v23 →
M10 v23 → OOC v23。
