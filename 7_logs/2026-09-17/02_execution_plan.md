# 2026-09-17 执行记录（B0 迭代 10–13 + OOC v25–v27）

## 迭代 10（凌晨，完成）

- requant V1.2d→V1.2e：64 输出桶形消失（q8 窗口 mux ×8、qneg=
  prod[63]、在域判定代数化 himask）。首版 himask 位序错被 M5 v24
  拦下（m5_v24a_xsim_fail.log，2739 错）。
- 门链：M5 v24 run03 PASS（21465）/ M10 run09 PASS（438447，层时
  刻与 v21–v23 逐拍同）/ M12 csr run06 PASS（csr=0）/ OOC v24
  **FAIL −0.224（fmax 145.12）**——桶形家族整体退出 top10。

## 迭代 11（本日主体）

设计（v24 top10 两族）：
1. requant V1.2f——v24 top1 族（prod_c_w__2/CLK→q8_r −0.224…）：
   prod_r 被综合吸收为 DSP48E1 PREG，CLK→P 出 DSP 长线 + 3 级
   64:1 窗口 mux 同拍无解 → prod2_r fabric 重寄存（PIPE 5→6，纯
   输出侧）；mask/himask 同值晚一拍（c2b 沿）。
2. addrgen V1.3——v24 第二族（kh_r→pad_o −0.158、k_len_c→
   row_off_r −0.157…）：两级输出寄存拆窗口解码 + last_k 用
   k_len_m1_c（描述符接受沿采 K−1）超前预测。
3. ctrl 不动：S_DRAIN 长度由 gemm_array acc 排空链决定，与 requant
   深度无关（requant 在 S_RQ 的 rq_en 拍采输入）。

执行：
- M5 v25 PASS（TB 唯一改 PIPE=6，黄金复用）。
- M7 v25a FAIL（66637 错，首差 beat4 pad=1(exp0)）——首版把窗口
  比较放捕获同沿。修复两级 A/B 后 M7 v25 PASS（67918）。
- M10/M12 v25a FAIL（err=134307，字节流错位）——**根因：gemm_array
  Y 尾不消费 requant vld_o，以延迟 en 链重建有效**（LUT en d6、
  sideband d7、SEG_IDLE 读 d7 全挂 PIPE=5）。gemm_array V1.8：
  LUT en rq_en_d7_r、sideband 链延至 d8、SEG_IDLE 读 d8、在途
  计数峰值 7→8（仍 4 位）。
- M10 v25 run10 PASS（计数与 run09 同；层时刻 +2 拍早期漂移，总
  时长 47770370 与 v24 同）/ M12 csr v25 run07 PASS（层时刻与 v24
  逐拍同——被 CSR 轮询粒度吸收）。

## OOC v25

（判决见 4_metrics/logs/2026-09-17_yolo7020_ooc_gate_v25/README.md）
**FAIL −0.079（fmax 148.24）**——唯一 owner 家族 requant 乘法级联
（sum_r→prod DSP PCIN，首 DSP 组合穿越 4.04ns）。

## 迭代 12（凌晨–清晨，完成）

设计（v25 唯一 owner）：requant V1.2g——乘法操作数直通重寄存
sum_x_r/m_x_r/s_x_r/v1b_r（c1b 拍，PIPE 6→7），给映射器
AREG/BREG 候选，级联跳变自 DSP 内部寄存器发火。gemm_array V1.9
适配：LUT en rq_en_d8_r、sideband d9、SEG_IDLE 读 d9、在途峰值
8→9（仍 4 位）。ctrl 不动（同 V1.8 论证）。

执行：M5 v26 run04 PASS（pipe=7）→ M10 v26 run11 PASS（层时刻较
v25 +2 拍合法平移：layer0 @29936000、layer5 @43927166000，计数同）
→ M12 csr v26 run08 PASS（csr=0，layer5 @43958550000——再 +2 拍
漂移，轮询不再完全吸收）→ **OOC v26 FAIL −0.031（fmax 149.30）**：
requant 族清零，新唯一 owner = gemm_array V1.5 行地址融合乘加
（oc_g_d1_r_reg[13]→row_addr_d2_r0/PCIN，top10 全同族）——与
requant v25 病理同构（A→mult→adder→PCOUT 4.036ns 组合穿越，
详径 ooc_v26_rowaddr_path.rpt）。

