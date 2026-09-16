# 2026-09-16 yolo7020 UG479 严格合规批（V1–V4 全量）门链证据

用户指令："暂停当前任务，阅读 ug479，严格按照手册要求设计"；范围选择
（AskUserQuestion）：**全量合规 V1–V4**。依据 = UG479 v1.10
（2018-03-27，docs_ref/ug479.txt，全文 58 页抽取）。

## 审计结论（改动前）
- 12 项已合规：OPMODE=7'b0000101 (X=M,Y=M,Z=0) 合法配对、ALUMODE=
  0000、USE_SIMD=ONE48+USE_MULT=MULTIPLY、USE_DPORT=FALSE、DIRECT
  输入、级联口 tie-0、输出开路、ACASCREG≤AREG、|A|<2^24 打包界、
  requant/acc 推断式（按手册推荐）
- V1：C 端接违约 → C=48'hFFFFFFFFFFFF, CREG=1, CEC=0, RSTC=0
  （Table 2-2 note 1：未用数据口 tie High + 选端口寄存器 + CE/RST Low）
- V2：D 端接违约 → D=25'h1FFFFFF, DREG=1, CED=0, RSTD=0（同上）
- V3：控制寄存器隐式默认 1 → OPMODEREG=CARRYINSELREG=0（p.41 必须
  相等）+ ALUMODEREG=INMODEREG=CARRYINREG=0 显式流穿
- V4：0 级流水（WNS −31ns 根因）→ AREG=BREG=MREG=PREG=1（p.14
  "at least three pipeline registers"；p.47 重申）；ACASCREG=
  BCASCREG=1 由 Table 2-3 强制；RSTA/B/M/P=~rst_n 同步复位
  （Table 2-4 优先级）

## RTL 改动（数值合同不变，仅延迟合同 0→3 拍）
| 文件 | 版本 | 内容 |
|---|---|---|
| rtl/yolo_pe_pack.v | V1.2 | DSP48E1 全属性显式合规 + 新 rst_n_i 口 + w_d3 对齐延迟（lane0 偏置校正用 3 拍前 w 对齐已寄存 P） |
| rtl/yolo_gemm_array.v | V1.3 | pe_pack 实例接 rst_n；acc_en 3 拍重定时（acc_en_d1/2/3） |
| rtl/yolo_ctrl.v | V1.3 | 新增 S_DRAIN（S_K 后 3 拍再进 S_RQ）：末 K 拍乘积 tk 产生 → acc 落地沿 tk+4 → requant 采样 tk+5，drain 占 tk+1..tk+3，k_total=1 单拍 tile 亦安全 |

## 门链结果（冻结顺序 M1→M8→M4/M10→M11→B0）
- **M1 PASS** `TB_PE_PACK_PASS compared=10216/10216`
  （xsim snap_m1_v12b；10216 向量黄金集与 V1.0/V1.1 同一套未动——
  三级流水只移延迟不动数值的直接证据）
- **M8 PASS** `TB_CTRL_PASS compared=706403 cycles (15 outputs/cycle)
  ldone=23 alldone=1`（xsim snap_m8_v13；ctrl_vecgen.py 黄金再生成，
  drain_cycles=6813=3×2271 tiles ✓）
- **M4/M10 PASS** `TB_GEMM_ARRAY_PASS layers=6 compared=438447
  dut_wr=438447 gold_wr=3247 ldone=6 adone=1`（xsim snap_m4_v13；
  统计与 V4 前基线完全一致，含 k=2304/k=576 层）
- **M11 PASS（ModelSim，2026-09-16 晚收口）**：
  `TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900
  head_bytes=149100 ldone=63 adone=1`（v13_m11_run.log，msim_v13/
  work_v13）+ **`M11_HEADCHK_PASS` sha256=9ce70525fc1732cde640bfa6
  54919dd28504422aa9791a2875225ae6ad6aa6ad == run04 frame0 权威值**，
  6 张量拆分逐字节全对——与 V4 前基线（Plan B 同日收口，见
  ../2026-09-16_yolo7020_m11_fullnet_xsim_failchain/）完全同数。
  三级流水重定时（acc_en_d3 + S_DRAIN）在全网 63 conv 下数值不变。
