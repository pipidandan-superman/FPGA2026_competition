# YOLO 手势量化启动条件检查

日期：2026-09-14。范围：只读资产检查与启动条件分析，未执行量化、训练、整数参考推理、RTL 或板测。工程日志技能要求记录本次结论；冻结 2_fpga 和原权重均未修改。

结果：`READY_FOR_REFERENCE_DEVELOPMENT / CALIBRATION_DATA_NOT_LOCATED / INTEGER_REFERENCE_NOT_IMPLEMENTED / QUANTIZATION_NOT_RUN`。

## 已核实

- best.pt 和 best.onnx 存在，本次 SHA-256 与同日静态分析一致，见 [原始输出](console.log)。
- 已锁环境内存在 onnxruntime/quantization/quantize.py，第 479 行定义 quantize_static；这是接口源码存在性证据，不是本轮量化运行通过。
- 全项目按 data.yaml、data.yml、*dataset*.yaml、*train*.zip、*gesture*.zip、dataset*.json 定向检索，排除 venv、_internal、site-packages、node_modules、.git，没有命中。不能据此断言其他命名/目录/压缩包中绝无数据。
- 历史 camera/webcam/gesture/yolo 命名证据目录发现 3 个 .bgr 文件，每个 921600 字节。仅核实文件存在与大小，未验证图像内容、类别覆盖或校准代表性。
- 已有静态模型分析可复用，见 [静态分析报告](../2026-09-14_yolo7020_deployment_plan_run01/REPORT.md)。该分析不证明量化精度或硬件逐位一致。
- 项目技能路径审计 15 项通过，输出已保存在 console.log。

## 启动条件与工作边界

1. 无需先完成 RTL、DMA、综合或上板；现在可以开发算术合同、整数参考、导出器与合成单元测试。
2. 主线采用现有权重训练后静态量化（PTQ），不要求完整训练集、不要求重新训练，也不强制 GPU。代表性无标注图片即可参与激活校准。
3. 可靠的精度验收需要独立带标签的验证/测试数据。旧 MODEL.md 中 test/train 子集校准的建议不适用于本次严格对照：测试集保持不参与校准和参数选择。
4. 300–1000 张代表性校准图是工程起始建议而非算法最低要求。少量真实图或随机输入可以做流程 smoke test，但不能证明部署精度。正式校准应覆盖手势、空背景、光照、距离和目标大小，视频抽帧须去除近重复。
5. 先锁最低算术合同：W8A8 类型/量化范围/scale/zero point、BN 折叠、INT32 bias/累加及溢出处理、定点乘子/移位/舍入/饱和、Add/Concat 对齐和 SiLU 近似。软件不能用普通浮点 Conv 假装全程精确整数累加。
6. 640 保留原始精度参考，320 作为资源候选。先做同尺寸 FP32/INT8 对比，另行计算缩小尺寸损失；不能把尺寸变化损失和量化损失混为一谈。可先实现一个尺寸的参考流程，再对候选尺寸重新校准与验证。
7. QDQ ONNX 作为量化诊断/对照产物，不自动等于自研 FPGA 的位精确 golden。首版允许 PS 承担 DFL 解码/NMS，但必须记录 PS/PL 边界，PL 算子不得静默浮点回退。
8. 逻辑张量和量化元数据可以先保存；DMA/BRAM 实际打包、tile 顺序和总线 padding 在接口确定后导出，不必为了尚未冻结的 PE 数量阻塞数值基线。
9. 改变输入尺寸、权重、量化参数或运算规则后，必须重新生成有版本/hash 的 golden，避免硬件比较到过期文件。

## 建议的下一阶段

先开发算术合同/整数参考/数据导出框架；数据到位后完成同尺寸浮点基线、真实图片校准、硬件规则整数推理和独立精度验证，再冻结参数与逐层输入/INT32 累加/重定标/非线性输出。保存 manifest、预处理配置、量化参数、权重/bias/LUT、少量完整中间张量及对照指标。大规模验证保留指标和异常，不全量倾倒所有层。

当前最小外部输入：队友数据集目录（优先 images、labels、data.yaml）；若只有图片，也能先做 PTQ，但不能完成有标签精度验收。当前不是整项工作停滞，而是有数据依赖的验收阶段尚不能完成。

## 查询与来源

只读命令：Get-FileHash 检查原模型；Test-Path 和 rg 检查静态量化接口；rg --files 按上述模式定向检索；Get-Item 读取历史帧元数据；powershell -NoProfile -ExecutionPolicy Bypass -File E:/competition/4_metrics/scripts/audit_project_skill_paths.ps1。检查输出保存在 console.log。

本地内容来源：3_host/model/MODEL.md、锁定环境 quantize.py、同日部署计划与静态证据。外部技术来源：[ONNX Runtime 官方量化说明](https://onnxruntime.ai/docs/performance/model-optimizations/quantization.html)，用于核实静态校准、QDQ 表达及量化精度调试边界。
