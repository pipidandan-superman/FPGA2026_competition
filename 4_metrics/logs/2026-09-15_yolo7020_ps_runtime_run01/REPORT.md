# PS 运行时离线自检报告 — 2026-09-15_yolo7020_ps_runtime_run01

## 结论

**PS_RUNTIME_OFFLINE_PASS**：`rom_data` 部署包 + `schedule.json` +
numpy-only 执行器，对 G2 真-RNE 回归集 **128/128 帧原始 INT8 头逐字节一致
（raw_head_sha256 相等）、128/128 帧解码（框 2dp / 置信 4dp / 类别）精确相等**。
包自包含性（manifest 4/4 哈希核对）与无 torch 依赖（板上可跑）同时成立。

## 达成路径上发现并修复的两个 G2 缺陷

本 run 的离线自检最初 0/128 全不一致，顺藤摸出两个上游 bug（详见
`2026-09-14_yolo7020_g2_quant_intref_run01/ADDENDUM_2026-09-15_rne_and_boff_bugs.md`）：

1. **quant.json b_off 4× 虚高**：导出段 `bo += nd.b_q.nbytes * 4`（int32
   nbytes 已含 ×4）→ 所有偏移越界（末偏移 82512 > bias.bin 21652B）。
   bias.bin 布局本身正确，仅元数据错。修复 = 去掉 `* 4`。
2. **rne_shift NEP50 shift-dtype 溢出（根因，影响全部数值）**：
   `np.frexp` 指数是 np.int32，`1 << np.int32(41)` 回绕为 0 → 平局阈值
   `full=0` → shift≥32（本网几乎全部 conv 通道，shift 39–43）下 RNE 退化
   为「非零余数远离零进位」（均值 +0.5LSB）。诊断指纹：golden 与包重算
   差值直方图 {0: 266023, +1: 127600, +2: 12272, −1: 3705}，均值 0.5129，
   与该退化模式的解析期望 0.5 吻合；同进程探针
   （`probe_g2state/`）证明节点状态与导出字节完全一致、int_forward 与
   golden 完全一致，差异仅在 rne_shift 收到的 shift 类型。
   修复 = `rne_shift` 入口 `s = int(s)`（intref 与 pynq/intarith 同步），
   并加入 s=41 手算用例 + np.int32 A/B 随机回归单测。

## 修复后的量化精度状态（真 RNE 合同）

| run | 舍入 | refit | valid drop | test drop | 备注 |
|---|---|---|---|---|---|
| run01 (09-14) | 混合（≥32 退化） | 128×2 | **+0.0176** | +0.0571 | 含 bug，仅历史记录 |
| run02 | 真 RNE | 128×2 | +0.0288 | +0.0336 | 合同化，PS 离线 PASS 基准 |
| run03 | 真 RNE | 420×2 | +0.0224 | +0.0377 | 全量校准 LSQ |
| run04 | 真 RNE | 420×3 | **−0.0092（PASS）** | +0.0334 | **部署源** |

run04 门限判定：valid drop −0.0092 ≤ 0.02 通过（INT8 0.9031 略超 FP
0.8939，npos=81 小分割噪声范围内；test +0.0334 与 run02/03 的
0.0336/0.0377 稳定一致——test 未参与任何调参，refit 仅用 G1 校准列表）。
第三轮 refit 在真 RNE 收敛比 ~0.995/iter 下安全（旧「×3 过收缩」结论
属于偏置世界 4%/iter 的机制，不适用）。

## 部署包状态

- `2_fpga/3_yolo_zynq/rom_data/`：weights.bin / bias.bin / lut.bin /
  quant.json / manifest.json + schedule.json —— **源 = run04（门限通过）**，
  本 run 目录离线自检对 run04 回归集 128/128 位级一致后冻结。
- 执行链：`pynq/yolo_pkg.py`（包加载）→ `pynq/gen_schedule.py`（PC 侧
  一次性编译，104 tasks/104 buffers）→ `pynq/yolo_runtime.py`（numpy
  解释器）→ `pynq/yolo_decode.py`（float64 DFL+NMS）。
- `intarith.py` 为 PS/RTL 共用整数原语的唯一权威副本（含 shift 归一）。

## 工件清单（本 run 目录）

- `run_offline_check.py` — 三段式自检（哈希 / 逐字节头 / 解码）
- `console.log` + `offline_check.json` — PASS 证据
- `debug_first_diff.py` — golden 逐节点首差定位
- `pre_rerun_sha256.txt` — run01 重跑前后哈希快照（证明确定性）
- `probe_g2state/` — 同进程状态探针（root-cause 定位的决定性证据）

## 下一步（G3 前置）

1. 以最终选定 run 重跑 `run_offline_check.py` 固化 PASS 证据（若换包）。
2. 硬件合同模块：解析 0_diaplay_test HWH 提取空闲地址段（G3 §10.3）。
3. 单模块 RTL（首层 conv）vs golden 逐位比对开发。