- **B0 OOC run03 完成（FAIL @150MHz，与 run02 持平）**：
  `dsp48e1=142 ramb36=20` / `WNS=-31.017 whs=+0.117 fmax=26.54MHz`
  （run02 对照：dsp=142 / WNS=−31.140）
  - ✅ DSP 计数稳定 142（128 PE + 14 推断式 addrgen/requant 等），
    MREG/PREG 加入未拆出额外乘法器；数值批门链全绿
  - ❌ **WNS 未改善**——前次会话"0 级流水 = −31ns 根因"判断被
    路径证据**推翻**（−31.140 → −31.017，仅 +0.12ns）
  - **真 −31ns 属主 = addrgen 描述符捕获除法**：
    `u_array/cfg_ow_r_reg[0] → u_addrgen/ox_r_reg[15]`，95 级逻辑
    （76×CARRY4），源码 yolo_addrgen.v:158-159
    `oy_r <= n_start_i / ow_i; ox_r <= n_start_i % ow_i;`
    ——16 位组合除法/取模在捕获拍一次算完
  - dbg7c 分层剖析（次差类）：requant **−24.6**（47 级 mul/shift/sat
    未流水）；acc **−15.2**（levels=1，FSM→512 lane CE 高扇出纯布线）；
    ctrl −11.6（同 CE 扇形态）；xbuf −10.8（addrgen ox_r 直喂 BRAM）；
    PE 自身 −8.1（levels=1，广播网布线；DSP 墙内已无长链——
    V4 对 DSP 路径的收益被更差的别处掩盖）
  - 修复方向（**新范围，待授权**，不在 V1–V4 批内）：
    (a) addrgen 除法/取模移出单拍（预计算 or 多拍迭代除法 or
    由 ctrl 传商/余数）；(b) requant 算术链分级；(c) acc/ctrl 高扇出
    CE 复制（max_fanout/寄存器复制）

## 工具坑（本批新增）
1. **块注释内 `x*/w*` 的 `*/` 提前终止注释**——pe_pack V1.2 首编
   18 连错（首个错在第 50 行 `*`，余波至 190 行 'always' incorrect
   context）。修复 = 改写为 "x and w"。教训：注释里写乘号组合时
   避免 `*/` 序列。
2. **管道掩盖编译失败**：`xvlog ... | tail -3` 使 bash 拿到 tail 的
   退出码，`&&` 误跑 xelab 并用陈旧 work 库拼出无效快照。改法：
   检查 log 内 ERROR 字符串而非管道退出码，且每批用独立 work 库
   （work_m1v12 / work_m8v13 / work_m4v13）。
3. **xelab 无 `-work`**：库限定用 `lib.unit` 语法
   （`xelab work_m1v12.tb_yolo_pe_pack ...`）。
4. **Bash 工具 cwd 每次调用后重置**：全部命令显式 `cd` 前缀。
5. **ModelSim 直例 DSP48E1 需把 unisim 源编进库**：
   `vlog -work work_v13 <vivado>/data/verilog/src/unisims/DSP48E1.v`
   （否则 vsim-3033 Instantiation failed；无 modelsim.ini 映射时
   这是唯一路径）。

## 文件
m1_v12b_{xvlog,xelab,xsim}.log / m8_v13_{xvlog,xelab,xsim}.log /
m4_v13_{xvlog,xvlog2,xelab,xsim}.log（xsim 侧）
sim/msim_v13/ = V1.3 批 ModelSim 独立目录（work_v13 + v13_m11_run.log）
proj/ooc_gate/ooc_v13.tcl + ooc_v13_* = B0 run03
