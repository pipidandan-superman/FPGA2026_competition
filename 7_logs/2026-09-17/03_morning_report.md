# 2026-09-17 晨报 —— B0 OOC 150MHz 收敛 + M11 过夜

（授权执行：2026-09-17 ~01:30 "……继续 B0 迭代……直至 150MHz 收敛
或无计可施；B0 收敛或你判断应冻结后，M11 ModelSim 过夜直接启动，
无需再问我。早上留完整报告。"）

## 一句话

**B0 收敛：OOC v27 GEMM16_OOC_TIMING_PASS wns +0.005ns
（fmax 150.11MHz，150MHz 目标达成）**；功能门 M10 run12 / M12 csr
run09 与 v26 逐拍相同；M11 v27 全网 ModelSim 过夜进行中
（heartbeat t=20e9 err=0）。

## 各轮 WNS 轨迹（迭代 10–13，本会话窗口）

| 轮 | RTL 变更 | WNS (ns) | fmax | 判决 |
|---|---|---|---|---|
| v24 | requant V1.2e（64 位桶形消失） | −0.224 | 145.12 | FAIL |
| v25 | requant V1.2f（prod2_r，PIPE 6）+ addrgen V1.3 + gemm_array V1.8 尾链 | −0.079 | 148.24 | FAIL |
| v26 | requant V1.2g（操作数重寄存，PIPE 7）+ gemm_array V1.9 尾链 | −0.031 | 149.30 | FAIL |
| **v27** | **gemm_array V1.10（行地址乘加拆分）** | **+0.005** | **150.11** | **PASS** |

完整轨迹 v13→v27 见
4_metrics/logs/2026-09-17_yolo7020_ooc_gate_v27/README.md。

三步收敛病理同一类：**宽乘法映射 2-DSP 级联且首 DSP 被组合穿越**
（A→multiplier→adder→PCOUT 内部弧 4.04ns，操作数自布线 FF 发火，
无输入寄存可吸收）。修法一致：给乘法一个额外拍让操作数寄存吸收进
DSP（AREG/BREG）或拆出独立寄存积（PREG）——v26 requant
sum_r→PCIN 与 v27 oc_g_d1_r→row_addr PCIN 同构。v27 行地址乘法
单 DSP 化后 **dsp48e1 141→140**。

## 门链结果（v27）

| 门 | 结果 | 与 v26 对比 |
|---|---|---|
| M5 v26 (run04) | PASS pipe=7 | requant 未再改，结果有效 |
| M7 v26 | PASS | addrgen 未再改，结果有效 |
| M10 v27 (run12) | PASS 438447/438447/3247 ldone=6 adone=1 | **六层时刻逐拍同**（layer0 @29936000 … layer5 @43927166000），$finish 47771360 ns 同 |
| M12 csr v27 (run09) | PASS csr=0 | **六层时刻逐拍同**（layer5 @43958550000） |
| OOC v27 | **PASS** wns +0.005 / whs +0.051 | 布线零错；dsp 141→140 |

V1.10 的 d9 呈现拍不变设计得到两级实证（M10 + M12）。

## B0 冻结点（RTL 版本）

gemm_array **V1.10** / requant **V1.2g** / addrgen **V1.3** /
ctrl **V1.8** / xbuf **V2.2**（BMG 输出寄存，读延迟 2）/
dma **V1.3** / dma_wr **V1.5**。数值合同 = 延迟平移合同
（2026-09-17 授权），黄金字节不变。

v27 OOC 新临界（全部正裕量）：addrgen vld_o→xbuf BRAM ENARDEN
+0.005 —— BMG 输出寄存合同下的稳定形态，无需再动。

## M11 状态

- 已启动（无需再问，按授权）：sim/msim_v19/run_m11_v27.sh，
  vsim -c -novopt +STIM=../stim/m11 +WDT_MS=3600000。
- 首跑 vlog-19：work_v27 库缺 vlib（v19/v25/v26 脚本从未执行，
  潜伏缺口首次暴露；脚本已补 guarded vlib 并留注释）。
- 判据：TB_FULLNET_PASS convs=63 psops=65 compared=3553900
  dut_wr=3553900 head_bytes=149100 ldone=63 adone=1
  + headcheck sha256 ==
  9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad。
- 对照：v13 run（B0 期唯一已执行全网 M11）同 token 同计数。
- 当前进度：heartbeat t=20000000000 conv=0 ywr=351952 **err=0**。
  完成后本文件补判决行（或见 v27_m11_run.log 尾部）。

## 证据目录（本窗口新增）

- 4_metrics/logs/2026-09-17_yolo7020_m5_requant_run04/（v26）
- 4_metrics/logs/2026-09-17_yolo7020_m10_gemm_array_run11/（v26）
- 4_metrics/logs/2026-09-17_yolo7020_m12_csr_engine_run08/（v26）
- 4_metrics/logs/2026-09-17_yolo7020_ooc_gate_v26/（含 rowaddr
  详径 + top25 探针）
- 4_metrics/logs/2026-09-17_yolo7020_m10_gemm_array_run12/（v27）
- 4_metrics/logs/2026-09-17_yolo7020_m12_csr_engine_run09/（v27）
- 4_metrics/logs/2026-09-17_yolo7020_ooc_gate_v27/（PASS + 轨迹表）

## 后续（待授权/已授权未启动）

- A2 loader V2 三件套（此前已授权，未启动）。
- B1 主工程整合/bd + M13 板卡操作（需另行授权）。
- 调试工件清理决策：tb_yolo_gemm_array_dbg.v /
  xsim/yolo_gemm_array_probe.v（不入门证据，已在档外）。
