# 2026-09-14 日计划

## 当前：r3文档与GitHub发布（2026-09-14）

发布收据：内容提交f7c55a1已推送个人分支，已创建[PR #8](https://github.com/pipidandan-superman/FPGA2026_competition/pull/8)指向main。GitHub显示Awaiting approval / Merging is blocked，需另一位有写权限成员批准，尚未合并。xiaokaiyuan未出现在审核人搜索结果，未成功指派。下一动作是队友审核最终提交；本轮不绕过保护、不操作他人PR #7。r3文档66项检查与路径审计15项通过，量化/硬件阶段仍未执行。

本轮目标：发布部署计划r3、模型数据说明、四份日志和精选文本证据到codex/full/pipidandan-superman，创建面向main的PR。数据已下载且结构检查通过；不重复下载，不运行量化/训练/RTL/板测，不上传ZIP、图片、权重或冻结2_fpga。另一成员审核是main合并前置。

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

本轮用户要求把所有硬件部署讨论整合到既有计划。已形成r2唯一主路线：浮点基线 → 硬件一致的整数参考 → 单模块验证 → 子图验证 → 整网验证 → 实时系统验收，穿插B0–B4小规模板测。补齐公共数据前置、整数合同、golden/布局包、验证矩阵及停止条件；保留原算量/预算。本轮非目标为数据下载、量化、RTL、构建或板测。

[部署计划r2](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[修订与文档验证](../../4_metrics/logs/2026-09-14_yolo7020_plan_consolidation_run01/REPORT.md)。

## 本日历史记录（与r2冲突时以以上当前状态为准）

## 补充：允许使用公共手势数据

原训练集不是硬性前提；允许筛选公共手势数据启动校准和整数参考流程，目标保持现有七类，不默认重训或更换类别。

[公共数据适用条件](../../4_metrics/logs/2026-09-14_yolo_external_data_guidance_run01/REPORT.md)。

## 最新：量化启动条件检查

当前可以开始整数参考和导出框架开发，无需等待 RTL/上板；正式静态量化需要代表性图片，精度验收另需独立标签。目标是区分可开工内容与验收前置条件，本轮未启动量化或功能变更。

[本轮检查与后续条件](../../4_metrics/logs/2026-09-14_yolo_quantization_readiness_run01/REPORT.md)｜[原始检查输出](../../4_metrics/logs/2026-09-14_yolo_quantization_readiness_run01/console.log)。

## 最新：YOLO手势7020硬件部署详细计划完成

目标已收敛为仅在Zynq-7020实施手势YOLO，PC模型暂不考虑。完成详细部署计划、原模型逐层审计与资源预算；主线为现有权重W8A8、320性能候选/640参考、128MAC100MHz复用引擎，必要时硬件对齐结构化剪枝。旧的PC预处理优先级作为历史保留。

[详细部署计划](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[本轮证据](../../4_metrics/logs/2026-09-14_yolo7020_deployment_plan_run01/REPORT.md)。

## 最新：最终目标调整为板上YOLO与PC其他模型协作

用户明确最终目标为PS+PL独立完成YOLOv8手势检测并与HDMI显示融合，网口向PC提供原图/ROI/结果用于另一模型。本轮完成合理性分析；早前仅优化PC预处理/RGB565传输的建议作为局部历史方案保留。下一步应围绕量化算子映射、共享DDR推理通道、同帧框图匹配和干净原图加元数据协议设计，详见[报告最新目标](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)。当前是DESIGN_ONLY，无新增硬件实现或板测。本地完整检测应在PC断开时仍工作，检测率与HDMI刷新率分开验收。

## 用户追问后的方向修订

以净提速为目标，先测PS快照/CRC/分包/发送及PC显示等待推理。默认5 fps和每16包1 ms节流已在源码确认，但尚无本轮分段实测。额外原图+ROI会增加总流量；首版不默认增加letterbox/CRC副本。评估RGB565单流上传、PC精确展开以保持原画面，或用户接受低分辨率后再评估PL缩放支路。新增图像写DDR通常需独立S2MM，元数据可走AXI-Lite。详细分析与代码位置见[报告补充](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)。当前为咨询分析完成，未执行功能变更或板测；后续先做可归因测量。

## 当前判断

当前七类手势 YOLOv8n 完整运行在 PC；板端提供 `640x480` BGR 视频。模型等价预处理为 `640x640` letterbox、BGR->RGB、`/255` 和 HWC->CHW。冻结 FPGA 工程中的旧灰度/二值化/`112x112->28x28` 模块不在当前 BD 中，且不兼容该 YOLO 输入。

## 主目标

明确哪些预处理可下放 PL，并给出不反压、不复位、不抢占显示主链的旁路结构与验收门。

## 优先任务

1. 核对当前 PC 模型、输入张量、推理参数和板端像素格式。
2. 核对冻结 PL 视频主链与既有预处理模块的实际集成状态。
3. 区分数值等价下放、需重新验证的 ROI/缩放，以及不推荐操作。
4. 定义 HDMI 连续性隔离原则和分阶段实现范围。

## 非目标

- 不修改、构建或下载 `2_fpga`。
- 不连接板卡，不改变当前视频/动作服务。
- 不把设计分析表述为资源、时序、模型精度或板测 PASS。

## 交付

- [PL 预处理下放分析](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)
- 本日执行、验证和继续指南。
