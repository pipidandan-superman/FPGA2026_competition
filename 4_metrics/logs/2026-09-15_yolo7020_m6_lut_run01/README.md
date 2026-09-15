# M6 SiLU LUT 门 run01 — yolo_silu_lut（2026-09-15）

## 结果：TB_LUT_PASS（首跑全绿，CLOSED）

1400/1400 读比对（5 张表 × 256 全索引走查 + 复访/act 旁路/保持混合），
y_o 黄金 + vld_o==en 零失配。

## 工件

| 角色 | 文件 |
|---|---|
| RTL | `2_fpga/3_yolo_zynq/rtl/yolo_silu_lut.v` V1.0 |
| TB | `2_fpga/3_yolo_zynq/sim/tb_yolo_silu_lut.v` V1.0 |
| 激励生成器 | `2_fpga/3_yolo_zynq/sim/lut_vecgen.py`（seed 606） |
| 激励 | `2_fpga/3_yolo_zynq/sim/stim/lutmod/`（op/waddr/wdata/en/act/ypre/y_exp + 表快照 + manifest） |
| 本目录 | console_extract.txt / sim_lut.log / stim_manifest_lutmod.json / stim_sha256.txt（14 文件） |

## 合同（架构基线 §3.2）

- `act=1`：`y = LUT[(y_pre + 128) & 0xFF]`——+128 折叠由 8b 无符号加法
  自然回绕实现（0x80+0x80→0x00、0x7F+0x80→0xFF），无符号性处理；
- `act=0`：`y = y_pre` 位透传（noact 层，M0 genC 类）；
- 256 项 int8 表整层共享（真实模型 lut 形状 [256]），层切换经写口重载；
- en=0 保持；vld_o=en 打一拍；同步写口；读写同址返回旧值（调度上
  装载与走查互斥，仅作语义定义）。

## 激励设计（五表 × 装载+全走查）

| 表 | 内容 | 目的 |
|---|---|---|
| real00 / real02 | conv0_golden00/02 真实 lut_i8.bin | **真实数据回归** |
| identity | lut[i]=i−128 | noact 参照 + 256 distinct（检出任何索引/折叠偏移） |
| random | seed 606 全域 int8 | 非结构值 |
| extreme | −128/127 棋盘 + 端点单调段 | 近旁敏感性（SiLU 真实表在饱和区平坦，棋盘强迫区分相邻索引） |

走查段 y_pre 从 −128 到 127 升序全覆盖（256 全索引，基线要求）+
24 复访随机点；8% 保持、8% act 旁路交错。装载段 256 连写走**写口**
（写路径同时受验；表快照 hex 落盘供审计对照）。

生成器内断言：每表 distinct≥8、identity=256、hold≥16、act0≥16
（实测 hold=84、act0=141）。

## 环境与复现

- ModelSim SE-64 10.1c（vsim 必须 `-c -novopt`）；
- 复现：`python lut_vecgen.py` → `vlog -work work ../../rtl/yolo_silu_lut.v
  ../tb_yolo_silu_lut.v` → `vsim -c -novopt +STIM=../stim/lutmod +WDT_MS=200
  -do "run -all; quit -f" work.tb_yolo_silu_lut`（sim/msim 下）。

## 过程记录

- RTL 初版 `ZP_OFF[AW-1:0]` 参数直接位选是 SystemVerilog 语法，
  Verilog-2001 不允许——编译前改为 wire 中转（本轮工具链铁律的又一例）。
- 其余一次通过；RTL 未再改动。

## 结论

M6 门通过。M10 集成注意：层切换时先重载 LUT 再放行 requant 尾段
（读写相位互斥由 ctrl 保证）；noact 层置 act=0 即可复用本模块。
