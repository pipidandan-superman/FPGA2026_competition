# 05 — RNE 合同修复 + PS 运行时离线 PASS（2026-09-15 续）

## 摘要

PS 侧 numpy 运行时离线自检 **PS_RUNTIME_OFFLINE_PASS**（128/128 帧原始
INT8 头逐字节一致 + 解码精确一致）。达成过程中发现并修复 G2 的两个缺陷
（b_off 导出偏移 4×；rne_shift NEP50 shift-dtype 溢出），量化重跑为真 RNE
合同（run02/03/04）。**G3/RTL 的整数合同自此才真正冻结为可复现语义。**

## 发现的两个 G2 缺陷

1. `run_g2_quant.py` 导出 `bo += nd.b_q.nbytes * 4` → quant.json 全部
   b_off 越界（bias.bin 本体正确）。修复：去掉 `* 4`。
2. `np.frexp` 指数 np.int32 → `1 << np.int32(41)` NEP50 下回绕 0 →
   rne_shift 平局阈值失效 → shift≥32（全网 conv 通道）RNE 退化为非零余数
   远离零进位（+0.5LSB 均值偏置）。run01 的全部数值（golden/mAP/回归
   哈希）均带此偏置产出，与文档化 RNE 合同不符，仅作历史记录。
   修复：`rne_shift` 入口 `s = int(s)`（intref + pynq/intarith 同步），
   单测补 s=41 手算 + np.int32 A/B 回归。

诊断方法存档（复用价值）：golden npz 逐节点反演 → 首差定位 model.0 →
包重算与 golden 差值直方图 {0,+1} 各半、均值 0.5129 → 同进程探针
（`2026-09-15_yolo7020_ps_runtime_run01/probe_g2state/`）证明状态一致、
仅 shift 类型不同 → A/B 一行代码复现（`1 << np.int32(41) == 0`）。

## 真 RNE 重跑轨迹（valid/test drop，FP 基线 0.8939/0.7255）

| run | refit | valid | test |
|---|---|---|---|
| run01(旧,混合舍入) | 128×2 | +0.0176 | +0.0571 |
| run02 | 128×2 | +0.0288 | +0.0336 |
| run03 | 420×2 | +0.0224 | +0.0377 |
| run04 | 420×3 | **−0.0092（PASS，部署源）** | +0.0334 |

**run04 门限通过（≤0.02），部署包取 run04，离线自检对其回归集
128/128 位级一致（PS_RUNTIME_OFFLINE_PASS）。** valid npos=81（Right
类仅 10）类间 AP 摆动 ±0.13 属单检测噪声；test 在真 RNE 下系统性改善且
三轮一致（0.0334–0.0377），test 未参与任何调参（refit 仅用 G1 校准列表）。

## PS 侧资产（全部位于 2_fpga/3_yolo_zynq）

- `pynq/yolo_pkg.py` — 包加载（偏移布局 = 修复后语义）
- `pynq/gen_schedule.py` — PC 一次性编译 → schedule.json（104 tasks）
- `pynq/yolo_runtime.py` — numpy 解释器（im2col+int32 GEMM+每通道 requant+LUT）
- `pynq/intarith.py` — 整数原语权威副本（含 shift 归一）
- `pynq/yolo_decode.py` — float64 DFL+NMS
- `rom_data/` — 部署包 + schedule（以最终选定 run 同步）

证据：`4_metrics/logs/2026-09-15_yolo7020_ps_runtime_run01/`
（REPORT.md、console.log、offline_check.json、debug/probe 工件）；
量化重跑：`2026-09-15_yolo7020_g2_quant_rne_run02/03/04`；
run01 增补：`ADDENDUM_2026-09-15_rne_and_boff_bugs.md`。

## 边界重申

- 2_fpga 冻结区只有 3_yolo_zynq 可写；0_diaplay_test 只读借用。
- 测试集不参与调参（run02-04 的 refit 只用 G1 校准列表）。
- 板卡加载/重新配置仍需用户单独授权（未发生）。
