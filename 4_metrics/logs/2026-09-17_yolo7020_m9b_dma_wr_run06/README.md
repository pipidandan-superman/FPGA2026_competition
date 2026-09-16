# M9b dma_wr 门 run06 — dma_wr V1.5 突发参数预计算拆沿（2026-09-17, B0 迭代 9）

## 结果：TB_DMA_WR_PASS（与 run03/04/05 逐计数一致）

```
TB_DMA_WR_PASS bytes=410255 fed=410255 cmds=45 aws=3240 (stall-tolerant, 4KB-split, B-drain, bijection+checksummed)
```

## RTL 变更（rtl/yolo_dma_wr.v V1.4 → V1.5）

v22 ooc top10 **全部 10 条**为 `u_dma_wr/words_r[23] → addr_r[*] /
words_r[*]`（−0.581…−0.372）——AW 发火沿串行本体：
`min(words_r,16)` 24 位比较 → `min(bnd_r,·)` → 32 位减法回装，
加法侧再串 32 位 addr_r 进位链。**突发参数预计算拆沿**：
`want2_r = min(words_r,16)` 与 addr_r 推进（`+blen_r<<3`）均改在上一
突发末拍（w_fire && burst_last）装载/结算——words_r 自上次 AW 发火起
稳定 ≥1 拍、addr_r/blen_r 全突发稳定，末拍只剩单 24 位比较与单 32 位
进位链。**AW 发火沿只剩 min(bnd_r, want2_r) 10 位比较 + 一次 32 位
减法**，addr_r 发火沿纯寄存器搬运（awaddr_o 仅在 S_AW 被采样，提前
推进不可见）。转 S_DR 末拍的推进/装载为哑写（命令接受沿重装；命令
接受沿 want2_r 由 cmd 总线直算——OOC 输入端口无输入延迟约束，B1
整合时按真实 input delay 复核）。

突发序列/AW 地址/周期行为逐拍不变——本 run 逐计数一致即证明。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/msim_it7 && bash run_m9b_v23.sh
```

激励 = 冻结集 sim/stim/dma_wr（seed 912，run03 同一集，sha256 见
stim_sha256.txt）。原始日志：m9b_v23.log / m9b_v23_vlog.log。

门链位置：B0 迭代 9——M9 run04 → **M9b run06** → M12 csr v23 →
M10 v23 → OOC v23。
