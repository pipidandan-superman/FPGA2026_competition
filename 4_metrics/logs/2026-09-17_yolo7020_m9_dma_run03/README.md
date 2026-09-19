# M9 dma 门 run03 — dma V1.2 突发末拍 bnd 结算（2026-09-17, B0 迭代 8）

## 结果：TB_DMA_PASS（与 run01/run02 逐计数一致）

```
TB_DMA_PASS bytes=210904 cmds=33 ars=1666 (stall-tolerant, 4KB-split, checksummed)
```

## RTL 变更（rtl/yolo_dma.v V1.1 → V1.2）

v21 ooc dma_wr 同源 owner（words_r→bnd_r −0.634）的读侧预防性同构
修复：bnd 结算沿从 AR 发火挪到**突发末拍**——AR 发火装 `blen_r`
（本突发拍数 ≤16，5 位），末拍（r_fire && beats_r==1 && 非命令末字）
读 blen_r 与 bnd_r 作 10 位等值/减法结算。words_r 彻底退出 bnd 更新
链（原发火沿更新读 words_r→beats_w 最小值级联：words_r>16 折叠 →
32 位 min → 零扩展比较 → 10 位减法 → 回装 mux）。

突发序列/AR 地址逐拍不变（同一算术、结算时刻不同：bnd_r 在下一 AR
可见前已更新完毕——本 run 逐计数一致即证明）。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/msim_it7 && bash run_m9_v22.sh
```

激励 = 冻结集 sim/stim/dma（seed 909, run01 同一集）。原始日志：
m9_v22.log / m9_v22_vlog.log。

门链位置：B0 迭代 8——M5 run02 → **M9 run03** → M9b run05 → M12 csr
v22 → M10 v22 → OOC v22。