## 迭代 13（清晨，完成）

设计（v26 唯一 owner）：gemm_array V1.10——拆分融合式
`cfg_ybase + oc_g*n_total + n_base`：
1. cfg 项 d1 快照（n_tot_d1_r/ybase_d1_r）——d1 后不再读 cfg，
   V1.5 的 NBA 次序论证由构造退役；
2. 16x16 乘法自带寄存积 row_prod_d2_r（d2 沿，单 DSP PREG，弧内
   无级联）；
3. ybase+n_base 布线并行加 row_sum_d2_r（d2 沿）；
4. d3 沿合并 row_addr_d3_r，地址腿 d3 起并入原 sideband 移位链。
mod-2^32 加法结合律——逐位等价；d9 呈现拍不变 → M10/M12 v27
应与 v26 逐拍相同（M10 v27 实测 layer0 @29936000 = v26）。requant/
addrgen/ctrl 不动，M5/M7 v26 单元结果有效。

门链（v27）：M10 run12 PASS（六层时刻与 v26 逐拍同，$finish
47771360 ns 同）→ M12 csr run09 PASS（六层时刻与 v26 逐拍同，
csr=0）→ **OOC v27 PASS wns +0.005（fmax 150.11）——B0 150MHz
收敛**。资源 dsp48e1=140（少 1：行地址乘法单 DSP 化）。
新临界 = addrgen vld_o→xbuf BRAM ENARDEN +0.005（BMG 输出寄存
合同下的稳定形态，全 top10 正裕量）。

## B0 冻结 + M11 过夜（按 2026-09-17 授权）

- 冻结点：gemm_array V1.10 / requant V1.2g / addrgen V1.3 /
  ctrl V1.8 / xbuf V2.2（BMG 输出寄存）/ dma V1.3 / dma_wr V1.5。
- M11 v27 过夜启动（sim/msim_v19/run_m11_v27.sh）：首跑 vlog-19
  （work_v27 库缺 vlib——v19/v25/v26 脚本从未执行，潜伏缺口本跑
  才暴露；脚本已补 guarded vlib 并留注）。重跑编译干净，vsim
  全网进行中。判据：TB_FULLNET_PASS convs=63 psops=65
  compared=3553900 dut_wr=3553900 head_bytes=149100 ldone=63
  adone=1 + headcheck sha256
  9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad。

## 证据

- 4_metrics/logs/2026-09-17_yolo7020_m5_m7_unit_v25/
- 4_metrics/logs/2026-09-17_yolo7020_m10_gemm_array_run10/
- 4_metrics/logs/2026-09-17_yolo7020_m12_csr_engine_run07/
- 4_metrics/logs/2026-09-17_yolo7020_m5_requant_run04/（v26）
- 4_metrics/logs/2026-09-17_yolo7020_m10_gemm_array_run11/（v26）
- 4_metrics/logs/2026-09-17_yolo7020_m12_csr_engine_run08/（v26）
- 4_metrics/logs/2026-09-17_yolo7020_ooc_gate_v26/（含 rowaddr
  详径 + top25 探针）
- 4_metrics/logs/2026-09-17_yolo7020_m10_gemm_array_run12/（v27）
- 4_metrics/logs/2026-09-17_yolo7020_m12_csr_engine_run09/（v27）
- 4_metrics/logs/2026-09-17_yolo7020_ooc_gate_v27/（PASS + 全
  WNS 轨迹表）
- FAIL transcripts：m7_v25a / m10_v25a / eng_v25a 均随各目录留档；
  M11 v27 首跑 vlib 缺口以脚本内注释留档（工具坑，非门判决）。
