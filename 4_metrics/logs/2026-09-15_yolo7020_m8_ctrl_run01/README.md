# M8 ctrl 门 run01 — yolo_ctrl（2026-09-15）

## 结果：TB_CTRL_PASS（CLOSED，2 跑过门）

695092/695092 周期逐拍比对 15 路输出（dsc_ready/busy/acc_clr/
beat_en/k_cnt/rq_en/rq_idx/wr_bank/rd_bank/oc_tile/n_tile/n_tail/
oc_tail/layer_done/all_done），layer_done 脉冲 23、all_done 恰 1。
2271 tile、115672 K 拍、577057 requant 拍。

## 工件

| 角色 | 文件 |
|---|---|
| RTL | `2_fpga/3_yolo_zynq/rtl/yolo_ctrl.v` V1.0 |
| TB | `2_fpga/3_yolo_zynq/sim/tb_yolo_ctrl.v` V1.0 |
| 激励生成器 | `2_fpga/3_yolo_zynq/sim/ctrl_vecgen.py`（seed 808） |
| 激励 | `2_fpga/3_yolo_zynq/sim/stim/ctrl/`（5 驱动列 + 15 期望列 + n_cycles + manifest，21 hex） |
| 本目录 | console_extract.txt / sim_ctrl.log / stim_manifest.json / stim_sha256.txt |

## 合同（基线 §3.1/§5 M8 行）

- 层描述符流（oc_total/n_total/k_total/last）在 S_IDLE 接受；
- tile 循环 n 外 × oc 内：每 tile S_TILE（acc_clr 1 拍）→ S_K
  （K 拍，k_cnt 0..K−1，末拍后计数器保持 K）→ S_RQ（oc_tail×
  n_tail 拍，rq_idx = oc_local·n_tail+n_local 平铺）→ 下一 tile；
- 尾部钳位 tail_calc（末 tile 宽 = total−(tiles−1)·EDGE）；
- rd_bank 每 tile 推进翻转一次（跨层连续，全网 tile 0 读 bank0），
  wr_bank 恒为补（DMA 填非激活 bank）；
- 层末 S_LDONE：layer_done 脉冲；last 层同拍 all_done → S_IDLE；
- requant 定速为 1 输出/拍（REQUANT_UNITS 重叠定速属 M10 集成关注，
  本门只覆盖 tile/层序）；
- 输出 = 寄存器状态组合直出。

## 激励设计（23 层，覆盖 15 K 档全集 + 5 N 档全集）

| 层组 | 形状 | 目的 |
|---|---|---|
| L0 | oc16/n25600/k27 | **真实 conv0 形状回归** + N 档 25600（1600 tile） |
| L1..L15 | n=100 × K∈{27..2304} 15 档 | K 档全集 + N 档 100 + 尾 tile 4 |
| L16..L18 | n=400/1600/6400, k27 | N 档全集 |
| L19 | oc=24（2 oc tile，尾 8） | OC 尾钳位 |
| L20 | oc16/n16/k27 | 单 tile 层 |
| L21 | oc1/n1/k1 | 极小层（K=1 边界） |
| L22 | n400/k576，last=1 | 末层 all_done |

层间隔混合背靠背（0 拍）与随机 0–4 拍。黄金 = python 逐拍寄存器
影子（与 RTL case 一一对应）。生成器断言：15 K 档全集、5 N 档
全集、n_tail 事件 ≥100、oc_tail 事件 ≥50、acc_clr 数 == tile 总数
（2271）、layer_done==23、all_done==1、bank 翻转 == tiles−层数。

## 过程记录（run1 → run2）

- RTL 定稿前自查修掉一处：`tail_calc` 形参名 `edge` 是 Verilog 保留
  字（vlog 语法错级联）→ 改名 `t_edge`。
- **run1 全红（黄金发射时序惯例错位）**：黄金按"本拍驱动前状态"
  发射，而 TB 采样点在消耗本拍输入的时钟沿之后——Moore 机黄金必须
  **先 step 后发射**（后沿语义，与 wbuf/xbuf 1 拍延迟读同惯例）。
  首错 cyc=4（DUT 已进 S_TILE，黄金仍 IDLE），逐拍全错。仅改
  ctrl_vecgen.py 的 emit 顺序，RTL/TB 零改动 → run2 全绿。
  **经验：状态机黄金的发射点必须与 TB 采样窗对齐——后沿采样 ⇒
  后沿发射。**
- 生成器首版另有两处自查修掉：层运行期漏发逐拍推进（offer 后必须
  继续 emit 直到回 IDLE，否则机器永不前进）；K 档全集断言被极小层
  的 k=1 撞破（改子集判定）。

## 环境与复现

- ModelSim SE-64 10.1c（vsim 必须 `-c -novopt`；695092 周期实测
  ~1 分钟）；
- 复现：`python ctrl_vecgen.py` → `vlog -work work ../../rtl/yolo_ctrl.v
  ../tb_yolo_ctrl.v` → `vsim -c -novopt +STIM=../stim/ctrl +WDT_MS=60000
  -do "run -all; quit -f" work.tb_yolo_ctrl`（sim/msim 下）。

## 结论

M8 门通过。M10 集成注意：ctrl 的 S_RQ 相位以 rq_idx 平铺输出——
requant 尾段按 (oc_local, n_local) = divmod(rq_idx, n_tail) 解码；
W/X 缓冲 bank 由 rd_bank_o 直连；acc_clr_o/beat_en_o/k_cnt_o 接
阵列；描述符预取（当前 S_IDLE 单拍接受）如成瓶颈在 M10 加。
