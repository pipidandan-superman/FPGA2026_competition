# 2026-09-16 yolo7020 M1 PE 双打包乘法 门（run02，xsim + V1.1 源语版）

## 目标
M12 B0（OOC 综合适配检查）首跑失败的修复门：`yolo_pe_pack` 乘法从
RTL 推断改为 **DSP48E1 源语直例**（V1.1）后，在**官方 unisim 模型 +
Vivado 自带仿真器 xsim** 上重跑 M1 冻结门，确认与 run01（ModelSim、
V1.0 推断版）逐位一致。数值合同不变：p0=w·x0、p1=w·x1 精确。

## 背景（为什么重跑）
B0 首跑（ooc_run01，2026-09-16）DSP 238/220 超限：Vivado 2025.2 把
推断式 25×18 打包乘法**拆解成两个独立 8 位通道乘法器**（多数 PE 每
个 2 DSP，阵列 228 DSP；证据链 ooc_dbg1/2/3 + DSP Preliminary Mapping
Report）。修复 = 直接例化 DSP48E1 源语锁定每 PE 恰 1 个 DSP，配置
OPMODE=7'b0000101 / ALUMODE=4'b0000 / INMODE=5'b00000、全部流水
寄存器旁路（AREG..PREG=0），组合路径、契约与位布局不变。该配置先在
proj/xsim_smoke/tb_xsom_dsp48.v 用官方模型穷举角点验证
（XSOM_DSP48E1_PASS 11264/11264）。

## 结果

**TB_PE_PACK_PASS compared=10216/10216**（与 run01 同一冻结激励集：
216 定向角点 + 10000 随机）。源语版与 Python 位模型零差异，M1 门
对 V1.1 继续成立。

## 仿真器切换（ModelSim → xsim，用户指示）
本 run 起仿真主路径 = Vivado xsim（官方 unisim/IP 模型，免手工
适配）。命令（自 sim/xsim）：
```
xvlog.bat ../../rtl/yolo_pe_pack.v ../tb_yolo_pe_pack.v \
  <vivado>/data/verilog/src/glbl.v
xelab.bat tb_yolo_pe_pack glbl -s snap_m1 \
  -L unisim -L unisims_ver -timescale 1ns/1ps
xsim.bat snap_m1 -R
```
预编译库位置 `<vivado>/data/xsim/ip/`（unisim 等）。

### xsim/unisim 坑（已入 TB V1.1 头注）
unisim `DSP48E1.v` 模型在仿真前 100ns 门控其 OPMODE 多路选择
（源码 `$time > 100000` 判据，`#100010 ping_opmode_drc_check`），
此前 P 不可靠。tb_yolo_pe_pack V1.1 在首比较前插入 2µs 空闲
（`#2000`）。xsim 烟雾测试（counter + DSP48E1 穷举角点）先行通过
（proj/xsim_smoke/，XSOM_COUNTER_PASS / XSOM_DSP48E1_PASS）。

## 零漂移声明
激励 = run01 同一文件（sha256 逐一相符，见 stim_sha256.txt 与
console_extract.txt 尾部对照）；期望零改动。DUT 变更仅：
- `rtl/yolo_pe_pack.v` V1.0 → V1.1（DSP48E1 直例，新增 clk_i 端口，
  无内部使能寄存）
- `rtl/yolo_gemm_array.v` V1.2 → V1.2b（u_pe 实例补 .clk_i）
- `sim/tb_yolo_pe_pack.v` V1.0 → V1.1（clk_i + 2µs 热身 + 头注）

## 环境
- xsim（Vivado 2025.2，F:\vivado2025）；unisim/unisims_ver 预编译库
- 原始日志：m1_xvlog.log / m1_xelab.log / m1_xsim.log（本目录）
- 上游证据：2026-09-15_yolo7020_m1_pe_pack_run01（V1.0 基准 PASS
  10216/10216 + 2^24 穷举证明）；proj/ooc_gate/ooc_run01_vivado.log
  （失败链，保留不改写）
