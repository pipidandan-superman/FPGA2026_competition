# YOLO手势7020部署计划：本轮证据

结果：`MODEL_STATIC_PROFILE_PASS / DESIGN_PLAN_COMPLETE`。量化、训练、RTL实现、仿真、综合、板测均未执行。

交付：[详细计划](../../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)。

## 已完成

- 对原best.pt/best.onnx校验SHA-256；读取本地已锁定的模型环境。
- 在256/320/416/640四种尺寸上作PT合成输入形状分析，提取卷积、张量和逻辑分块周期；不修改原固定640 ONNX。
- 独立计算ONNX Conv MAC，与PT640全部64次Conv的4,044,595,200 MAC一致。
- PT/ONNX固定随机输入误差max_abs=0.00067138671875，mean_abs=0.0000062996709857543465，rtol/atol0.001比较通过；不是数据集精度证明。
- 主网络63卷积的MAC：320为1,011,014,400，640为4,044,057,600。参数总计3,012,213；主卷积权重元素3,001,584。
- 新增硬件预算与64/128MAC、100/150MHz、效率40/60/80%、DDR100/250/500MBps的144组敏感性组合已生成；均为假设推演。
- 计划本地链接检查零失败、UTF-8替代字符零个、原PT权重哈希保持不变。

## 命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/competition/3_host/model_env/run_python.ps1 E:/competition/4_metrics/logs/2026-09-14_yolo7020_deployment_plan_run01/profile_model.py
powershell -NoProfile -ExecutionPolicy Bypass -File E:/competition/3_host/model_env/run_python.ps1 E:/competition/4_metrics/logs/2026-09-14_yolo7020_deployment_plan_run01/estimate_resources.py
```

首次沙箱启动venv报`Unable to create process using ... Python312/python.exe`；经批准后以同一解释器执行成功，未换环境、未装依赖。模型分析输出在console.log（脚本main阶段），估算完整数值在resource_estimate.json和CSV。

## 主要文件

- [summary.json](summary.json)、[profile.json](profile.json)：数值、版本、模型/脚本哈希和精度边界。
- [architecture.json](architecture.json)、[onnx_nodes.json](onnx_nodes.json)：原图结构。
- [conv_layers_320.csv](conv_layers_320.csv)、[conv_layers_640.csv](conv_layers_640.csv)：逐卷积M/N/K、MAC、输入输出和展开规模。
- [resource_estimate.json](resource_estimate.json)、[throughput_sensitivity.csv](throughput_sensitivity.csv)：预算假设与结果。
- [profile_model.py](profile_model.py)、[estimate_resources.py](estimate_resources.py)：复现脚本。

## 外部资料边界

官方ORT静态量化、Torch-Pruning原作者YOLOv8示例、FINN官方构建文档、AMD DSP48E1原语资料已浏览。额外查到KV260完整YOLO部署参考以及7020检测头/后处理参考；未把其性能当成本板完整网络数据。资料链接与各自用途在详细计划第3/6节。没有下载并运行外部代码。

## 未解决但不阻碍计划交付的事项

训练/校准数据位置尚未确认；量化精度、320尺寸精度、真实DDR有效带宽、MAC核供数及布局后资源/时序尚待G0余项至G7逐步验证。本轮不宣称量化已生成或可直接部署。
