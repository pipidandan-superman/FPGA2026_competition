# 2026-09-14 下次启动指南

## 当前：补充数据集调研与HaGRID下载（2026-09-14）

先查后台下载任务状态：`3_host/model_datasets/hagrid-sample-500k-384p.zip`（13.4GB，hf-mirror源）完成后①核验SHA-256=`461ad5746eb95c3605f4fa2ba7daa19e2fcd4d7d91d4d26c7c31dfe228feb68e`②安全解压③确认标注JSON是否在ZIP内④按user_id划分独立评估子集并建4_metrics run。方向类（Left/Right/Down）仍是缺口：Kaggle `marusagar/hand-gesture-detection-system`与Roboflow Universe类名检索需用户本人登录导出（swipe语义≠静态指向，禁止改名映射）。全景与操作路径见[supplementary_dataset_survey_2026-09-14.md](../../3_host/model_datasets/supplementary_dataset_survey_2026-09-14.md)。

## 当前：1_docs 分类整理与去重（2026-09-14）

找文档先读[1_docs/README.md](../../1_docs/README.md)：分类索引+迁移对照表是旧路径的权威入口。正式交付文档在`doc/`（索引`doc/README.md`），赛题原文/评分页/设计方案/平台选型在`赛题方向/`，器件手册在`datasheets/`（ov5640与ADV7511 manuals仅本地不在Git），早期文档在`legacy/`。历史日志里的旧`1_docs`路径不回写，按对照表换算。已推送93eae1f。

## 当前：r3文档与GitHub发布（2026-09-14）

