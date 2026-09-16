# M9b dma_wr 门 run04 — dma_wr V1.3 增量 bnd_r（2026-09-17, B0 迭代 7）

## 结果：TB_DMA_WR_PASS（与 run03 逐计数一致）

```
TB_DMA_WR_PASS bytes=410255 fed=410255 cmds=45 aws=3240 (stall-tolerant, 4KB-split, B-drain, bijection+checksummed)
$finish : ../tb_yolo_dma_wr.v(495)  Time: 12244230 ns
```

410,255 字节双射 + 45/45 命令计数/校验和 + 3,240 个 AW（8 对齐/
不跨 4KB/地址链/WLAST 末拍/单在途）+ 28 条非对齐命令（head=0..7）
首字 wstrb 掩 head、字节精确落址——全部与 run03（V1.2, 2026-09-16）
完全一致。

## RTL 变更（rtl/yolo_dma_wr.v V1.2 → V1.3）

dma V1.1 镜像（同批授权）：删每拍 `(4096−addr_r[11:0])>>3` 重算的
bnd_beats_w，改增量寄存器 bnd_r——命令接受沿
`10'd512 − {1'b0, cmd_addr_i[11:3]}`（awaddr 本就下对齐 8B，[11:3]
与 [2:0] 无关，非对齐命令装载值同样正确）、AW 发火沿 −beats、吃掉
边界回装 512。addr_r 变纯累加器。突发序列/AW 地址逐拍不变（纯重
定时）——本次 run04 逐计数一致即为其证明；head=0 回归路径不变。
动机：v20 ooc dma_wr 同源 owner（与 dma 侧同构的重算级联）。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/msim_it7 && bash run_m9b_v21.sh
# vlib work2; vlog ../../rtl/yolo_dma_wr.v ../tb_yolo_dma_wr.v
# vsim -c -novopt +STIM=../stim/dma_wr +WDT_MS=120000 work2.tb_yolo_dma_wr
```

激励 = 冻结集 sim/stim/dma_wr（seed 912, run03 同一集,
stim_sha256.txt）。原始日志：m9b_v21.log / m9b_v21_vlog.log。

门链位置：B0 迭代 7——M9 run02 → **M9b run04** → M12 csr run03
→ M10 v21 → OOC v21。
