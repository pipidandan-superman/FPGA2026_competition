# run07 — GEMM 16×16 阵列 OOC 综合评估（上板准备，部分完成）

- 日期：2026-09-19（凌晨自主批）
- DUT：`E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_array.sv`（V1.1）
  及其依赖链（yolo_pe_core / yolo_acc_dual / yolo_mac_cell / yolo_gemm_tail）
- 脚本：`syn_gemm_ooc.tcl`（非工程 synth_design -mode out_of_context，
  -generic 传参；create_clock + in→out false_path，内部 reg-reg 全计时）
- 控制台：`syn_console.log`（含终止记录）
- 器件：xc7z020clg484-1（EES-331）

## 终态：配置 A 中止于 RTL Optimization Phase 2 后段；B/C 未运行

宿主内存临界（Vivado 峰值 **15,155 MB**），后台综合任务被系统回收，
孤儿 vivado.exe 亦被终止以防整夜内存耗尽；util/timing 报告未生成。
按会话工具纪律**不自行重启**——B（K64 核视图，规模小、内存友好）留作
晨间第一动作（用户在场时数分钟可完成），C（150MHz 探针）可选。

## 目的与三配置（脚本保留，晨间可直接复用）

| 配置 | 参数 | 时钟 | 目的 | 状态 |
|---|---|---|---|---|
| A | P_TO=16 P_TN=16 P_KMAX=2304 | 10.000 ns (100 MHz) | 真配置可行性 + ③ 档功能缓冲代价量化 | 中止（证据已足，见下） |
| B | P_KMAX=64 | 10.000 ns | 核视图：MAC 网格+尾+FSM 本征资源/时序（G2 后参考底线） | 未运行（晨间补） |
| C | P_KMAX=2304 | 6.667 ns (150 MHz) | 数据通路时序余量探针 | 未运行（可选） |

## 关键证据（G2 立项依据，已落档）

`syn_console.log` 配置 A 综合阶段原文：

```
WARNING: [Synth 8-11357] Potential Runtime issue for 3D-RAM or RAM from Record/Structs for RAM  W_buf_reg with 294912 registers
WARNING: [Synth 8-11357] Potential Runtime issue for 3D-RAM or RAM from Record/Structs for RAM  X_buf_reg with 294912 registers
```

三点链证：

1. **映射结构**：③ 档功能缓冲是异步读 reg 阵列（cell 同拍消费
   `W_buf[r][k_abs]`），综合器既不能推 BRAM（要同步读）也不能有效推
   LUTRAM（二维索引+每行独立读口）→ 纯 FF 堆 + 巨多路器；
2. **数量**：16×2304×8×2 = **590k FF**，XC7Z020 全器件仅 106,400 FF
   ——物理不可容纳（算术结论，不依赖综合完成）；
3. **代价实测**：即便综合本身也被迫消耗 15GB 宿主内存、无法在常规
   会话内完成——功能缓冲版在工具链层面同样不可行。

结论：**这不是缺陷**——③ 档缓冲在 GEMM 手册 §6 里就是功能占位，
真 bank/ping-pong 机构即 G2 门。本 run 用综合器自己的行为把 G2 的
必要性钉死；A 配置无需重跑（结论已封闭）。

## 附带观察

- `yolo_gemm_tail` 的 `prod_r_reg[*][19..17]` 类 unused-element 警告
  （8 位移位/舍入后高位确实无扇出）属正常修剪，非缺陷；
- FSM 正确推断（`state_reg` sequential 编码消息在案）。

## 板测衔接

见 `1_docs/yolo_gemm_board_test_plan_20260919.md`：G2（真 bank）→
G4（DMA/CSR 接入）→ G7（系统综合+上板）。晨间动作：
1. （可选）补跑配置 B 取核视图资源/时序底线：`vivado.bat -mode batch
   -source syn_gemm_ooc.tcl`（B 在 A 之后自动执行；如只需 B 可临时
   注释 ooc_run A/C 两行）——建议用户在场时跑；
2. 评审本 README + 板测计划 → G2 开工决策。
