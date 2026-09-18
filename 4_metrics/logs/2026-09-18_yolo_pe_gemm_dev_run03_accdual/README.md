# run03 — 手册② 双 INT32 累加器独立仿真（GATE PASS）

> 2026-09-18 迁移记录：RTL 自 rtl_pe/ 迁至 rtl/GEMM/（用户指定目录，后续 GEMM 相关代码统一放此）。tcl 路径已同步，迁移后三个门仿真重跑全 PASS 且 checks 数逐字节一致。

日期：2026-09-18。PE 手册第 10 节累加器行 · 手册步骤②独立验证级。
上游：① 单 PE RTL 已双 PASS（[run02](../2026-09-18_yolo_pe_gemm_dev_run02_singlepe/)）。

## 结果

```
EES_SUMMARY checks=169025 errors=0
EES_VIVADO_RESULT PASS
EES_ACC_INFO tiles started=231 done=228 aborted=3   （231-3=228 守恒 ✓）
EES_ACC_INFO A8 manual s8 bound pinned: 37748736    （2304×128×128 手册 §8 界）
```

逐相 tally（每相结束打印，增量闭合到零残差）：

| phase | started | done | aborted | 增量说明 |
|---|---|---|---|---|
| A1_K_SWEEP | 5 | 5 | 0 | K=1/27/32/576/2304 连续 tile |
| A2_RESUME_2304 | 6 | 6 | 0 | [576,1152,576] 空闲断点续累 |
| A2_RESUME_64_IRREG | 7 | 7 | 0 | [1,1,27,1,34] 不规则分块 |
| A3_CLEAR_RESTART | 10 | 9 | 1 | 50 拍中途 clr 击杀 + 27 拍完整 + done 后空闲 clr + clr 后紧接 K=1 + A3c clr/valid 同沿优先级探针 |
| A4_MASK | 17 | 16 | 1 | 掩码 01/10/11、背靠背再激活、K=1 掩 lane |
| A5_STALL | 18 | 17 | 1 | 25% 空闲拍 + valid=0 裸 last_k（无 done） |
| A6_RESET_MID | 22 | 19 | 3 | 1000 拍中途 rst 击杀 + 末拍沿 rst 击杀（复位优先杀末乘积）+ 各自后续新 tile |
| A7_K1_CORNER | 27 | 24 | 3 | 5 组 K=1 角点（first_k=last_k 同拍） |
| A8_EXTREME_SUM | 31 | 28 | 3 | +37748736 字面钉死 / −37748736 / 17 位端口宽应力 / 交替号 |
| A9_RANDOM_TILES | 231 | 228 | 3 | 200 随机 tile（K∈{1,27,32,576,2304}、tile 常量掩码、gap 0..5 半数背靠背、20% tile 内空闲、每 16 拍角点注入） |

## DUT 与手册条款对照（rtl/GEMM/yolo_acc_dual.sv）

| 设计点 | 手册依据 |
|---|---|
| 输入为已解包修正乘积 p0/p1（17 位有符号），绝不见打包 P | PE 手册 §3（禁跨 K 累加打包 P，防跨 lane 进位） |
| 符号扩展 17→32 在加法**之前** | PE 手册 §2 |
| first_k 拍执行 acc=p（免 clr+en 同沿丢首项） | PE 手册 §7 |
| K 分块边界 = in_valid=0 空闲拍，续块不带 first_k | 手册断点续累语义 |
| lane_mask 逐 lane 门控、tile 常量；掩 lane 保旧值不出账 | PE 手册 §7（结构化 OC/N 尾） |
| last_k 落账后一拍 acc_done_o 脉冲 | GEMM 手册 §5 DRAIN_PE 离开条件 |
| INT32 自然回绕（契约域 K≤2304 界 37748736 ≪ 2³¹，域外导出时拒绝） | PE 手册 §8 |
| clr_i 同步 tile 级清零、优先于累加；阵列须先停发排空再置位 | GEMM 手册 §5（计数器在阵列级） |
| FF+fabric 加法器基线（每拍更新的计算态，非寄存器表） | PE 手册 §6 |

## TB 架构（rtl/GEMM/tb/tb_yolo_acc_dual.sv）

- **独立 INT64 oracle**：eacc0/eacc1 在驱动点用 64 位加法更新，永不读 DUT；过门要求 DUT INT32 ≡ sext64(oracle) 逐位相等（GEMM 手册 §14 更宽独立 oracle 规则——契约域内任何回绕都会失配）。
- **每拍不变量**（每个受检 negedge 一处进程全覆盖）：活动 lane 对 oracle、掩 lane 对 first_k 快照、done 对 posedge 镜像 exp_done_r 逐拍精确、守恒 done = started − aborted。
- **驱动纪律**：arm 到结束每个 negedge 都驱动（gapn()）；裸 `@(negedge)` 间隙会让 in_valid=1 泄漏重采样。
- **X 绊线**：beat() 入口 `^q === x` 即报错——X 同时进 oracle 与 DUT 时 4 态比较空真通过，必须显式防。

## 调试记录（3 次失败运行 → PASS，教训入库）

1. **Run1 守恒失配** started=152 done=149 aborted=4（数值全对）：两个 TB 自伤，与 DUT 无关。
2. **Bug A（K=1 记账）**：K=1 tile 的 start/done 镜像同拍出现，旧 checker 先记 done 后记 start，active_tile 悬 1，下一相 clr 误记 1 次 abort。修复：start 置位优先判 done 同拍（K=1 同拍完成→active=0）。
3. **Bug B（$random 符号陷阱，一石二鸟）**：`r32 = {$random(seed)}; idx = r32 % N` 是伪习惯用法——拼接结果赋回**有符号** integer 后又变负数 → `Ks[r32 % 5]` 负索引得 X → 内循环零迭代 → 79 个 tile 凭空消失；gap 同理得负。更险的是 `corners[r32 % 8]` 的 X 流进 oracle 与 DUT 两侧，`!==` 对双侧 X **空真通过**（静默漏洞）。修复：模运算直接在无符号拼接表达式上算 `{$random(seed)} % N`，并加 X 绊线。
   - 正确写法：`kk = Ks[{$random(rs1)} % 5];`、`gap = {$random(rs3)} % 6;`、`corners[{$random(rs3)} % 8]`。

## 环境/复现

- 纯 fabric RTL（无 unisim/glbl/DSP 原语）：`xvlog -sv dut tb` → `xelab -debug off -timescale 1ns/1ps -s tb_acc_dual` → `xsim tb_acc_dual -runall`。
- 运行：`cmd //c "F:\vivado2025\2025.2\Vivado\bin\vivado.bat -mode batch -source sim_acc_dual.tcl -notrace -nojournal" > acc_console.log 2>&1`（xsim 经 tcl exec 输出缓冲至结束，属正常）。
- 证据：`acc_console.log`（本次 PASS 完整原始输出）、`sim_acc_dual.tcl`。

## 文件

- `E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_acc_dual.sv` — ② DUT（新目录 rtl/GEMM/，未触碰冻结 2_fpga 既有文件）
- `E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_acc_dual.sv` — ② 门 TB

## 下一步（用户已确认的验证流）

② 独立 PASS → **级 2：PE+acc 联合 MAC 仿真**（真 DSP48E1 乘积流入真累加器，E3 对齐 + first_k/last_k 边带，期望 = TB 独立乘后 INT64 累加，扩展①延迟计分板）→ ③ 小阵列 + 共享尾（golden_tail.hex）→ ④ 8×16/16×16 参数化。勿以理论下界替代综合/时序/板测。
