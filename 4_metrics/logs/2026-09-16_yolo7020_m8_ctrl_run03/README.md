# M8 ctrl V1.2 门重跑（run03）—— S_RQ 等待态 rq_rdy_i（Y 写背压）

日期：2026-09-16。结果：**TB_CTRL_PASS**（run03 首跑绿，699590 周期 × 15 输出零失配，
ldone=23 / alldone=1，与 V1.1 run02 记录**逐位一致**）。

## 为什么重跑（M12 A1 前置）

A1 把 Y 输出从"TB 观测流"升级为真 AXI 写主（yolo_dma_wr，M9b 已过门）。阵列的
Y 行段化器以 req/ack 方式消费 requant 尾拍：写命令通道忙时必须反压 ctrl 的
S_RQ 推进。ctrl 升 V1.2 增等待态，按基线 §5 规则（模块改时序路径 → 从该模块的
门开始重跑）先重过 M8 门，再做阵列 V1.2。

## RTL 变更（rtl/yolo_ctrl.v V1.1 → V1.2）

- 新增输入 `rq_rdy_i`（阵列 Y 段化器的 per-output 背压）；S_RQ 体由无条件
  步进改为 `if (rq_rdy_i)` 才步进 rq_cnt_r / tile 推进。
- 等待拍 rq_en_o（S_RQ 电平解码）与 rq_idx_o（rq_cnt_r）保持稳定——
  合格的 req/ack offer（稳定数据 + 单拍 ack 语义），段化器无需重取。
- 其余逻辑零改动。`rq_rdy_i` 接高时与 V1.1 周期级相同（回归性保证）。

## TB 变更（sim/tb_yolo_ctrl.v V1.1 → 本 run 增一行）

- 仅增 `.rq_rdy_i(1'b1)` 端口连接（注释：接高 == V1.1 周期精确，回归用）。
- 激励零改动：复用 run02 的 `stim/ctrl/`（seed 808，含 drv_rdy.hex 共 22 个
  hex），重算 sha256 与 run02 记录**零失配**（见 stim_sha256.txt 对比段）。
- 待 M10 阵列 V1.2 门时 TB 换接真实段化器背压并回放 per-cycle rdy 序列
  （届时另行生门，不属本 run）。

## 一致性核验（V1.1 run02 → V1.2 run03）

| 指标 | run02（V1.1） | run03（V1.2, rq_rdy=1） |
|---|---|---|
| cycles | 699590 | 699590 |
| compared（15 输出/拍） | 699590 | 699590 |
| ldone / alldone | 23 / 1 | 23 / 1 |
| finish Time | — | 6995930 ns |

**rq_rdy_i 接高 ⇒ 周期级等价**，设计预期得到实证（等待注入路径未被本 run
激励，其正确性由后续 M10/M11 阵列门带真实背压覆盖）。

## 命令与环境

- 编译：`vlog -work work ..\..\rtl\yolo_ctrl.v ..\tb_yolo_ctrl.v`（sim/msim）
- 运行：`vsim -c -novopt +STIM=../stim/ctrl +WDT_MS=10000 -l m8_run03.log
  -do "run -all; quit -f" work.tb_yolo_ctrl`
- 环境：主机 HC-202510241838（Windows 11 企业版）；ModelSim SE-64 10.1c
  （`-c -novopt` 铁律）；RTL/TB/激励 sha256 见 stim_sha256.txt（绝对路径，
  22 stim hex + 3 源文件）。

## 证据清单

1. 本 README.md
2. console_extract.txt（PASS token 摘录）
3. m8_run03.log（原始 transcript，未编辑）
4. stim_manifest.json（沿用 run02 原件——激励未重新生成）+ stim_sha256.txt
   （本机重算，stim 部分与 run02 记录程序化对比零失配）

## 结论

ctrl V1.2 M8 门通过。S_RQ 等待态合同冻结：`rq_rdy_i` = 阵列 Y 段化器可接受
下一 requant 输出（M12 A1 wrapper 语义）。yolo_gemm_array V1.2（Y 段化器 +
u_dma_wr 实例 + y_rdy 反压）开工。
