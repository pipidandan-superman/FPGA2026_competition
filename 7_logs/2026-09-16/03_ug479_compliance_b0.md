# 2026-09-16 执行记录（B0 OOC + UG479 严格合规批 + M11 xsim 失败链收口）

接 02_execution_plan.md（M12 A1 五门全绿）之后。本日下半程：
Vivado OOC 三跑 + UG479 全文审计与全量合规改造 + 门链重跑 + M11
双跑 ModelSim 收口。无板卡操作。

## B0 OOC run01/02：DSP 超映射修复，时序未过

- run01：DSP 238/220 超映射——Vivado 2025.2 把推断式双 int8 打包乘法
  拆成双 8 位乘法器。修复 = pe_pack V1.1 DSP48E1 源语直例 + xbuf V2.0
  BMG IP（13824 LUTRAM → BRAM）。
- run02：dsp48e1=142 ramb36=20 资源达标，但 150MHz FAIL
  （WNS −31.140，fmax 26.45MHz）。

## UG479 严格合规批（用户令"读 ug479 严格按手册设计"，全量 V1–V4）

审计（v1.10 全文 58 页）：12 项已合规 + 四类违规全修——
- V1/V2：C/D 端接（Table 2-2 note 1：tie High + CREG/DREG=1 + CE/RST Low）
- V3：控制属性显式（OPMODEREG==CARRYINSELREG=0（p.41）、ALUMODEREG/
  INMODEREG/CARRYINREG=0，消除隐式默认 1 的寄存）
- V4：AREG=BREG=MREG=PREG=1 三级流水（p.14/p.47），ACASCREG=BCASCREG=1
  （Table 2-3），RSTA/B/M/P=~rst_n（Table 2-4）
- **延迟合同变更：pe_pack 输入 D 拍 → 输出 D+3 拍**（w_d3 对齐做
  lane0 偏置校正）；gemm_array V1.3 acc_en 3 拍重定时；ctrl V1.3
  S_DRAIN（末 K 拍乘积 tk → acc 落地沿 tk+4 → requant 采样 tk+5，
  k_total=1 单拍 tile 亦安全，纸上重定时 + 黄金镜像双验）

门链（冻结顺序）：
- M1 PASS 10216/10216（黄金集未动——数值不动的直接证据；首编失败 =
  注释内 `x*/w*` 的 `*/` 提前终注释，18 连错留证）
- M8 PASS 706403 拍 ×15 输出（ctrl_vecgen 黄金再生成，drain=3×2271）
- M4/M10 PASS layers=6 compared=438447 与基线逐项同数
- **M11 双跑 ModelSim 全绿**：V1.3 批 TB_FULLNET_PASS 3553900 同数 +
  M11_HEADCHK_PASS sha==run04；V4 前基线（Plan B）同日同数复验。
  xsim 侧 M11 被 TB 级 X 问题阻塞——PS t_add/t_rscl 大数组任务在
  xsim 把 X 写进 DDR 镜像（XDBG3 判决；bisect1/2 + ModelSim 三重
  自洽，RTL 无罪），M11 以 ModelSim 为准。
  证据 `4_metrics/logs/2026-09-16_yolo7020_m11_fullnet_xsim_failchain/`。

## B0 run03 + dbg7c：−31ns 根因改判（重要）

- run03（合规批 RTL）：dsp=142 稳定（流水寄存器不引入乘法器）、
  WNS=−31.017 与 run02 持平——**"0 级流水 = −31ns 根因"被路径证据
  推翻（作废，勿再引用）**
- 真属主 = **addrgen 描述符捕获 16 位组合除法/取模**
  （yolo_addrgen.v:158 `oy_r<=n_start/ow; ox_r<=n_start%ow`，
  95 级逻辑 76×CARRY4，cfg_ow_r_reg[0]→ox_r_reg[15]）
- dbg7c 分层（15159 失败端点构成）：requant −24.6（47 级 mul/shift/
  sat 未分级）；acc −15.2 / ctrl −11.6（levels=1，FSM→512 lane 高
  扇出 CE 纯布线）；xbuf −10.8（addrgen ox_r 直喂 BRAM）；PE −8.1
  （DSP 墙内已无长链——V4 对 DSP 路径本身有效，被别处掩盖）
- **时序修复三向（除法移出捕获拍 / requant 分级 / CE 复制）= 新
  范围，待用户授权**

## 本批新坑（6 条，已入记忆与证据 README）

块注释 `x*/w*` 提前终注释；`| tail` 掩盖 xvlog 失败致 xelab 用陈旧
库拼无效快照（每批独立 work 库 + 查 log ERROR）；xelab 无 -work 用
lib.unit；Bash 工具 cwd 每调用重置必须自带 cd；ModelSim 直例 DSP48E1
须 `vlog <vivado>/.../unisims/DSP48E1.v` 入库（vsim-3033）；两台 vsim
并行可行（独立目录防 transcript 互踩）。

证据：`4_metrics/logs/2026-09-16_yolo7020_ug479_compliance/`（README +
M1/M8/M4/B0/dbg7c 日志 + M11 双跑 log）。
