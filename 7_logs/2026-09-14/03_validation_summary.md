# 2026-09-14 验证摘要

## 当前：r3文档与GitHub发布（2026-09-14）

已确认远端旧PR #6已合并，origin/main=91f3974，个人分支已快进同步。数据实际1765/59/69及七类顺序与MODEL.md一致；结构PASS不能提升为精度/量化PASS。发布验证和最终PR状态见下方本轮报告。既有r2的66项验证仅覆盖r2历史版本，不冒充r3验证。

[部署计划r3](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[发布审计与交接](../../4_metrics/logs/2026-09-14_yolo7020_docs_github_publish_run01/REPORT.md)。以下为同日过程记录，旧“当前/最新/等待”标题只表示当时状态，与本节冲突时以本节及发布报告为准。

## 当前：v6 YOLOv8已下载并校验

用户确认条款后完成ZIP下载、安全解压和结构检查，DOWNLOAD_AND_ZIP_CRC_PASS / PACKAGE_STRUCTURE_PASS。实际train1765/valid59/test69，共1893张416x416，七类顺序与本模型一致；网页数量差异未出现在实际包划分。原ZIP/hash、图片清单及validation.json已归档，登录和条款停止点已解除。下一步可按r2做数据语义/去重审核、独立本地路径配置与浮点基线；本轮未训练或量化，不能把结构检查当精度通过。

[下载完成与校验报告](../../4_metrics/logs/2026-09-14_gesture_dataset_download_run01/REPORT.md)。原模型/2_fpga未修改，原始下载文件保留。

## 最新：v6 YOLOv8下载等待Roboflow登录

用户已要求下载。浏览器实际进入v6/YOLOv8导出页后显示Login or create a free account；已保留标签供用户登录。状态DOWNLOAD_PENDING_USER_LOGIN / ARCHIVE_NOT_DOWNLOADED，无ZIP或校验通过结果。用户完成登录后继续原版本下载到本run，检查ZIP/hash/安全解包/类别和划分；不改用其他数据集，不修改模型或2_fpga。

[下载停止点与后续步骤](../../4_metrics/logs/2026-09-14_gesture_dataset_download_run01/REPORT.md)。

## 最新：公开七类手势数据已定位（未下载）

找到MODEL.md记录的Roboflow同项目及v6页面，七类名称匹配；公开划分1870/72/69与本地1765/59/69不一致，页面为416拉伸预处理。下载入口本轮抓取失败，不能标下载或数据准入通过。HaGRID仅作后续补充候选。下一步若实施，先获取首选包并核对hash、类别ID/框、划分和预处理，不直接沿用旧精度数字。

[公开数据检索与差异](../../4_metrics/logs/2026-09-14_gesture_public_dataset_search_run01/REPORT.md)。本轮仅查证与记录，未改模型/部署计划或执行量化。

## 当前：部署计划r2统一收敛

r2内容已整合，DOCUMENT_VALIDATION_PASS：66项检查全部通过、13个主章节、12个本地链接有效、UTF-8及代码围栏正常、原权重与r1快照哈希一致、四份工程记录齐全，技能路径审计15项通过。原始输出见本轮证据目录validation_console.log。原静态模型证据继续有效于其原范围；量化、整数参考、RTL、仿真、上板和实时验收均未执行，文档校验不升级任何技术阶段状态。

[部署计划r2](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[修订与文档验证](../../4_metrics/logs/2026-09-14_yolo7020_plan_consolidation_run01/REPORT.md)。

## 本日历史记录（与r2冲突时以以上当前状态为准）

## 补充：允许使用公共手势数据

确认公共数据可用于 PTQ，原训练集非必需。已核对现模型七类定义及官方校准机制，尚未选择/下载/检查任何候选数据集，未运行量化；检测精度须用适配标签评估，位精确一致不等于语义准确。

[公共数据适用条件](../../4_metrics/logs/2026-09-14_yolo_external_data_guidance_run01/REPORT.md)。

## 最新：量化启动条件检查

权重哈希不变，静态量化接口源码存在；定向数据清单/归档检索未命中，历史原始 BGR 帧命中 3 个，仅确认大小。结果 READY_FOR_REFERENCE_DEVELOPMENT / CALIBRATION_DATA_NOT_LOCATED / INTEGER_REFERENCE_NOT_IMPLEMENTED / QUANTIZATION_NOT_RUN。路径审计 15 项通过。接口存在、少量帧和静态分析均不代表量化精度或位精确参考已验收。

[本轮检查与后续条件](../../4_metrics/logs/2026-09-14_yolo_quantization_readiness_run01/REPORT.md)｜[原始检查输出](../../4_metrics/logs/2026-09-14_yolo_quantization_readiness_run01/console.log)。

## 最新：YOLO手势7020硬件部署详细计划完成

本轮MODEL_STATIC_PROFILE_PASS：PT参数3,012,213，主卷积63个、320/640分别1.011014/4.044058 GMAC。ONNX64个Conv算量与PT一致；单个合成输入PT/ONNX allclose通过，模型哈希不变。资源合计预算DSP145–161/220、BRAM92.5–108.5/140，属于设计预算，无综合/板测。计划本地链接与UTF-8检查通过。

[详细部署计划](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[本轮证据](../../4_metrics/logs/2026-09-14_yolo7020_deployment_plan_run01/REPORT.md)。

## 最新：最终目标调整为板上YOLO与PC其他模型协作

用户明确最终目标为PS+PL独立完成YOLOv8手势检测并与HDMI显示融合，网口向PC提供原图/ROI/结果用于另一模型。本轮完成合理性分析；早前仅优化PC预处理/RGB565传输的建议作为局部历史方案保留。下一步应围绕量化算子映射、共享DDR推理通道、同帧框图匹配和干净原图加元数据协议设计，详见[报告最新目标](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)。当前是DESIGN_ONLY，无新增硬件实现或板测。本地完整检测应在PC断开时仍工作，检测率与HDMI刷新率分开验收。

## 用户追问后的方向修订

以净提速为目标，先测PS快照/CRC/分包/发送及PC显示等待推理。默认5 fps和每16包1 ms节流已在源码确认，但尚无本轮分段实测。额外原图+ROI会增加总流量；首版不默认增加letterbox/CRC副本。评估RGB565单流上传、PC精确展开以保持原画面，或用户接受低分辨率后再评估PL缩放支路。新增图像写DDR通常需独立S2MM，元数据可走AXI-Lite。详细分析与代码位置见[报告补充](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)。当前为咨询分析完成，未执行功能变更或板测；后续先做可归因测量。

## 已核实事实

- 当前模型：7 类手势 YOLOv8n，PC 端 PyTorch/Ultralytics 推理。
- 当前模型调用：`imgsz=640`、`rect=False`、`conf=0.45`、`iou=0.7`。
- 当前输入：板端 UDP 完整帧 `640x480x3`，PC 视为 BGR HWC uint8。
- 文档输入合同：letterbox 到 `640x640`，填充值 114，BGR->RGB，`/255`，输出 `[1,3,640,640] float32`。
- 当前显示主链通过原 VDMA/DDR/MM2S 到 HDMI；旧灰度/二值化/28x28预处理 RTL 未接入当前 BD。
- 最近动作版已有实现报告使用率较低且时序满足，但它没有包含本次建议的预处理旁路。

## 本轮结果

`ANALYSIS_COMPLETE / DESIGN_ONLY / FPGA_NOT_MODIFIED / BOARD_NOT_RUN`

完整分析与证据来源：

- [2026-09-14 PL 预处理分析 run01](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)

## 后续 PASS 标准

- 数值等价：固定帧上的 PL 与 PC 预处理输出匹配，或误差界限和检测差异已量化并接受。
- 显示隔离：旁路正常、禁用、过载时 HDMI 连续且原 VDMA 无错。
- 数据隔离：原 UDP CRC/丢帧不劣化；只允许推理支路按整帧策略丢弃。
- 模型一致：同一帧集上的检测框、类别、置信度及数据集指标达到预先锁定标准。
- 长稳：并发运行至少 2 小时，保留所有原始日志与异常。

## 未验证

- 尚无新增 RTL、仿真、综合、实现或板测。
- 尚未证明新增 DMA 的 DDR 并发安全。
- 尚未证明 ROI、缩小输入或定点量化不降低手势识别精度。
