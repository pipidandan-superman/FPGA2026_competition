# G1 浮点基线 run01｜2026-09-14

状态：`G1_FP32_BASELINE_PASS / SIZE_COMPARISON_RECORDED / QUANTIZATION_NOT_RUN`

依据：部署计划 r3 §10.2/§13.3 第一批软件工作包。输入只读（best.pt/best.onnx/v6 dataset 导出包均未修改），全部产物在本 run 目录。

## 执行内容与状态

| 阶段 | 状态 | 说明 |
| --- | --- | --- |
| 权重 manifest | PASS | best.pt SHA-256 `68db7cac…`、best.onnx `ac45c457…`（与 MODEL.md/静态profile一致，未变） |
| 独立路径数据配置 | PASS | 原包 data.yaml 未动；新建 `gesture_v6_local.yaml` 绝对路径，`check_det_dataset` 解析核对通过 |
| 数据集清单 | PASS | 逐图 SHA-256、逐类框数入 `dataset_manifest.json`；valid/test 列表冻结 |
| 校准名单 | PASS | 420 张，按类分层（每类目标 60，seed=20260914）；train 无空标签图（background=0） |
| 预处理参考 | PASS | numpy letterbox(114, BGR→RGB, /255, CHW) 与 ultralytics LetterBox **逐位一致**（max_abs_diff=0.0，含 640×480 合成图非方图用例 ×3 尺寸） |
| FP32 基线 | PASS | 640/416/320 × val/test 全部完成，conf=0.001 扫描（非部署单点） |

## 结果（mAP50 / mAP50-95）

| 尺寸 | valid(59图/81框) | test(69图) |
| --- | --- | --- |
| 640 | 0.796 / 0.459 | 0.730 / 0.438 |
| 416 | 0.812 / 0.443 | 0.745 / 0.431 |
| 320 | 0.824 / 0.456 | 0.741 / 0.428 |

尺寸损失（valid，相对 640）：416 mAP50 **-0.015**（即上升）、320 **-0.028**（上升）；mAP50-95 均在 +0.003 以内。小尺寸不亏的原因：v6 为 416×416 拉伸分布，320 缩放比 640 放大更接近原生分辨率。**320 性能候选获得数据支撑**，最终裁定留给 G2 量化后同口径对照。

逐类（valid，gt 框数）：Right 最弱（640:0.372 / 320:0.428，gt=10）；其余各类 ≥0.746。Stop gt=1、Thumbs up/Down gt=4——这几类**统计意义不足**，与 MODEL.md 弱类结论方向一致但幅度受样本量限制。

## 边界与注意事项

- conf=0.001 全扫描指标；部署 conf=0.45 单点 P/R 另行记录（计划 §4.4.4）
- 每类结论受 valid/test 微小样本限制（单类 1–30 框），不外推为真实场景精度
- v6 分布（416 拉伸、特定背景）≠ 摄像头 640×480 分布；部署场景精度待 G6/独立场景集
- 本轮未做训练/量化/剪枝，不构成 G2 数值包；`dataset_manifest.json` 等清单冻结后供 G2 引用

## 产物清单

`weights_manifest.json`｜`dataset_manifest.json`｜`class_map.json`｜`calibration_list.txt`(420)｜`valid_list.txt`｜`test_list.txt`｜`calibration_stats.json`｜`preprocess_check.json`｜`metrics_fp32.json`｜`size_loss.json`｜`run_env.json`｜`summary.json`｜`console.log`｜`run_g1_baseline.py`

环境：`4_metrics/logs/2026-09-12_model_env_run01/venv`（torch 2.10.0+cpu / ultralytics 8.4.142 / numpy 2.x），seed=20260914，OMP=MKL=2 线程。
