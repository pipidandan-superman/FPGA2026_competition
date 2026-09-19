# M9 dma 门 run02 — dma V1.1 增量 bnd_r（2026-09-17, B0 迭代 7）

## 结果：TB_DMA_PASS（与 run01 逐计数一致）

```
TB_DMA_PASS bytes=210904 cmds=33 ars=1666 (stall-tolerant, 4KB-split, checksummed)
$finish : ../tb_yolo_dma.v(323)  Time: 6022380 ns
```

210904 字节逐字节 + 33/33 命令计数/校验和 + 1666 个 AR 对齐/不跨 4KB/
地址链/无超取/rlast 末拍——全部与 run01（V1.0, 2026-09-15）完全一致。

## RTL 变更（rtl/yolo_dma.v V1.0 → V1.1）

用户授权"dma_wr/dma_rd 增量寻址"批：4KB 边界拍数从每拍
`(4096−addr_r[11:0])>>3` 重算（12 位减法+移位+比较，嵌在全部
addr_r/last_burst_r/beats_w 更新路径）改为增量维护寄存器 bnd_r：

- 命令接受沿：`bnd_r <= 10'd512 − {1'b0, cmd_addr_i[11:3]}`（地址
  8 对齐合同下 [11:3] 即线内 beat 序号）；
- AR 发火沿：`bnd_r <= (beats_w == bnd_r) ? 512 : bnd_r − beats_w`；
- 复位 512；beats_w 改读 bnd_r，不再读 addr_r。

突发序列/AR 地址/拍数逐拍不变（同一计算的纯重定时）——本次 run02
逐计数一致即为其证明。动机：B0 v20 ooc owner addr_r→last_burst_r
−0.862ns / addr_r→addr_r[31] −0.783ns（重算级联拆除后 addr_r 变纯
累加器）。位宽教训：bnd_r 需 10 位（512 装不进 9 位，9'd512 截断
为 0——编辑期自纠）。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/msim_it7 && bash run_m9_v21.sh
# vlib work; vlog ../../rtl/yolo_dma.v ../tb_yolo_dma.v
# vsim -c -novopt +STIM=../stim/dma +WDT_MS=60000 work.tb_yolo_dma
```

激励 = 冻结集 sim/stim/dma（seed 909, run01 同一集, stim_sha256.txt）。
原始日志：m9_v21.log（transcript）/ m9_v21_vlog.log（编译）。

门链位置：B0 迭代 7（OOC v21 批）——M9 → M9b run04 → M12 csr run03
→ M10 v21 → OOC v21。
