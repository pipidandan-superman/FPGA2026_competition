# 2026-09-17 yolo7020 M11 全网门 run04 — B0 冻结批（v27）

## 结果

**TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900
head_bytes=149100 ldone=63 adone=1**
**M11_HEADCHK_PASS sha256=
9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad**
（== run04 frame0 黄金；6 张量拆分 102400/25600/6400/11200/2800/700
逐字节全对——归档副本独立复跑 headcheck.out 承证）。

七项计数与 v13（B0 期唯一已执行全网 M11）及 M11 run02/run03 逐一
相同；末层 conv 62/63 @t=1356486600000 acc_err=0（63 层全零）。
逐拍 cycle 计数按延迟平移合同合法漂移（迭代 9–13 累计平移），字节
判决不变。

## 本跑覆盖的 RTL（B0 冻结点，OOC v27 wns +0.005 收敛批）

gemm_array V1.10 / requant V1.2g / addrgen V1.3 / ctrl V1.8 /
xbuf V2.2（BMG 输出寄存）/ dma V1.3 / dma_wr V1.5 / pe_pack V1.2。

## 工具坑留档

首跑 vlog-19（work_v27 库缺 vlib）：v19/v25/v26 ModelSim 脚本经
sed 衍生但从未执行，vlib 建库步骤缺失潜伏四代。脚本已补 guarded
vlib（`[ -d work_v27 ] || $VLIB work_v27`）并留注释。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/msim_v19 && bash run_m11_v27.sh
# ModelSim SE-64 10.1c: vsim -c -novopt +STIM=../stim/m11
# +WDT_MS=3600000（墙钟 ~1.5h）
```

激励 = stim/m11 冻结集（13.3MB 镜像不入库）。head_dump.bin 留本
目录不入 Git（惯例）。

门链位置：B0 迭代 13 终点——M10 run12 + M12 csr run09 + OOC v27
PASS → **M11 run04（本跑，冻结批全网承证）**。B1 整合 + M13 板卡
待另行授权。
