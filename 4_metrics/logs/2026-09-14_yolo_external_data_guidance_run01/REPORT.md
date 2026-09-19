# 公共手势数据用于现有模型量化的边界

2026-09-14；咨询结论，未下载数据、训练、量化或修改模型/FPGA。结果：ANALYSIS_COMPLETE / DATASET_NOT_SELECTED / QUANTIZATION_NOT_RUN。

原训练集不是静态 PTQ 的硬性条件。公共数据或自采图片可以用于校准，关键是代表预期部署输入。校准不要求标签或外部类别 ID 与现模型一致；建议覆盖当前手势、背景、尺度、光照等，不把白底单手裁剪图直接当作复杂背景远距离视频的充分代表。

精度验收需要独立的检测框与类别标注，语义及 ID 映射到现模型 0 Down、1 Left、2 Right、3 Stop、4 Thumbs Down、5 Thumbs up、6 Up；仅有整图类别或关键点的数据不能直接计算现检测任务的完整 mAP。相似类别名不保证语义一致，例如 Left 是手指指向而非左手身份。没有目标七类的标签不能通过强行改名制造语义对应。

FP32 和 INT8 在同一独立外部评估集、相同输入尺寸与预后处理下对比，隔离量化新增损失；FP32 本身泛化差应另行处理，PTQ 不会训练出新类别。外部结果不能直接同旧测试集 mAP 相减。校准/调参/最终评估分开，视频按来源/片段分组并去重，最终保留部署摄像头场景验收。

硬件整数 golden 不依赖人工类别标签，可用外部图片生成；但参考与硬件一致不等于识别语义正确。建议公共数据先启动软件数值流程，再补部署摄像头样本做校准/独立测试，必要时重校准并版本化重导 golden。

来源：本轮读取 3_host/model/MODEL.md 核对类别；[ORT 静态量化](https://onnxruntime.ai/docs/performance/model-optimizations/quantization.html#static-quantization)核对输入校准机制；[Ultralytics 官方导出说明](https://docs.ultralytics.com/modes/export#quantization-options)核对代表性校准数据要求。未把最新导出命令视为本地锁定版本已支持，也未采用 TensorRT 作为 FPGA 部署方案。

[检查和路径审计原始输出](console.log)：技能路径审计 15 项通过，仅为路径合规证据。
