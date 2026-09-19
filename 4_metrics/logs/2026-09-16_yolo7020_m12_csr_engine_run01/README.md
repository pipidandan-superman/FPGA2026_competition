# M12 A1 CSR/engine 门 run01 —— yolo_csr + yolo_engine_top（2026-09-16）

## 结果：TB_CSR_ENGINE_PASS（首跑即过；前置 smoke 失败链留证[TB 打包错位]）

```
TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1 csr=0
```

**与 M10 门 run03 计数同一性逐项同数**（layers/compared/dut_wr/gold_wr/ldone/adone
六项全同）+ 新增 csr=0（AXI-Lite 协议/读回/IRQ 检查零错）。激励零改动
（stim/m10 22 个 hex sha256 与 m10 run03 记录零失配，见 stim_sha256.txt）。
本门是 A1 第三件：CSR（PS 真控制路径）+ engine 组装（PROD/SIM 同 RTL
参数化）。A1 三件到此 = M9b run03 ✓ + M10 run03 ✓ + M11 run03（并行在跑）
+ 本门 ✓。

## 门内容（M12 A1 第三件）

- **rtl/yolo_csr.v V1.0**：AXI4-Lite 从（单在途，AW/W 同拍受理，B 保持到
  bready；字节 strobe 合并）；描述符影子寄存器 12 个 + CTRL 门铃/清统计 +
  STATUS（busy/dsc_ready/all_done 粘滞/dsc_pend/ldone 计数[31:16]）+
  IRQ_EN/IRQ_STAT(W1C) + LUT 预载窗口（0x400+4i，i=0..255，只写）。
  C_BASEADDR 参数化（地址合同单一事实源 = hw_contract/address_map.md，
  本批新增寄存器图表，三处同步：合同 + RTL + TB 镜像）。
  门铃语义：START 置 start_pend（dsc_valid 保持）→ 阵列受理沿自动清除；
  阵列仅在受理沿采样影子（层切换竞态免疫沿用阵列 V1.2 设计）。
- **rtl/yolo_engine_top.v V1.0**：u_csr + u_array（V1.2a）纯布线组装；
  AXI4 读主（W/参数）/写主（Y）拉到顶层；X 字节口 A1 直通（组合合同，
  A2 换 xrowgen + 第二读 DMA）；REQUANT_UNITS 参数随 A2 引入。默认参数
  = PROD 16×16，门用 SIM 8×8 实例化（同 RTL 仅参数不同）。
- **sim/tb_yolo_engine_top.v V1.0**：M10 TB 同构（黄金链/W 读 BFM/Y 写
  BFM/比较逻辑原样复制），PS 角色全部换到 AXI-Lite 主 BFM：LUT 窗口
  256 写/层、DESC0..DESC5+6 基址 + DESC0/DESC1 读回抽检、CTRL.START 门铃、
  STATUS.dsc_pend 受理等待、STATUS.ldone_cnt 排空门控完成轮询（层完成
  语义 = Y 已全落地）、all_done 粘滞轮询、IRQ 置起/W1C 清零检查；
  t0 自检：ID/VER + 12 影子寄存器模式读写往返。+MAXLAYER 烟测开关
  （M11 +MAXCONV 先例）。ldone/adone 经 CSR STATUS 快照计数（PS 可见
  视图即门断言对象）。

## smoke 失败链（eng_run01_smoke.log，留证）

`TB_CSR_ENGINE_FAIL err=220 dbl=0 ... dut_wr=343(exp 343) ldone=1` ——
计数全对、220 字节值错，首错 L0 i=2 dut=128 gold=0。根因：**TB DESC1
拼接位错**（`{17'b0,act,first,last,k}` 把三标志放到 [14:12]，CSR 解包读
[18:16]）→ L0 的 act=1 丢失 → SiLU 被旁路（dut=raw requant −128=0x80，
gold=SiLU 负半轴 0）。修复：`{13'b0,act,first,last,4'b0,k}`，并把 DESC1
加入读回抽检（该类错读回一击即中）。smoke2 全绿：
`TB_CSR_ENGINE_SMOKE layers=1 compared=343 dut_wr=343 gold_wr=343 ldone=1 csr=0`。

## 命令与环境

```
cd E:\competition\2_fpga\3_yolo_zynq\sim\msim
vlib work_eng     # 独立库：避免与并行 M11 vsim 共享 work_arr 库文件
vlog -work work_eng ..\..\rtl\yolo_engine_top.v ..\..\rtl\yolo_csr.v ^
    ..\..\rtl\yolo_gemm_array.v ..\..\rtl\yolo_ctrl.v ..\..\rtl\yolo_dma.v ^
    ..\..\rtl\yolo_dma_wr.v ..\..\rtl\yolo_wbuf.v ..\..\rtl\yolo_xbuf.v ^
    ..\..\rtl\yolo_addrgen.v ..\..\rtl\yolo_pe_pack.v ..\..\rtl\yolo_acc.v ^
    ..\..\rtl\yolo_requant.v ..\..\rtl\yolo_silu_lut.v ..\..\rtl\yolo_conv_core.v ^
    ..\tb_yolo_engine_top.v
# smoke（失败链）: +MAXLAYER=1 -l eng_run01_smoke.log ；修复后:
vsim -c -novopt +STIM=../stim/m10 +MAXLAYER=1 +WDT_MS=600000 ^
     -l eng_run01_smoke2.log -do "run -all; quit -f" work_eng.tb_yolo_engine_top
# 门：
vsim -c -novopt +STIM=../stim/m10 +WDT_MS=1800000 ^
     -l eng_run01_full.log -do "run -all; quit -f" work_eng.tb_yolo_engine_top
# 期望: TB_CSR_ENGINE_PASS layers=6 compared=438447 dut_wr=438447
#       gold_wr=3247 ldone=6 adone=1 csr=0
```

主机 HC-202510241838（Windows 11 企业版）；ModelSim SE-64 10.1c（`-c -novopt`
铁律）。RTL/TB/激励 sha256 见 stim_sha256.txt（38 项绝对路径：22 stim hex +
14 RTL + TB + address_map.md；stim 22 项与 m10 run03 记录零失配）。

## 证据清单

1. 本 README.md
2. console_extract.txt（PASS/SMOKE/FAIL token 摘录）
3. eng_run01_full.log（通过 transcript 原件）+ eng_run01_smoke.log
   （失败链原件）+ eng_run01_smoke2.log（烟测通过原件）
4. stim_manifest.json（沿用 m10 run01 原件——激励零改动）+ stim_sha256.txt

## 结论

A1 CSR/engine 门通过。PS 真控制路径（AXI-Lite 描述符/门铃/状态轮询/LUT
窗口/IRQ）+ engine 组装与 M10 门逐位同数。A1 待收口项：M11 全网 run03
（并行运行中）过门后，A1 全绿 → B 段（OOC 综合）另行向用户确认。
