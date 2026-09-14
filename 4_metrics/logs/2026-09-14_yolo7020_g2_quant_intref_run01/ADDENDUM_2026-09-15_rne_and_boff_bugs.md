# Run01 增补说明（2026-09-15，事后发现的两处缺陷记录）

本 run 的量化精度结论（valid drop +0.0176）在当时通过门限，但事后在
PS 运行时离线回归（4_metrics/logs/2026-09-15_yolo7020_ps_runtime_run01）
中发现本 run 存在两个缺陷，均已修复并重跑：

## 1. quant.json b_off 元数据 4× 虚高（导出 bug）

`run_g2_quant.py` 导出段 `bo += nd.b_q.nbytes * 4` —— b_q 为 int32，
`nbytes` 已含 ×4，再乘 4 导致所有 b_off 越界（末偏移 82512 > bias.bin
实际 21652 字节）。bias.bin 文件本体布局正确，仅 quant.json 偏移元数据
错误；本 run 自身评估走内存，未受影响。修复：`bo += nd.b_q.nbytes`。

## 2. rne_shift 的 NEP50 shift-dtype 溢出（数值合同 bug，影响全部结果）

`np.frexp` 返回的指数是 np.int32；`req_pair` 里 `shift = 31 - e` 因此是
np.int32。numpy 2.x NEP50 下 `1 << np.int32(41)` 回绕为 **0**，使
`rne_shift` 的平局阈值 `full` 变 0：对 shift ≥ 32（本网络几乎全部 conv
通道，典型 shift 39–43），RNE 退化为「非零余数即远离零进位」，均值
+0.5LSB 系统性偏置（实测与 golden 差值均值 0.5129、{0,+1} 各半完全吻合）。
Add/Concat 的 dyadic 路径 ratio≈1、shift<32，仍是真 RNE —— 即本 run 的
实际舍入语义是 shift 依赖的混合体，与文档化合同（RNE ties-to-even）不符。

单测未覆盖：14 个手算用例的 shift 全部 ∈ {0,1,2}，从未命中 ≥32 路径。

修复：`rne_shift` 入口 `s = int(s)` 归一（intref_yolov8.py 与
2_fpga/3_yolo_zynq/pynq/intarith.py 同步），并在重跑 run 的单测中加入
s=41 手算用例 + np.int32 A/B 随机回归（见 run02/run03）。

## 影响

- 本 run 的 golden npz、regression_128frames.json、mAP 数字均基于混合
  舍入语义产出，**不作为部署包来源**；其精度结论仅作历史记录。
- 修复后的合同化重跑见 `2026-09-15_yolo7020_g2_quant_rne_run02`
  （真 RNE，PS 离线回归 128/128 位级一致）及 run03（校准参数复核）。
- 部署包以修复后 run 为准（2_fpga/3_yolo_zynq/rom_data）。
