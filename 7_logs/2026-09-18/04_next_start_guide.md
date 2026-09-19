# 2026-09-18 下次启动指南

## PE / GEMM 详细架构图（本次）
PE/GEMM 绘图交接：先阅读 [详细图集](../../1_docs/yolo_pe_gemm_architecture_figures_20260918.md)，再对照设计手册。后续实现需锁定原语延迟、RAM 端口和尾部吞吐；图形渲染通过不能代替 RTL 验证。保持冻结 FPGA 项目只读。

## YOLO PL CSR 子系统（主线已收口 ✅）
**板级验收整体闭环（勿重做）**：L1/L2/L3（run03，BOARD_CSR_PASS +
BOARD_L3_PASS）→ L4（run04，BOARD_L4_PASS，暴露幻影尾）→ RTL 修复 +
仿真 85/85（sim_run03_phantomtail）→ **修复版 bit 上板复验 run05
BOARD_L4_PASS（含新增 D5c/D5d 幻影尾钉死：空 ACK 后 STATUS[7:6]=0、
tail/head 纹丝不动；31 连发零幻影；D5a 证实 l3r1 修复未回退）**。
证据 [run05_phantomfix](../../4_metrics/logs/2026-09-18_yolo_csr_bd_board_run05_phantomfix/)。
板上现挂 186154c5 版 overlay（含全部修复），可作 Conv 叠加基线。

遗留小项：~~git 提交 yolo_reg_file.sv + TB + run04/05 证据~~（2026-09-19 凌晨核实已完成：ae8da88/c7080d4 在用户分支）；rom_data README "来源 run01" 标注过时（实为 run04 sha）。

后续方向（原 2/3/4 条）：code-review 审 ps_axi_pl RTL；PS 端驱动化；
再叠 Conv 引擎（walker walk-through 替换，契约不动）。
刚开始时不要做：不要重构已验证 RTL；不要把 Conv/HP/DDR 混进当前 BD；
不要动 axi_action(0x43C0_0000)。

阻塞：无。

## YOLO 量化审查线（背景）
先阅读本日验证摘要和 [软件量化审查报告](../../1_docs/yolo_quant_software_audit_20260918.md)。
禁止直接修改/构建冻结 2_fpga，禁止以FakePL或仿真通过代替板测通过。
成功标准：后续硬件逐层复现 63 Conv 和三尺度 raw head；先修正评估器并确认测试集精度门。
当前待办：对 Right、Thumbs Down、Left 做逐图量化误差分析；必要时重新校准/QAT；不要把当前 valid 改善视为最终精度通过。

## PE/GEMM 手册后的下一步
先阅读 [PE 设计手册](../../1_docs/yolo_pe_design_manual_20260918.md) 和
[GEMM 设计手册](../../1_docs/yolo_gemm_design_manual_20260918.md)。

**G0 已完成（2026-09-18，证据
[pe_gemm_dev_run01](../../4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run01/)）**：
软件 PE oracle（C1 256³ 打包穷举 0 失配 + RNE/饱和/首层/K 分块全过，
PE_ORACLE_PASS）+ golden 链复放等价（rom_data+canvas → oracle 算术 →
53 节点 × 5 帧位级 0 失配，G0_REPLAY_PASS ×5）——oracle ≡ 软件侧量化推理，
复用原则成立，RTL 对拍用 golden_pe.hex / golden_tail.hex 已备。
注意：rom_data README 的"来源 run01"标注过时，四件套实际 sha == run04。

**单 PE RTL ① 已收口（GATE + 256³ 全穷举双 PASS，证据
[run02_singlepe](../../4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run02_singlepe/)）**：
`rtl/GEMM/yolo_pe_core.sv`（V1.2 DSP48E1 原语按实例复用 + 3 级边带流水）+
TB（期望值=金文件/独立乘，永不取自被测公式；三级镜像逐周期延迟计分板）。
GATE：checks=140909 errors=0，lat_err=0，issued−published=3（恰为复位击杀）。
FULL 256³：**checks=16778408 errors=0 PASS**（全部 16,777,216 个三元组含 −128
逐位相等；总账逐笔闭合零残差，分解表见 README）。

**双 INT32 累加器 ② 已独立收口（GATE PASS，证据
[run03_accdual](../../4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run03_accdual/)）**：
`rtl/GEMM/yolo_acc_dual.sv`（first_k 免清零直存 / lane_mask 结构尾 / last_k→done 脉冲 /
INT32 自然回绕域钉 37748736 / clr 排空前置）+ TB（独立 INT64 oracle，GEMM 手册 §14）。
checks=169025 errors=0；守恒 231/228/3 逐相零残差；两个 TB 自伤已修（K=1 记账序、
$random 有符号模陷阱：模必须在无符号拼接表达式上算，X 入激励会被 4 态比较空真放过——beat() 已设 X 绊线）。

**级 2 PE+acc 联合 MAC 已收口（GATE PASS，证据
[run04_macjoint](../../4_metrics/logs/2026-09-18_yolo_pe_gemm_dev_run04_macjoint/)）**：
`rtl/GEMM/yolo_mac_cell.sv`（①PE + fk/lk 三级边带流水[本级唯一新增] + ②acc），
issue D → acc/done 可见 D+4 契约。checks=164044 errors=0 lat_err=0；守恒
240/237/3 精确；§8 域界 +37748736 经**真 DSP48E1 路径**字面钉死；M0 金值交叉
（TB 独立乘 ≡ run01 golden 76 向量零失配）。TB 教训：流水化设计的阶段边界必须
按 D+4 排空判定（M9 钉值曾被 M8 在飞 done 抢先触发）。

下一步：**③ 小阵列 + 共享尾（golden_tail.hex）**
→ ④ 8×16 基线 / 16×16 参数化 → 综合/时序/板测。
不要以手册中的理论下界替代综合、时序和板测数据。
文档证据目录：[2026-09-18_yolo_pe_gemm_manual_run01](../../4_metrics/logs/2026-09-18_yolo_pe_gemm_manual_run01/)。
