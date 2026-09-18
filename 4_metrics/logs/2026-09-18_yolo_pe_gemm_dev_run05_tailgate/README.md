# run05 — GEMM 共享尾门（③a，手册 §8 全链）

- 日期：2026-09-18（补记 README 2026-09-19）
- DUT：`E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_gemm_tail.sv`（R=1）
- TB：`E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/tb/tb_yolo_gemm_tail.sv`
- 脚本：`sim_gemm_tail.tcl`（xvlog/xelab/xsim 直调，无工程）
- 原始控制台：`tail_console.log`

## 结论

**PASS** —— `EES_SUMMARY checks=713 errors=0 lat_err=0`，
`driven=704 y=703 flushed=1 last_seen=2`，`EES_VIVADO_RESULT PASS`。

## 被测契约（GEMM 手册 §8，冻结次序）

```
sum  = acc + bias_eff            33 位有符号（bias_eff 已含首层 +128Σw 修正，
                                 硬件在所有 K 块之后只加一次）
prod = sum × M                   64 位
RNE  q=floor(prod/2^s), r=prod−q·2^s；
     r>2^(s−1) 或 (r==2^(s−1) 且 q 奇) 进位（ties-to-even）；
     s==0 整段旁路（不移位不舍入）
sat  双侧饱和 INT8
LUT  addr = sat+128（有符号+128，非补码原字节）；act_en=0 线性旁路
```

时序：元素 D 拍喂入 → y 于 D+3 拍呈现（sum/prod/RNE+sat+LUT 三级）。
参数（bias/M/shift）随元素入流水，驱动方可次拍即改。

## 期望值来源（手册 §14 双向交叉）

- 软件 golden 向量：`tb_yolo_gemm_tail.sv` 内嵌 10 组（模型↔golden 对拍 + DUT↔模型对拍）；
- TB 独立 requant 模型：截断除 + floor 修正 + RNE（与 DUT 的移位/掩码法**不同构**）。

## 阶段与判定

| 阶段 | 内容 | 结果 |
|---|---|---|
| T0 GOLDEN | 10 向量，模型↔golden + DUT↔模型 | PASS |
| T1 TIE_EVEN | s=1/s=2 平局双奇偶（含 −0.5→0） | PASS |
| T2 SAT/EXTREME | 饱和 + shift 扫 0..62 | PASS |
| T3 LUT_ADDR | 图样 A(i^A5)，addr 0/255 轨 | PASS |
| T4 STREAM | 400 背靠背 + 20% 气泡，末拍标记 | PASS |
| T5 GAPS + RSTKILL | 间隙流 + 在飞 rst 击杀 flushed=1 | PASS |

## 纪律要点（本 run 固化的 TB 技术）

- **检查器侧打时戳**：`dtags/dwp` 与观测 y_valid 同一 always 块采样，
  避免任务/检查器调度相位差造成 lat 差一（修复过程见下）；
- rst 用 `rst_d`（posedge 采样延迟副本）判幂等，规避同沿竞争；
- 守恒 `driven = y + flushed`；
- X 绷线：y 任何位 X 即报错。

## 调试记录（终态前的两次失败）

1. **lat 差一**：任务侧 tag 读取与检查器侧观测分处不同调度相位 → cyc−tag=4（期望 3）。
   修复：时戳全部移到检查器侧。lat_err=0。
2. **X 连坐（805 错）**：`{$random(rs3)} % 28'h10000000` —— 2^28 不含于 28 位，
   字面量截断为 0，模零得 X，T4 全部 bias 污染。修复：
   `% 32'h08000000 - 32'sh04000000`。教训：**模数必须用不截断的宽度书写**。
3. **golden 解析**：golden hex 的 shift 列是十六进制（"1e"=30），`$sscanf %d` 遇
   'e' 停止且残渣被下一个 `%h` 吞掉 → 模型↔golden 5 向量假错。修复：五列全 `%h`。
4. **打包端口重整回归（296 错）**：有符号打包数组 `acc_i[i]` 变索引选择被 xsim
   按无符号处理，负数走 +127 轨。修复：使用点显式 `$signed()`。
   教训：**xsim 打包数组变索引元素选择不继承符号性**。

## 下一步

③b/④ 阵列门（run06）：本尾以 R=1 单例共享挂接阵列。
