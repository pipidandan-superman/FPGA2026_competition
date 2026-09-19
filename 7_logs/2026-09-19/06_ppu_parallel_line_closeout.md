# 06 PPU 非线性算子并行线收官 + 迁移注记（2026-09-18 夜 → 09-19 晨）

> **迁移注记**：本线隔夜工作产物原落
> `E:\competition\2_fpga\parallel_task\`（用户隔夜授权的防撞暂存区），
> 2026-09-19 晨经用户指令迁入主树。本文件为该线工程日志并入件
> （当日 01-04 四件套属 GEMM 线，未改动；本线以编号文件并入）。
> `parallel_task\` 原样保留为归档，不再更新。

## 一、本线概况（01/02 对应内容）

- 用户隔夜授权：全部产物入 parallel_task 防撞，迁移待各 agent 收口后
  由用户主导；遵守 skill 准则（证据四件套、vsim -c -novopt、
  ModelSim 机器级 ≤2 本线恒 1）。
- 任务：YOLOv8n 图算子（PPU）线，与 PE/GEMM 线并行——GEMM 线做
  conv 主干，本线做 requant/upsample2/maxpool5/add/xfer(view 零拷贝
  无 RTL)。
- 执行序：P0 手册+ABI 事实核验 → P1 oracle 回放 → P2a-e 五算子
  RTL 门 → 手册 §7 注记 → 本迁移。
- 风险控制：不触主树、不触 GEMM 线文件、共享契约变更走手册 §10
  （本夜无变更）、TDP BRAM 规则不涉（五引擎纯流式无 BRAM）。

## 二、验证总表（03 对应内容，全部门 PASS）

| 门 | 内容 | 结果 |
|---|---|---|
| P0 | 手册+ABI 事实核验 | **PPU_ABI_FACTCHECK_PASS 28/28** |
| P1 | oracle 全图回放对软件 golden | **PPU_ORACLE_PASS**（5×53=265 位级 0 失配） |
| P2a | requant 核 RTL 门 | **EES_MODELSIM_RESULT PASS** checks=11043 |
| P2b | upsample2 核 RTL 门 | **PASS** checks=643001 |
| P2c | maxpool5（pad 物化≡位掩码双模型交叉） | **PASS** checks=13962 |
| P2d | add（int64 不逐路饱和→int32 合同截断） | **PASS** checks=12679 lat_err=0 |
| P2e | xfer（恒等捷径≡全量 requant 钉死） | **PASS** checks=2842 lat_err=0 |

期望三源独立：金文件=ppu_oracle（P1 对软件 golden 闭环）‖ TB 模型
=截断除+floor 修正（与 DUT 移位+掩码不同构）装载期交叉 ‖ 运行期
DUT≡金逐拍（posedge 三级镜像记分板，vsim/xsim 调度序无关）。
反退化配额生成期断言全过（平局/饱和/死通道/恒等/s 全 63 档）。

## 三、迁移后落位（最终绝对路径）

| 类别 | 位置 |
|---|---|
| RTL 核（每算子一夹） | `E:\competition\2_fpga\3_yolo_zynq\rtl\PPU\{requant,upsample2,maxpool5,add,xfer}\yolo_ppu_*.sv` |
| TB（集中） | `E:\competition\2_fpga\3_yolo_zynq\rtl\PPU\tb\tb_yolo_ppu_*.sv` ×5 |
| vecgen + oracle（平铺） | `E:\competition\2_fpga\3_yolo_zynq\sim\ppu_*_vecgen.py` ×5 + `ppu_oracle.py` |
| 设计手册（ABI 冻结 V1.0） | `E:\competition\1_docs\yolo_ppu_design_manual_20260918.md` |
| 证据七 run 目录 | `E:\competition\4_metrics\logs\2026-09-1{8,9}_yolo_ppu_*_run01\` |
| 本日志 | `E:\competition\7_logs\2026-09-19\06_ppu_parallel_line_closeout.md` |

vecgen 的 oracle 导入已改为 sim\ 本目录（oracle 平铺同目录）；
rom_data 绝对路径原就指向主树，无需改。

## 四、下一步（04 对应内容，PPU 线部分）

1. **P3 已撤销独立门（2026-09-19 用户决策）**：schedule.json 邻接反查
   ——41 任务 = 16 view（零拷贝无 RTL）+ 25 引擎任务，其中 16 个输入
   全直连 conv 输出（64%），仅 9 个存在引擎→引擎输入且全为 DDR 缓冲级
   耦合（add→concat ×4 / add→add ×2 / maxpool5×3→concat（SPPF）/
   upsample2→concat ×2）；PPU-only 集成 = 自写 walker + 自写 BFM 复放
   P2 已钉死数值，conv↔图算子真合同（缓冲布局/生命周期/requant 分工）
   不存在于单验。手册 §7 已加撤销注记（权威），§10 D2 对表时机同步改
2. **P4/G5 双线汇合**（= PPU 线下一门）：convs=63 + 图算子 41 + heads
   全网对软件 golden，与 GEMM 线协调启动，不单方；walker/描述符译码
   并入 GEMM 线 G4 共定合同后实现；41 任务回放留作 bring-up 二分
   调试工具（oracle 层，无 RTL 集成 TB）
3. 综合/时序/资源与板测：P4/G5 之后
4. 注意：`rtl\yolo_requant.v`（GEMM 线 conv 尾 requant）与
   `rtl\PPU\requant\yolo_ppu_requant.sv` 同义不同物，勿混用

## 五、首跑教训沉淀（详见各 run README）

- 数据链/有效链级数必须对齐（P2e：旁路链 4 级 vs 有效链 3 级 → 滞后
  一拍而 y_valid 无延迟错）
- 传输判定用 posedge 镜像 mv1（末拍后 ready 已落 0，negedge 事后采样
  必漏末拍）
- 引擎 profile 任务级 → 金文件按 profile 分组多任务布局
- 平局构造域：m∈[1,2^31)、q0∈0..3、s≤37；奇 M 段内全平局
  x≡2^(s-1) (mod 2^s)
- 失败跑 console 先另存再重跑（P2e 教训②）
