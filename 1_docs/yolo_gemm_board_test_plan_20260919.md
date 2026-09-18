# YOLO GEMM 上板测试计划（2026-09-19）

状态：③④ 仿真门已收官（run06 三档 PASS）；本文件是上板路径的总计划与
晨验清单。**GEMM 尚未到可上板状态**——缺口与证据见 §2，晨验内容见 §4。

## 1. 当前已完成（证据在案）

| 门 | 内容 | 证据 |
|---|---|---|
| G0 | 软件 PE oracle + golden 链复放等价 | run01（PE_ORACLE_PASS / G0_REPLAY_PASS ×5） |
| ① | yolo_pe_core（DSP48E1 打包双 int8） | run02（140909 checks） |
| ② | yolo_acc_dual（双累加器） | run03（169025 checks） |
| L2 | yolo_mac_cell（①+② 联合） | run04（164044 checks） |
| ③a | yolo_gemm_tail（共享尾 §8 全链） | run05（713 checks，含双向 golden 交叉） |
| ③b/④ | yolo_gemm_array 三档 4×4/8×16/16×16 | run06 V1.1（846/4250/6881 checks，0 err） |
| 综合评估 | 16×16 OOC 三配置 | run07（本日，见 §2） |

RTL：`E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/`（阵列/尾/cell/acc/PE + TB×5）。

## 2. 上板缺口（如实）

### G2：W/X 真 bank（ping-pong）——上板的先决条件

run07 配置 A 综合证据：`W_buf_reg with 294912 registers`、
`X_buf_reg with 294912 registers`（各 16×2304×8 位）。③ 档功能缓冲是
**异步读** reg 阵列，综合器既不能推 BRAM 也不能推 LUTRAM，映射为纯 FF +
巨多路器：约 590k FF，而 XC7Z020 仅 106,400 FF——**物理不可容纳**。
（这不是 bug：③ 档缓冲在手册里就是功能占位，真机构就是 G2。）

G2 目标形态（手册 §6 RAM 组织方向）：
- W bank = 16 × BRAM36（2304×8/行），X bank 同；
- TDP：A 口装载写（空闲期），B 口计算读（共享 k 计数器）；
- BRAM 同步读 → 读地址提前一拍（k 计数器流水化），issue 节拍重排；
- ping-pong 双缓冲：当前 tile 计算时预装下一 tile；
- cell/tail/FSM 对外契约不变，TB 阶段矩阵（G1..G9）复跑。

### G4：DMA/CSR 接入

阵列挂上 PS 可控的加载/启动/回收通路。CSR 线的
yolo_control_subsystem（reg_file+tables，板级 L1-L4 已闭环）是现成骨架：
W/X/LUT 走 buf/lut table BRAM，tile 描述走 desc table，结果走 result ring。
契约对接（地址域/握手/中断）需要 G4 专项仿真门。

### G7：系统级综合 + 时序 + 上板

G2+G4 后：与 PS7 100 MHz 域的系统综合、时序收敛、bitstream、板级
L1→L4 式分阶段验收（复用 CSR 线方法论）。

## 3. run07 综合评估结果（终态：部分完成）

- 配置 A（真配置）：**中止于 RTL Optimization Phase 2**（宿主内存临界，
  Vivado 峰值 15.2GB）——但 A 的目的已达成：缓冲代价量化证据已落档
  （§2 的 294912×2 寄存器警告 + 590k FF 算术结论），**无需重跑**；
- 配置 B（P_KMAX=64，核视图）：未运行，晨间补（用户在场数分钟）——
  给出 MAC 网格+尾+FSM 本征 LUT/DSP/FF 与 100 MHz WNS，G2 后对比底线；
- 配置 C（150 MHz）：未运行（可选余量探针）；
- 详见 run07 README（含中止记录与晨间补跑命令）。

## 4. 明早板验清单（用户操作）

### 4a. 基线回归（~10 分钟，可选但推荐）

确认 186154c5 CSR 基线 overlay 未受今夜工作影响（今夜未动任何
2_fpga 工程，理论必然无影响——回归是证据不是怀疑）：

1. 板卡上电，UART 打开（115200-8N1，证据窗 `tee` 到文件）；
2. 按七步重载正典（见 zynq-pynq-overlay-workflow skill /
   2026-09-18 05 日志）加载现挂 overlay；
3. 跑 CSR L1 自验（VERSION/ID 读回 + 若干 RO 寄存器抽查）；
4. 判定：读回与 2026-09-18 run05 记录一致 → BOARD_BASELINE_OK。

### 4b. 证据评审 + G2 开工决策（主要动作）

1. （可选）补跑 run07 配置 B（核视图资源/时序底线，命令在 run07 README
   尾部；勿无人值守重跑 A/C——A 结论已封闭，C 内存代价同 A）；
2. 评审 run06（三档 PASS + TAILW 死锁修复记录）与 run07 README；
3. 决策 G2 开工（数据已在 §2：功能缓冲 590k FF 物理不可容纳，
   G2 是唯一路径）；
4. 若决策通过：按 `7_logs/2026-09-19/04_next_start_guide.md` 启动 G2 会话。

### 4c. 明确不做

- 不加载任何今夜新生成的比特流（今夜未生成，也不应生成——
  G2/G4 未过门，上板即违反门控纪律）；
- 不动 CSR 已验证 RTL 与冻结工程。

## 5. GEMM 上板验收标准（G7 时回看）

1. G2 门：bank 版阵列 run06 阶段矩阵全 PASS + 综合无 294912 类
   FF 爆炸（BRAM 32 块量级）+ 时序不劣于 run07 配置 B 底线；
2. G4 门：CSR-阵列联合仿真门（加载→启动→回收全链对拍）；
3. 板级：PS 加载真实层 W/X/LUT → 跑一个真 tile → y 与软件
   golden 位级一致（延续 G0 复放方法论）→ 再谈吞吐。
