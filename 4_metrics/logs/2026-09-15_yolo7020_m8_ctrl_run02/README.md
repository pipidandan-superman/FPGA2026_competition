# M8 ctrl V1.1 门重跑（run02）—— S_TILE 等待态 tile_rdy_i

日期：2026-09-15。结果：**TB_CTRL_PASS**（run1 首跑绿，699590 周期 × 15 输出零失配，
ldone=23 / alldone=1）。

## 为什么重跑（M10 集成前置）

M10 集成发现 ctrl V1.0 缺缓冲就绪门控：每 tile DMA 装载（OC_EDGE×K 字节）远
多于 K 拍计算，S_K 若不等待会读半填充 bank——这是**正确性缺口**而非性能问题。
按基线 §5 规则（模块改数值/时序路径 → 从该模块的门开始重跑），ctrl 升 V1.1
后先重过 M8 门，再做阵列顶层。

## RTL 变更（rtl/yolo_ctrl.v V1.0 → V1.1）

- 新增输入 `tile_rdy_i`；S_TILE 体由无条件进 S_K 改为 `if (tile_rdy_i)`。
- 等待拍拉长 acc_clr_o（S_TILE 电平解码）——无害：阵列累加器 en=0 时保持 0。
- 其余逻辑零改动。`tile_rdy_i` 接高时与 V1.0 周期级相同（回归性保证）。

## 黄金/TB 变更

- `ctrl_vecgen.py`：指令级参考模型加等待建模——每 tile 进 TILE 态抽
  w∈{0..4}（rng），前 w 拍 rdy=0、随后 rdy=1 放行；rdy 逐拍记录为新列
  `drv_rdy.hex`（TB 回放同一序列）。覆盖断言更新：acc_clr 电平周期数 =
  tiles + 等待拍总数；等待拍 ≥1000 且 0 等待与 ≥3 等待 tile 均存在。
- `tb_yolo_ctrl.v` V1.1：`tile_rdy` 寄存器 + `mem_rty` 阵列 + 读
  `drv_rdy.hex` + 逐拍驱动 + `.tile_rdy_i(tile_rdy)` 端口连接。

## 一致性核验（V1.0 → V1.1 差量）

V1.0 run01 总周期 695092；V1.1 run02 总周期 699590；差 = 4498 =
本 run 等待拍总数（tile_wait_cycles=4498）——**等待注入是唯一差异源**，
层计划/tile 序列/beat/rq 计数与 V1.0 逐项相同（tiles=2271、
k_beats=115672、rq_beats=577057、bank_toggles=2248）。

## 命令与环境

- 激励：`python ctrl_vecgen.py`（seed 808，含 drv_rdy.hex 共 27 文件 +
  manifest；生成期断言全过：15 K 档/5 N 档全集、n_tail_ev/oc_tail_ev、
  等待覆盖 4498≥1000、0/长等待 tile 均存在）
- 编译：`vlog -quiet ../../rtl/yolo_ctrl.v ../tb_yolo_ctrl.v`（sim/msim）
- 运行：`vsim -c -novopt +STIM=../stim/ctrl +WDT_MS=120000
  -do "run -all; quit -f" -l <本目录>/sim_ctrl_run1.log work.tb_yolo_ctrl`
- 环境：ModelSim 10.1c（win64，MGLS_LICENSE_FILE=D:/work/modelsim/win64/
  LICENSE.TXT），Windows 11 主机，`-c -novopt` 铁律沿用。

## 证据清单

1. 本 README.md
2. console_extract.txt（PASS token 摘录）
3. sim_ctrl_run1.log（原始 transcript，未编辑）
4. stim_manifest.json + stim_sha256.txt（27 个激励文件哈希，含新
   drv_rdy.hex）

## 结论

ctrl V1.1 M8 门通过。S_TILE 等待态合同冻结：`tile_rdy_i` = tile 数据
装载完成 + 参数预取完成（M10 wrapper 语义）。M10 阵列集成可以开工
（yolo_gemm_array.v 用 ctrl V1.1 实例）。
