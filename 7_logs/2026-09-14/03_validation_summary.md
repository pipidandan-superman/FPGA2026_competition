# 2026-09-14 验证摘要

## 当前：1_docs 分类整理与去重（2026-09-14）

六分类落地且活跃文档旧路径残留为0（grep终扫）；重复删除依据为逐文件证据：`doc/ADV7511KSTZ`全部文件与`datasheets/ADV7511_Hardware_Users_Guide/`一致且后者为超集（多寄存器表/MANIFEST/3个linux_driver文件），`赛题方向/amd_dual_model`r2（10:11）第5/6章覆盖初版（08:23）独有主题。分支同步93eae1f：73重命名+6新增+14删除+7修改=119个跟踪文件，排除项零入库，工作区与磁盘README哈希一致。边界：历史日志与`4_metrics`中的旧1_docs路径按政策不回写，以[迁移对照表](../../1_docs/README.md)为权威入口；`物联网综合课程设计资料.zip`系用户自行删除非异常；第三方资料/ov5640/ADV7511 manuals仅本地。

## 当前：zynq-pynq-overlay-workflow skill修复（2026-09-14）

用户反馈按该skill执行在线加载失败而EES331_PL_Reloader_v1.4 EXE正常。根因：skill于2026-09-13仅做格式/镜像一致性校验，未包含v1.0–v1.3失败、v1.4验证通过的摄像头overlay热重载关键序列（v1.3实测：BIT下载PASS+fpga_manager operating仍FIRST_FRAME_TIMEOUT，被误读为"无法在线加载"）。本轮修复：

- `references/ees331.md`新增"Camera overlay hot-reload: proven load sequence"一节：安全停原服务（VDMA_HALTED→BUFFER_FREED）、两阶段Overlay(download=False)预校验、fpga_manager state检查、10s传感器settle、30s首帧门控（每秒槽位报告）、fail-closed恢复；标注载荷常量与v1.4工具入口；引用v13失败审计与v14两轮验收证据。同轮修复该文件数字与单位间空格丢失的粘连问题。
- `SKILL.md`新增通用条目：重载成功判据必须是观测到数据流动而非下载完成；热重载丢失上电隐式传感器settle（如SCCB），需显式定时settle+有界首帧窗口+超时fail-closed。
- 三层同步（6_skill、.codex/skills、.claude/skills）后逐文件SHA-256一致（SKILL.md 636c1f31...，ees331.md 5fa5b999...）。
- 另：本项目10个skill已安装到E:/competition/.claude/skills（Claude Code原生调用层），与6_skill参考层全量哈希一致。

边界：本轮为文档/skill修复，未改RTL、载荷、EXE或板卡状态；未复现实机加载，v1.4证据仍为2/2样本。

## 当前：r3文档与GitHub发布（2026-09-14）

发布收据：内容提交f7c55a1已推送个人分支，已创建[PR #8](https://github.com/pipidandan-superman/FPGA2026_competition/pull/8)指向main。GitHub显示Awaiting approval / Merging is blocked，需另一位有写权限成员批准，尚未合并。xiaokaiyuan未出现在审核人搜索结果，未成功指派。下一动作是队友审核最终提交；本轮不绕过保护、不操作他人PR #7。r3文档66项检查与路径审计15项通过，量化/硬件阶段仍未执行。

已确认远端旧PR #6已合并，origin/main=91f3974，个人分支已快进同步。数据实际1765/59/69及七类顺序与MODEL.md一致；结构PASS不能提升为精度/量化PASS。发布验证和最终PR状态见下方本轮报告。既有r2的66项验证仅覆盖r2历史版本，不冒充r3验证。

[部署计划r3](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[发布审计与交接](../../4_metrics/logs/2026-09-14_yolo7020_docs_github_publish_run01/REPORT.md)。以下为同日过程记录，旧“当前/最新/等待”标题只表示当时状态，与本节冲突时以本节及发布报告为准。

## 当前：v6 YOLOv8已下载并校验

用户确认条款后完成ZIP下载、安全解压和结构检查，DOWNLOAD_AND_ZIP_CRC_PASS / PACKAGE_STRUCTURE_PASS。实际train1765/valid59/test69，共1893张416x416，七类顺序与本模型一致；网页数量差异未出现在实际包划分。原ZIP/hash、图片清单及validation.json已归档，登录和条款停止点已解除（数据本体2026-09-14应用户要求迁至`3_host/model_datasets/`，校验证据留在原run目录）。下一步可按r2做数据语义/去重审核、独立本地路径配置与浮点基线；本轮未训练或量化，不能把结构检查当精度通过。

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
