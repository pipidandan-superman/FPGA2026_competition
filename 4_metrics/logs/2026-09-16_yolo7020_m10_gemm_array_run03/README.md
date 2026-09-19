# M10 gemm_array 门 run03 —— DUT V1.2a Y 真 AXI 写主承接（2026-09-16）

## 结果：TB_GEMM_ARRAY_PASS（run02 失败链留证[段化器在途竞态，RTL 修复] + run03 全绿）

```
TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1
```

**与 V1.0 run01 门同一性逐项同数**（layers/compared/dut_wr/gold_wr/ldone/adone
六项全同；门判据为计数同一性，非周期同一性——Y 写延迟变化允许）。激励零改动
（stim/m10 22 个 hex 重算 sha256 与 run01 记录零失配）；数值路径逐字节唯一地址
不变（Y 写序与镜像布局无关，A2 决策行）。

## 为什么重跑（M12 A1）

DUT 升 V1.2/V1.2a：Y 从观测输出口（y_we/y_addr/y_wdata）换真 AXI4 写主
（阵列内行段化器 + u_dma_wr V1.2 实例 + ctrl V1.2 rq_rdy 行首背压 +
dsc_ybase 描述符字段）；ldone/adone 排空门控。数值合同不变；本门验证
接口承接后全链仍与黄金逐位一致。

## RTL 变更（rtl/yolo_gemm_array.v V1.0 → V1.2 → V1.2a）

- V1.2（详见文件头）：dsc_ybase 字段；行段化器 FSM（SEG_IDLE/FILL/CMD/DR，
  行 = n_tail 字节 @ ybase+oc_g·n_total+n_tile·N_EDGE，任意字节对齐）+
  u_dma_wr 实例；行首准入背压接 ctrl rq_rdy_i（d0 判决点，d1..d3 在途拍
  自然排空，requant/LUT 脉冲 valid 无需保持支持）；行地址/长度 d0 计算
  沿流水携带（cfg 竞态免疫）；ldone_pend/adone_pend 排空门控。
- **V1.2a（run02 失败链修复）**：行首准入条件 `段化器 IDLE` **加在途计数
  seg_infl_r==0**（d0 准入 +1 / d3 落地 −1 = d1..d3 精确占用）；
  `ywr_idle_w` 同判据（堵 ctrl_ldone 贴尾 3 拍内 layer_done 早脉冲窗口）。

## run02 失败链根因（留证：m10_run02.log）

`TB_GEMM_ARRAY_FAIL err=23 dbl=0 gdbl=0 unwritten=23 yaxi=0
dut_wr=438424(exp 438447) ldone=6 adone=1` —— 恰丢 23 字节、其余全对。

根因：准入读**前沿前**的 `seg_state_r`。行首拍准入后 3 拍才落地，这 3 拍
窗口内段化器仍读 IDLE，后续行首拍继续被准入；首个落地后段化器进 SEG_CMD，
其余落在 CMD 被静默丢弃。**len-1 行序列**（n_tail=1 的尾 tile 内行首拍
背靠背）每 IDLE 窗口放进 4 个行首拍 = 吸收 1 + 丢 3：

- L0 尾 tile 7 行 → 丢 5；L2 尾 tile 16 行 → 丢 12；L5 尾 tile 8 行 → 丢 6
- **5+12+6 = 23，与 FAIL 逐位吻合**（三层的 n=49/25/25 均含 n_tail=1 尾 tile；
  L1/L3/L4 的 n 全 8 倍数无尾 tile）

设计论证盲点：原"SEG_IDLE ⇒ 零在途"只对已落地字节成立，漏算了 d1..d3
流水里的已准入拍。修复后安全论证闭环：准入 = IDLE ∧ 在途 0 ⇒ 在准入拍
落地前无任何事件能把段化器带离 IDLE。run03 中该背压路径被 len-1 行序列
真实激励（ctrl V1.2 S_RQ 等待态首次非平局上场）。

## TB 变更（sim/tb_yolo_gemm_array.v V1.0 → V1.1）

- y_we/y_addr/y_wdata 消费换 **AXI4 写从 BFM**（tb_yolo_dma_wr 模式）：
  aw/w 随机停停（lfsr 独立位）+ B 0–3 拍随机延迟；协议哨兵：awaddr 8 对齐 /
  awsize=3 / INCR / wlast 位置 / 超拍 / 单在途（深度停停/4KB/链化覆盖属
  M9b 门，同一 u_dma_wr 实例）。判据加 yaxi==0。
- 散写按**物理地址**落 yd 镜像：dsc_ybase = L×YSPAN（TB 侧加，布局与 V1.0
  逐位一致，layers.hex 零改动）；哨兵双写检查 + n_ywr 计 strobe 字节数
  （PASS 要求 == total_out）。
- layer_done 已被 DUT 排空门控，层尾 repeat(8) 排空保留为展示性尾拍。

## 命令与环境

```
cd E:\competition\2_fpga\3_yolo_zynq\sim\msim
vlib work_arr
vlog -work work_arr ..\..\rtl\yolo_gemm_array.v ..\..\rtl\yolo_ctrl.v ..\..\rtl\yolo_dma.v ^
    ..\..\rtl\yolo_dma_wr.v ..\..\rtl\yolo_wbuf.v ..\..\rtl\yolo_xbuf.v ..\..\rtl\yolo_addrgen.v ^
    ..\..\rtl\yolo_pe_pack.v ..\..\rtl\yolo_acc.v ..\..\rtl\yolo_requant.v ..\..\rtl\yolo_silu_lut.v ^
    ..\..\rtl\yolo_conv_core.v ..\tb_yolo_gemm_array.v
# run02（失败链）: -l m10_run02.log ；修复后:
vsim -c -novopt +STIM=../stim/m10 +WDT_MS=900000 -l m10_run03.log ^
     -do "run -all; quit -f" work_arr.tb_yolo_gemm_array
# 期望: TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1
```

主机 HC-202510241838（Windows 11 企业版）；ModelSim SE-64 10.1c（`-c -novopt`
铁律）；work_arr 独立库（work 库存 M8/M9b 门编译）。RTL/TB/激励 sha256 见
stim_sha256.txt（绝对路径；22 stim hex + array V1.2a + TB V1.1 + manifest）。

## 证据清单

1. 本 README.md
2. console_extract.txt（PASS token 摘录）
3. m10_run03.log（通过 transcript 原件）+ m10_run02.log（失败链原件）
4. stim_manifest.json（沿用 run01 原件——激励零改动）+ stim_sha256.txt

## 结论

M10 门 V1.2a 承接通过。Y 真 AXI 写主链（ctrl V1.2 背压 → requant 尾 →
行段化器 → dma_wr V1.2 → AXI 写从）在 6 层合成+真实混合激励下与黄金逐位
一致，len-1 行背压路径真实激励。下一门：M11 全网 63 conv 回归（TB 同构
改造：Y 写 BFM 散写镜像本体 + dsc_ybase = prog 程序字）。
