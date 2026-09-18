# 2026-09-18 run02 —— 单 PE RTL 仿真：GATE PASS + 256³ 全穷举 PASS，① 收口

> 2026-09-18 迁移记录：RTL 自 rtl_pe/ 迁至 rtl/GEMM/（用户指定目录，后续 GEMM 相关代码统一放此）。tcl 路径已同步，迁移后三个门仿真重跑全 PASS 且 checks 数逐字节一致。

## 对象

- DUT：`E:/competition/2_fpga/3_yolo_zynq/rtl/GEMM/yolo_pe_core.sv`（新建，单 PE 包装：
  实例化只读参考 `rtl/yolo_pe_pack.v` V1.2 已证 DSP48E1 双乘打包原语 +
  3 级 valid/mask 边带流水，满足 PE 手册 §5 接口 clk_i/rst_i/in_valid_i/
  w_i/x0_i/x1_i[7:0]signed/lane_mask_i[1:0] → out_valid_o/p0_o/p1_o[16:0]/
  lane_mask_o[1:0]，无 out_ready，固定运转流水）
- TB：`rtl/GEMM/tb/tb_yolo_pe_core.sv`（手册 §10 单 PE 门行全覆盖）

## 判决独立原则（手册 §10）

期望值永不取自被测打包公式：定向相位用 run01 软件oracle 金文件
`golden_pe.hex`（76 向量），其余相位用 TB 内独立符号乘 `w*x`。
延迟用三级期望镜像逐周期核对：任何周期 `out_valid_o ≠ exp_v3` 即报错
（D→D+3 逐笔钉死，早一拍晚一拍都抓）。

## GATE 模式结果：PASS（gate_console.log）

```
EES_PE_INFO golden loaded: 76 vectors .../run01/golden_pe.hex
EES_PE_INFO mode=GATE issued=140912 published=140909 checks=140909 lat_err=0
EES_SUMMARY checks=140909 errors=0
EES_VIVADO_RESULT PASS
```

- issued−published = 3：恰为 P6(2)+P7(1) 复位击杀的在途笔，守恒精确（无重发/丢失/陈旧发表）
- lat_err=0：每笔发表周期标签 Δ=3，延迟契约逐笔成立
- 76 金向量（oracle 位级交叉）+ 1000 角点网格（含 −128/−127/±1/0/+127）+
  4 掩码扫描 + 200k 随机流（~30% 空拍、每 16 拍注入角点、随机掩码）全逐位相等
- P6/P7 复位中填充/中排空：被击杀笔永不发表；复位后首个 marker 笔正确
- P8 冻结输入空拍 5 拍：无陈旧数据重发

## FULL 256³ 穷举：PASS（full_console.log，退出码 0）

```
EES_PE_INFO mode=FULL_EXH issued=16778411 published=16778408 checks=16778408 lat_err=0
EES_SUMMARY checks=16778408 errors=0
EES_VIVADO_RESULT PASS
```

手册 §10 数学穷举行闭合：**全部 256³=16,777,216 个 (w,x0,x1) 三元组**
（含 −128×−128×−128 等每个极端值）连续流过 DUT，与 TB 独立符号乘**逐位相等**，
0 失配、lat_err=0。进度点 w_idx=0/16/…/240 每 16 个 w 值一打，块间增量恰
1,048,576=16×256²（首块 −3 为流水在途，账目自洽）。

**总账逐笔闭合（整数零残差）**：

| 相位 | issues | published |
|---|---|---|
| 穷举流 256³ | 16,777,216 | 16,777,216 |
| P1–P4（金76+金76+角1000+掩码32） | 1,184 | 1,184 |
| P6 复位中填充（A、B 击杀 + marker） | 3 | 1 |
| P7 复位中排空（C 击杀 + marker） | 2 | 1 |
| P8 冻结空拍（valid 保持 5 拍=同操作数重发×5 + 1） | 6 | 6 |
| **合计** | **16,778,411** | **16,778,408** |

与报告值精确相等；issued−published=3 恰为复位击杀笔，无重发丢失。
P8 的 5 拍冻结重发是设计语义（固定运转流水，valid 滤波），全部通过独立乘校验。

## 环境与坑（4 轮迭代定稿，tcl 逐版备份 vivado_*.backup.log）

- 流程：`cmd //c vivado.bat -mode batch -source sim_pe_core.tcl`（git-bash 下
  必须 `//c` 防 MSYS 路径改写）；tcl 内 `run_tool` proc 直接 `exec`
  `$env(XILINX_VIVADO)/bin/unwrapped/win64.o/{xvlog,xelab,xsim}.exe`
  （本装 vivado batch 内无 xvlog 命令）
- glbl：追加编译 `F:/vivado2025/2025.2/data/verilog/src/glbl.v` 入 work
- 双方无 timescale（含只读参考 yolo_pe_pack.v，不许改）→ xelab
  `-timescale {1ns/1ps}` 全局覆盖
- unisim 库：`-L unisims_ver -L unisim`（DSP48E1 原语真模型，其前 100ns
  mux 门控已由 TB 复位窗口 ~145ns + 首刺激 ~245ns 避开）
- 金文件：run01 `golden_pe.hex`（首行注释头，`%h %h %h %h %h %h` 六列）

## 文件

gate_console.log（GATE 全程原始输出）、full_console.log（FULL，完成后生效）、
sim_pe_core.tcl / sim_pe_core_full.tcl、xvlog/xelab/xsim 日志与 jou、
vivado*.backup.log（迭代证据）。仿真产物 xsim.dir/ 留档。

## 下一步（手册 §11 顺序）

**① 单 PE 已收口（GATE + 256³ 全穷举双 PASS）** → **② 双 INT32 累加器**
（K=1/27/576/2304 门行）→ ③ 小阵列+共享尾（golden_tail.hex）→ ④ 规模化。
勿跳手册外步骤。
