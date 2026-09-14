# G2 软件侧量化推理 + HWINT 整数参考 + golden 包｜REPORT

- Run：`4_metrics/logs/2026-09-14_yolo7020_g2_quant_intref_run01`（工作跨 2026-09-14 至 09-15，最终门限通过轮完成于 09-15 00:5x）
- 依据：部署计划 r3 §4.2（W8A8 数值合同）、§4.6、§12.2；G2 门限 = 量化后 valid mAP50 下降 ≤ 0.02
- 输入：`3_host/model/best.pt`、v6 数据集（1765/59/69）、G1 `calibration_list.txt`（420 图，训练集内）
- 结论：**G2_QUANT_INTREF_PASS（valid drop +0.0176 ≤ 0.02，manifest status=CANDIDATE）**

## 1. 最终精度

| split | FP32 mAP50 | INT8 mAP50 | drop |
| --- | --- | --- | --- |
| valid（门限判据） | 0.8939 | 0.8763 | **+0.0176** ✅ |
| test（未参与任何调参，仅报告） | 0.7255 | 0.6684 | +0.0571 |

valid 逐类（FP→INT）：Down 0.859→0.845（−0.014）、Left 0.875→0.776（−0.100）、Right 0.726→0.745（+0.019）、Stop 1.0→1.0、Thumbs Down 0.95→0.95、Thumbs up 0.95→0.917（−0.033）、Up 0.897→0.902（+0.005）。

- 每层 FP-vs-INT8 余弦（3 探针图 × 55 节点 = 165 检查）：最差 0.9305 @ model.22.cv3.1.1。
- test split 的 FP 基线本身仅 0.7255 且 npos 极少（Stop 2 框、Thumbs Down 3 框），单框翻转 ≈0.1 AP；按"测试集不参与调参"政策未针对 test 迭代，如实报告。valid 的 Left（npos=14，约 1.4 框当量）是残余损失的主要来源。
- 评测为同一 numpy 解码+NMS+AP50 评估器跑 FP 与 INT 两路原始头输出，无评估路径差异。

## 2. 方法演进（每轮只改一项，按计划 G2 失败处理条款）

| # | 变更 | valid drop | 根因/结论 |
| --- | --- | --- | --- |
| 0 | absmax 校准 | +0.8502 | 尺度取自 `model.N.conv` 输出 = **BN 之前**（ultralytics Conv=conv→bn→act），与折叠 BN 节点差每通道 BN 增益（5–25×） |
| 1 | 改为 `mod.bn` 输出钩子（每 Conv 自有 BN，= act 输入） | +0.2606 | 期间否决 `mod.act` 前置钩子方案：`Conv.default_act` 是**类级共享 nn.SiLU**，63 个钩子互相污染（最差余弦 −0.0756） |
| 2 | 双尺度 LUT：重量化域=激活前 absmax，存储张量=激活后 absmax | +0.2080 | 激活前范围负主导时单尺度浪费约 2 位（[−8,+2] 情形存储张量仅用 ±29/±127） |
| 3 | 直方图 MSE 最优裁剪 | +0.8937 ❌ | 目标函数错误而非实现错误：激活后张量被近零质量主导，最优裁剪≈absmax/1000，扼杀检测特征（合成单元测试证明曲线函数本身正确） |
| 4 | p99.99 百分位裁剪（只裁 0.01% 尾部，中位收缩 0.580） | +0.0980 | 2048-bin \|v\| 直方图双通校准 |
| 5 | **逐层 LSQ 存储尺度再拟合**（本报告最终方法，见 §3） ×3 轮×96 图 | +0.0278 | golden 斜率诊断发现每节点系统性增益误差 0.81–1.13（跨图一致） |
| 5b | 同上 ×6 轮 | +0.0344 ❌ | 饱和棘轮：每轮额外 ~4% 中位收缩，过度收缩伤害 AP |
| 5c | **同上 ×2 轮×128 图（最终）** | **+0.0176** ✅ | 收敛深度与精度的平衡点 |

## 3. 最终校准方法

