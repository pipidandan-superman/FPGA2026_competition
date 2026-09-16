# M9b dma_wr 门 run05 — dma_wr V1.4 突发末拍 bnd 结算（2026-09-17, B0 迭代 8）

## 结果：TB_DMA_WR_PASS（与 run03/run04 逐计数一致）

```
TB_DMA_WR_PASS bytes=410255 fed=410255 cmds=45 aws=3240 (stall-tolerant, 4KB-split, B-drain, bijection+checksummed)
```

## RTL 变更（rtl/yolo_dma_wr.v V1.3 → V1.4）

v21 ooc owner 本体（words_r→bnd_r −0.634）：bnd 结算沿从 AW 发火
挪到**突发末拍**——AW 发火装 `blen_r`（≤16，5 位），末拍
（w_fire && burst_last）读 blen_r 与 bnd_r 作 10 位等值/减法结算。
words_r 退出 bnd 更新链。转 S_DR 末拍的结算是哑写（下一命令接受沿
重装 bnd_r）。head=0..7 非对齐覆盖不变。

突发序列/AW 地址逐拍不变——本 run 逐计数一致即证明。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/msim_it7 && bash run_m9b_v22.sh
```

激励 = 冻结集 sim/stim/dma_wr（seed 912, run03 同一集）。原始日志：
m9b_v22.log / m9b_v22_vlog.log。

门链位置：B0 迭代 8——M5 run02 → M9 run03 → **M9b run05** → M12 csr
v22 → M10 v22 → OOC v22。
