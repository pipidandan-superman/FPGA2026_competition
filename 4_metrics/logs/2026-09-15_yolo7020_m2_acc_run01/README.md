# M2 累加器门 run01 — yolo_acc（2026-09-15）

## 结果：TB_ACC_PASS（首跑全绿，CLOSED）

57936/57936（7242 拍 × 8 lane，逐拍逐 lane 比对，零失配）。

## 工件

| 角色 | 文件 |
|---|---|
| RTL | `2_fpga/3_yolo_zynq/rtl/yolo_acc.v` V1.0 |
| TB | `2_fpga/3_yolo_zynq/sim/tb_yolo_acc.v` V1.0 |
| 激励生成器 | `2_fpga/3_yolo_zynq/sim/acc_vecgen.py` |
| 激励 | `2_fpga/3_yolo_zynq/sim/stim/acc/`（clr/en/d0..7/q0..7_exp/n_cycles + manifest） |
| 本目录 | console_extract.txt / sim_acc.log / stim_manifest_acc.json / stim_sha256.txt（20 文件） |

## 合同（架构基线 §3.2：int32、K 断点续累、清零）

- `N_LANES=8` 路独立 int32 累加器，lane l 占 `d_i/q_o[l*32 +: 32]` 扁平布线；
- `clr_i` 优先于 `en_i`（tile 起始清零，同拍 `clr&en` 以清零收场）；
- `en_i=0` 保持（K 断点：requant/drain 相位暂停，下一 K 块续累同一累加器）；
- int32 补码自然回绕（合同域 |sum| ≤ 2304·127·128 < 2^31 不会回绕，位语义仍与 numpy int32 逐位一致）；
- 异步低复位。M1 打包修正项（lane0 −w<<<7、lane1 +P[16]）由阵列包装层在 d_i 之前加，不进本模块。

## 激励设计（反退化纪律，M0 v2 模板）

| 段 | 内容 | 目的 |
|---|---|---|
| A | clr&en 同拍 1 + 小值 ramp 64 拍 | 同拍优先级证据 + 基础累加 |
| B | clr 1 → en 576（小值）→ hold 16（**全幅 d**）→ en 576 | K=576 断点续累；hold 期间巨值不得吸收 |
| C | MAX−3 +7 → MIN +3 → clr → MIN+2 −5 | 每 lane ±2^31 回绕对（8 个回绕事件定向） |
| D | 随机 6000 拍：clr 3% / en 85% / 全幅 d 10% | 密集混合 |

生成器内覆盖断言（本次实测值）：wrap=798（≥4）、hold=953（≥100）、
clr&en=139（≥1）、每 lane unique>100 且非 90% 全零。黄金 = Python
wrap32 逐拍模型（与 RTL 同优先级/同回绕），**每拍每 lane** 期望 q 落盘。

真实数据回归说明：acc 无数值参数（纯加法），合同数值正确性由 M0 门
的 golden00/02 全量回归（409600/409600，同一累加语义）覆盖——M0 的
conv 黄金链含 acc 语义端到端。本门聚焦时序合同（清零/保持/回绕/优先级）。

## 环境与复现

- ModelSim SE-64 10.1c（MGLS_LICENSE_FILE=D:/work/modelsim/win64/LICENSE.TXT）；
- vsim 必须 `-c -novopt`；`-do "run -all; quit -f"` 引号包裹；
- 复现：`python acc_vecgen.py` → `vlog -work work ../../rtl/yolo_acc.v
  ../tb_yolo_acc.v` → `vsim -c -novopt +STIM=../stim/acc +WDT_MS=200 -do
  "run -all; quit -f" work.tb_yolo_acc`（均在 sim/msim 下）。

## 过程记录

- TB V1.0 初版三处笔误在编译/加载前修正：readmemh 目标带索引不标准 →
  改起始地址参数形式；`{stim,"/d",l,...}` 整数 l 拼原始位非 ASCII →
  改 `lane_ch="0"+l`；NCYC 硬编码估计值 → 改由 `n_cycles.hex` 下发。
- 首次 vsim 加载报 `$readmemh: Argument 2 must be a memory`（integer
  不能作第二参数）→ 改经单字 memory `mem_n[0:0]` 中转。修正后一次通过。
- RTL 无改动（V1.0 原样通过）。

## 结论

M2 门通过。M10 集成注意（自 M1 延续）：阵列包装层须把 lane0 −(w<<<7)、
lane1 +P[16] 修正项并入送入 d_i 的部分和。