1. **p99.99 百分位裁剪**（每张量对称，激活前/后两域各自）：2048-bin |v| 直方图，420 校准图。
2. **逐层 LSQ 存储尺度再拟合**：对 73 个拟合位（63 个 QConv 节点 + C2f Add 位 + 顶层 Concat 位），在 128 图校准子样本上以 INT 管线自身输出 v 对 FP 模块输出 fp 闭式拟合 `S' = ⟨v,fp⟩/⟨v,v⟩`，全部尺度每轮后同时应用，定点迭代 2 轮。动机：golden npz 回归诊断显示 p99.99 网格下每节点级联斜率系统性偏离 1（0.81–1.13，跨图一致），沿链复合；再拟合同时吸收自身新产生与继承的增益误差。requant 域（|pre）与量化权重不动——纯存储尺度重校准。refit_trace 见 manifest.json。

诊断证据：`probe_layers.py`（单层隔离：in_cos 0.995–0.999、w_cos≈1.0、full 0.969–0.996、零饱和；深度分解确认整数算术与理想舍入一致）；golden npz 斜率分析（本次拟合的依据）。

## 4. 数值合同（与硬件实现一致，已冻结）

W8A8：每输出通道对称 INT8 权重（zp=0，RNE）+ 每张量对称 INT8 激活；INT32 累加；INT32 偏置 = round(b_fold/(Sx·Sw_c))；每通道 M+shift 重量化（r=f·2^e 经 frexp，M=RNE(f·2^31)，shift=31−e，移位上 RNE ties-to-even；shift>62 死通道返回 0,0）；SiLU 256 项 LUT（输入=激活前域，输出=激活后存储尺度，即双尺度设计）；首层 uint8−128 且 z 项折叠进偏置 +128·colsum(w_q)，pad_val=−128；C2f 内部 cat 沿用 cv1 存储尺度；顶层 Concat 自校准尺度；Add：int32 求和一次饱和；MaxPool 5×5 s1 pad −128；Upsample 最近邻 ×2；检测头原始 logits INT8；PS 侧 float64 DFL/解码/NMS。PL 路径全部算子无隐藏浮点。

## 5. 工件清单

| 文件 | 内容 |
| --- | --- |
| `weights.bin` | 3,001,584 B，63 节点 INT8 权重（布局/偏移见 quant.json） |
| `bias.bin` | 86,608 B（=21652×4），INT32 折叠偏置 |
| `lut.bin` | 14,592 B，SiLU LUT（激活节点各 256 项） |
| `quant.json` | 节点表（in/out/stored_scale、w_scales、req、偏移）、tensor_scales（含 `\|pre` 域） |
| `manifest.json` | SHA-256、校准方法与 refit_trace、环境锁定、status=CANDIDATE |
| `eval_fp_vs_int8.json` | valid+test FP/INT mAP50 与逐类 |
| `golden/`（5 npz） | 每图全节点 int8+fp16 张量 + 原始头，含 `golden_index.json` |
| `regression_128frames.json` | 128 帧框/置信度/类别 + 原始头哈希 |
| `layer_error.csv` | 165 项每层余弦 |
| `intref_yolov8.py` / `run_g2_quant.py` / `probe_layers.py` | 整数参考库 / 驱动 / 诊断探针 |
| `refit_run*.out` | 迭代过程控制台证据 |

环境：`4_metrics/logs/2026-09-12_model_env_run01/venv`（Python 3.12.10、torch 2.10.0+cpu、ultralytics 8.4.142）。

## 6. 已知限制与下一步

- test split drop +0.0571 未达 0.02（npos 极少、AP 噪声大；未参与调参）。板上验收以 valid 合同 + golden 回归对齐为准；若后续需要更高裕量，候选单变量：偏置校正（每通道均值漂移补偿）、p99.9 网格实验、或按计划第 17 行转入针对性 QAT。
- Left 类 valid 残余 −0.100（≈1.4 框当量）为主残余；方向类补充数据仍是缺口（见补充数据集调研）。
- 下一步 G3：单算子 RTL 与本整数参考逐位对齐（golden npz 即对齐源），包工件已复制到 `2_fpga/3_yolo_zynq/rom_data/`。
