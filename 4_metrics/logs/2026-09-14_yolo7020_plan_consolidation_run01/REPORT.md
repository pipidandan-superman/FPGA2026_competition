# YOLO7020 部署计划 r2：本轮讨论整合

日期：2026-09-14。范围：用户指定部署计划的原位补充、工程日志与文档检查。未训练、未量化、未生成整数模型或golden、未修改RTL/冻结2_fpga、未构建或连接板卡。

交付：[部署计划r2](../../../1_docs/yolo7020_hardware_deployment_plan_20260914.md)。

## 修订内容

- 唯一主路线收敛为“浮点基线 → 硬件一致的整数参考 → 单模块验证 → 子图验证 → 整网验证 → 实时系统验收”，G0为前置/并行准备，G1–G7与B0–B4职责明确。
- 公共/自采数据可替代原配套训练数据；校准无标签、精度需检测框/语义映射、同域FP32/整数对照及独立测试分离。
- 最低量化合同、INT64独立oracle、QDQ边界、逐层首错、完整K累加与非线性/分支规则。
- 单模块测试矩阵、子图拼接顺序、静态整网仿真/板测、早期DMA/cache板测和最终实时验收的证据门。
- 逻辑golden/物理BIN-MEM布局、manifest/hash、pack/unpack、容量控制、变化后重导与联合包回退。
- 共享DDR/VDMA/预处理/网络组帧边界、显示连续性和严格配帧的取舍、缓冲所有权、流式优化与PC扩展非目标。
- 精度统计、时序/资源/延迟口径、故障停止、工具链/接口版本与当前未执行状态。

保留原静态参数、算量、资源预算及其证据链接；原文r1已复制为 [plan_before_r1.md](plan_before_r1.md)，没有删除或重建目标文件。所有编辑使用apply_patch，单次一个文件。

## 验证状态

结果：DOCUMENT_VALIDATION_PASS。66项结构/编码/内容覆盖/输入身份检查全部通过，13个主章节顺序完整，12个本地链接全部存在，代码围栏成对，UTF-8无替代字符；原best.pt/best.onnx哈希与修订前一致，r1快照哈希一致，四份工程记录存在，项目技能路径审计15项通过。原始输出见 [validation_console.log](validation_console.log)。

最终计划为32,826字符、625个按换行切分的行，SHA-256为D026E9B35B3FF9A87912F642EE2AE0F4ED367DADF1A3CB256D84E5B61D9FAE16。人工复核重点是阶段编号、原训练集非硬性条件、整数/浮点容差边界、早期板测不冒充整网通过，以及原预算/证据保留。

计划的技术阶段仍为QUANTIZATION_NOT_RUN / INTEGER_REFERENCE_NOT_IMPLEMENTED / RTL_NOT_IMPLEMENTED / BOARD_NOT_RUN，不因文档校验通过而升级。

## 复现

文档检查脚本：`validate_document.ps1`；运行命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/competition/4_metrics/logs/2026-09-14_yolo7020_plan_consolidation_run01/validate_document.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File E:/competition/4_metrics/scripts/audit_project_skill_paths.ps1
```

输出已保存为validation_console.log；修订前文档及模型哈希输出保存为before_console.log。浏览仅复核ORT静态量化和Ultralytics检测标注说明，未下载模型/数据/外部脚本。

## 项目规则的影响

project-workspace-policy与本地daily-engineering-log将证据限定于本run、交接限定于7_logs/2026-09-14四文件，保持2_fpga冻结。日记历史内容保留并显式标历史，当前第一动作指向r2数据准入和整数参考准备，不再等待队友训练集或选择早期PC预处理分支。
