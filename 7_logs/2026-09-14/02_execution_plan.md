# 2026-09-14 执行计划

## 当前：1_docs 分类整理与去重（2026-09-14）

顺序：全量清单对比（分支跟踪127 vs 磁盘127）→ 按六分类迁移 → 活跃文档引用逐个修复（历史日志不动）→ 重复项逐文件diff验证超集/覆盖关系后经用户确认删旧 → 集合代数同步分支（87旧路径git rm＝73重命名+14幽灵删除，79新路径显式清单git add，排除第三方资料/ov5640/ADV7511 manuals）→ 提交推送93eae1f。第三方资料与厂商PDF按github-upload-policy本地保留。

## 当前：r3文档与GitHub发布（2026-09-14）

发布收据：内容提交f7c55a1已推送个人分支，已创建[PR #8](https://github.com/pipidandan-superman/FPGA2026_competition/pull/8)指向main。GitHub显示Awaiting approval / Merging is blocked，需另一位有写权限成员批准，尚未合并。xiaokaiyuan未出现在审核人搜索结果，未成功指派。下一动作是队友审核最终提交；本轮不绕过保护、不操作他人PR #7。r3文档66项检查与路径审计15项通过，量化/硬件阶段仍未执行。

顺序：核对下载JSON与模型合同→修订r3和MODEL.md→保留历史证据并标明过时停点→在独立个人工作树同步origin/main→逐文件清单复制、哈希/链接/暂存审计→提交推送→创建PR并请求另一成员审核。原E:/competition大量无关改动及个人工作树4个历史未跟踪文件保持原样。发生冲突或审核未满足则停止合并，不强推或绕过保护。

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

先读取原r1和同日数据/预处理讨论，保存r1快照，再原位整合第4/9/10/12节并新增第13节当前状态；更新工程记录后检查链接、编码、章节、覆盖项和原模型哈希。所有改动仅文档/记录，旧图集和模型不动。后续实施从数据准入与最低算术合同并行准备开始，不以等待队友数据或完整RTL为前提。

[部署计划r2](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[修订与文档验证](../../4_metrics/logs/2026-09-14_yolo7020_plan_consolidation_run01/REPORT.md)。

## 本日历史记录（与r2冲突时以以上当前状态为准）

## 补充：允许使用公共手势数据

后续先检查公共数据任务/场景/类别语义，再划分去重的校准与独立评估集；在同尺寸同外部集比较 FP32/INT8，最后补部署摄像头验证。仅校准或 golden 导出不要求标签。

[公共数据适用条件](../../4_metrics/logs/2026-09-14_yolo_external_data_guidance_run01/REPORT.md)。

## 最新：量化启动条件检查

本轮只读检查权重、静态量化接口、数据集命名清单和历史原始帧。后续按算术合同/整数参考/导出器 -> 数据定位与同尺寸浮点基线 -> PTQ 校准 -> 硬件规则推理与独立精度对照 -> 版本化 golden 执行；数据准备和参考开发可以并行推进，无需等待完整硬件设计。

[本轮检查与后续条件](../../4_metrics/logs/2026-09-14_yolo_quantization_readiness_run01/REPORT.md)｜[原始检查输出](../../4_metrics/logs/2026-09-14_yolo_quantization_readiness_run01/console.log)。

## 最新：YOLO手势7020硬件部署详细计划完成

本轮执行静态profile与假设资源计算，未训练、量化或实现RTL。后续依G0数据/目标->G1尺寸与量化->G2整数golden/IR->G3单算子->G4子图调度->G5板上全图->G6视频共存->G7性能长稳执行。PS首先负责DFL/NMS，PL承担主网络算子；未知算子不得静默回退。

[详细部署计划](../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)｜[本轮证据](../../4_metrics/logs/2026-09-14_yolo7020_deployment_plan_run01/REPORT.md)。

## 最新：最终目标调整为板上YOLO与PC其他模型协作

用户明确最终目标为PS+PL独立完成YOLOv8手势检测并与HDMI显示融合，网口向PC提供原图/ROI/结果用于另一模型。本轮完成合理性分析；早前仅优化PC预处理/RGB565传输的建议作为局部历史方案保留。下一步应围绕量化算子映射、共享DDR推理通道、同帧框图匹配和干净原图加元数据协议设计，详见[报告最新目标](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)。当前是DESIGN_ONLY，无新增硬件实现或板测。本地完整检测应在PC断开时仍工作，检测率与HDMI刷新率分开验收。

## 用户追问后的方向修订

以净提速为目标，先测PS快照/CRC/分包/发送及PC显示等待推理。默认5 fps和每16包1 ms节流已在源码确认，但尚无本轮分段实测。额外原图+ROI会增加总流量；首版不默认增加letterbox/CRC副本。评估RGB565单流上传、PC精确展开以保持原画面，或用户接受低分辨率后再评估PL缩放支路。新增图像写DDR通常需独立S2MM，元数据可走AXI-Lite。详细分析与代码位置见[报告补充](../../4_metrics/logs/2026-09-14_pl_preprocess_analysis_run01/REPORT.md)。当前为咨询分析完成，未执行功能变更或板测；后续先做可归因测量。

## 本轮已执行的只读分析

1. 从 `3_host/model/MODEL.md` 和 PC 推理源码核对模型输入、阈值与数据布局。
2. 从 UDP 接收源码核对 `640x480x3`、BGR 字节序和最新帧队列策略。
3. 从冻结 `2_fpga` 的采集 RTL、BD 和连接清单核对 RGB565->RGB888、VDMA 和 HDMI 路径。
4. 检查旧灰度、二值化、下采样 RTL，确认它们未接入当前 BD且不兼容当前 YOLO。
5. 使用最近实现报告仅评估资源可行性背景，不把既有报告外推为新增逻辑通过。

## 建议的后续实现顺序（尚未执行）

1. 在独立工程/副本加入无反压像素旁路、帧号、时间戳和完整帧提交。
2. 先保持当前 640 输入合同，只做颜色打包和可选 letterbox。
3. 建立 PC 原预处理与 PL 输出的 100 帧数值对齐测试。
4. 做旁路过载、DMA/DDR争用和 HDMI/UDP 连续性测试。
5. 数值和视频隔离通过后，再独立评估 ROI/320 输入及精度变化。

## 风险与回退

- AXI-Stream 分叉若共享 `TREADY` 会反压显示；必须使用独立 FIFO 和整帧丢弃策略。
- 第二 DMA 会争用 DDR；优先将低带宽 ROI/元数据写 BRAM。
- ROI、缩放和光度变换会改变模型分布；不通过同帧精度对照则回退当前 PC 预处理。
- 任一显示异常立即禁用旁路并恢复原冻结位流/软件，不在失败现场叠加修改。