发布收据：内容提交f7c55a1已推送个人分支，已创建[PR #8](https://github.com/pipidandan-superman/FPGA2026_competition/pull/8)指向main。GitHub显示Awaiting approval / Merging is blocked，需另一位有写权限成员批准，尚未合并。xiaokaiyuan未出现在审核人搜索结果，未成功指派。下一动作是队友审核最终提交；本轮不绕过保护、不操作他人PR #7。r3文档66项检查与路径审计15项通过，量化/硬件阶段仍未执行。

首先阅读部署计划r3第13节及本轮发布报告，确认PR审核/合并状态。后续技术工作从v6语义/框质量、跨集重复与场景覆盖审核、独立路径配置、校准清单和FP32基线开始；可并行做整数oracle。禁止再按历史登录/条款等待点执行，禁止测试集校准、直接改2_fpga或自动上板。main合并须另一成员审核。

[部署计划r3](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[发布审计与交接](../../4_metrics/logs/2026-09-14_yolo7020_docs_github_publish_run01/REPORT.md)。以下为同日过程记录，旧“当前/最新/等待”标题只表示当时状态，与本节冲突时以本节及发布报告为准。

## 当前：v6 YOLOv8已下载并校验

用户确认条款后完成ZIP下载、安全解压和结构检查，DOWNLOAD_AND_ZIP_CRC_PASS / PACKAGE_STRUCTURE_PASS。实际train1765/valid59/test69，共1893张416x416，七类顺序与本模型一致；网页数量差异未出现在实际包划分。原ZIP/hash、图片清单及validation.json已归档，登录和条款停止点已解除（数据本体2026-09-14应用户要求迁至`3_host/model_datasets/`，校验证据留在原run目录）。下一步可按r2做数据语义/去重审核、独立本地路径配置与浮点基线；本轮未训练或量化，不能把结构检查当精度通过。

[下载完成与校验报告](../../4_metrics/logs/2026-09-14_gesture_dataset_download_run01/REPORT.md)。原模型/2_fpga未修改，原始下载文件保留。

## 当前下载停止点：已登录，等待条款确认

用户登录后已选择v6/YOLOv8 ZIP下载，网站要求勾选接受Terms of Service和Privacy Policy。未代为接受、无ZIP；等待用户明确同意或自行确认后继续。浏览器标签已保留；以下等待登录记录已过时。详见[下载记录](../../4_metrics/logs/2026-09-14_gesture_dataset_download_run01/REPORT.md)。

## 最新：v6 YOLOv8下载等待Roboflow登录

用户已要求下载。浏览器实际进入v6/YOLOv8导出页后显示Login or create a free account；已保留标签供用户登录。状态DOWNLOAD_PENDING_USER_LOGIN / ARCHIVE_NOT_DOWNLOADED，无ZIP或校验通过结果。用户完成登录后继续原版本下载到本run，检查ZIP/hash/安全解包/类别和划分；不改用其他数据集，不修改模型或2_fpga。

[下载停止点与后续步骤](../../4_metrics/logs/2026-09-14_gesture_dataset_download_run01/REPORT.md)。

## 最新：公开七类手势数据已定位（未下载）

找到MODEL.md记录的Roboflow同项目及v6页面，七类名称匹配；公开划分1870/72/69与本地1765/59/69不一致，页面为416拉伸预处理。下载入口本轮抓取失败，不能标下载或数据准入通过。HaGRID仅作后续补充候选。下一步若实施，先获取首选包并核对hash、类别ID/框、划分和预处理，不直接沿用旧精度数字。

[公开数据检索与差异](../../4_metrics/logs/2026-09-14_gesture_public_dataset_search_run01/REPORT.md)。本轮仅查证与记录，未改模型/部署计划或执行量化。

## 当前：部署计划r2统一收敛

首先阅读部署计划r2第13节，再按第4.4节完成公共/自采数据准入和划分，同时准备第4.6节整数算术合同、oracle与导出器；用户要求实施后按G0/G1/G2推进。主路线和B0–B4板测位置已经明确，不再等待选择早期PC预处理分支。禁止直接改冻结2_fpga、升级环境或自动上板；成功标准是对应阶段证据，而非一份导出的INT8文件。

[部署计划r2](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[修订与文档验证](../../4_metrics/logs/2026-09-14_yolo7020_plan_consolidation_run01/REPORT.md)。

## 本日历史记录（与r2冲突时以以上当前状态为准）

## 补充：允许使用公共手势数据

不必等待队友训练集。可在用户要求执行后筛选公共手势数据；有代表性的无标注图片可先校准和导出 golden，独立精度集需正确映射的七类与检测框。保持校准与评估分离；不得将其他手势强行改名为现七类。

[公共数据适用条件](../../4_metrics/logs/2026-09-14_yolo_external_data_guidance_run01/REPORT.md)。

## 最新：量化启动条件检查

先读量化启动条件检查报告，定位队友 images/labels/data.yaml 或真实摄像头图片。同时可开发 W8A8 算术合同、整数参考与逻辑张量导出器，不必等待完整训练集、RTL 或板卡。代表性无标注图可做 PTQ；独立带标签数据用于精度验收，测试集不得参与校准。原模型与 2_fpga 继续冻结；未验证的少量帧不得作为正式校准充分性的证据。

[本轮检查与后续条件](../../4_metrics/logs/2026-09-14_yolo_quantization_readiness_run01/REPORT.md)｜[原始检查输出](../../4_metrics/logs/2026-09-14_yolo_quantization_readiness_run01/console.log)。

## 最新：YOLO手势7020硬件部署详细计划完成

下一步先定位队友训练/验证数据和现场校准图，运行同权重640/416/320精度对照并锁W8A8数值合同。已有static profile不必重做。GEMM/IR接口可按详细计划设计，原2_fpga保持冻结；暂不启动完整RTL/板测，也不以随机图代替真实校准。早前等待选择预处理模块的停点已由当前完整部署路线替代。

[详细部署计划](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[本轮证据](../../4_metrics/logs/2026-09-14_yolo7020_deployment_plan_run01/REPORT.md)。

## 最新：最终目标调整为板上YOLO与PC其他模型协作

用户明确最终目标为PS+PL独立完成YOLOv8手势检测并与HDMI显示融合，网口向PC提供原图/ROI/结果用于另一模型。本轮完成合理性分析；早前仅优化PC预处理/RGB565传输的建议作为局部历史方案保留。下一步应围绕量化算子映射、共享DDR推理通道、同帧框图匹配和干净原图加元数据协议设计，详见[报告最新目标](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)。当前是DESIGN_ONLY，无新增硬件实现或板测。本地完整检测应在PC断开时仍工作，检测率与HDMI刷新率分开验收。

## 用户追问后的方向修订

以净提速为目标，先测PS快照/CRC/分包/发送及PC显示等待推理。默认5 fps和每16包1 ms节流已在源码确认，但尚无本轮分段实测。额外原图+ROI会增加总流量；首版不默认增加letterbox/CRC副本。评估RGB565单流上传、PC精确展开以保持原画面，或用户接受低分辨率后再评估PL缩放支路。新增图像写DDR通常需独立S2MM，元数据可走AXI-Lite。详细分析与代码位置见[报告补充](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)。当前为咨询分析完成，未执行功能变更或板测；后续先做可归因测量。

## 历史第一动作（已被r2取代）

先阅读 [PL 预处理下放分析](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)，由用户在以下范围中确认第一版目标：

1. 仅做无反压旁路、frame_id/时间戳/完整帧标志；或
2. 再加入与当前模型等价的颜色打包和 640x640 letterbox；或
3. 另开 ROI/320 输入精度研究分支。

## 禁止立即动作

- 不直接修改冻结 `2_fpga`。
- 不把旧灰度/二值化/28x28模块接到当前 YOLO 输入。
- 不用共享 `TREADY` 的简单 Broadcaster 把推理阻塞传播到显示。
- 未做数值对齐前不删除 PC 预处理；未做精度测试前不改模型输入尺寸。

## 历史预处理方案成功标准（非当前整网验收标准）

第一版最小成功应同时满足：显示主链 RTL/连接不变、推理旁路过载只丢自身整帧、100帧数值对齐通过、HDMI/原UDP连续性不退化，并为新增逻辑保存独立资源/时序/板测证据。

## 历史阻塞（已解除）

此前曾等待选择第一版预处理功能边界；当前已收敛为板上YOLO部署，不再等待此选择。下一步数据来源可以是公共或自采；数据准备不阻塞整数参考框架开发。仍应在独立工程或可回退副本实现与仿真，不直接在冻结板证基线上试改。
