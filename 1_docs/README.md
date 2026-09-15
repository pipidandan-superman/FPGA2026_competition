# 文档入口

2026-09-14 分类整理：本目录按下述分类组织；迁移对照见文末。历史日志（`7_logs`）与证据（`4_metrics/logs`）中的旧路径不回写，以本表为权威入口。

## 目录分类

| 分类 | 路径 | 内容 |
|------|------|------|
| 正式交付文档 | `doc/` | 日期命名的计划、报告、上板指南、图集、AIPC 报告（索引见 `doc/README.md`） |
| 赛题与方向 | `赛题方向/` | AMD 赛题原文与 MinerU 解析、评分页、设计方案、AMD 双模型路线图、平台选型手册（RK3568/紫光同创对比） |
| 器件原始资料 | `datasheets/` | ADV7511 用户指南与寄存器表、OV5640 数据手册、EES-331 User Guide（`datasheets/ov5640/` 与 `datasheets/ADV7511_Hardware_Users_Guide/manuals/` 厂商 PDF 仅本地保留，不入 Git） |
| 图纸 | `figures/` | YOLOv8n 结构图、端到端数据流图、摄像头底座图、Visio 源图 |
| 早期占位文档 | `legacy/` | architecture / hardware_setup / interface / Zynq_PS7_Config_Report（历史参考，UDP 协议 v1 见 interface.md） |
| 第三方教程资料 | `第三方资料/` | 开源舵机控制器-2025款（约 9.6G）、物联网综合课程设计资料（约 5.7G）；仅本地参考，不上传 Git |

## 根级活跃文档

- 总体设计方案：`赛题方向/设计方案_具身智能视觉分拣.md`
- PYNQ 从零复现：`PYNQ零基础开发与EES331摄像头工程实战.md`
- YOLO 手势 7020 硬件部署计划（当前活跃，r3）：`yolo7020_hardware_deployment_plan_20260914.md`
- YOLO GEMM PE 阵列架构基线（2026-09-15）：`doc/yolo7020_gemm_pe_architecture_2026-09-15.md`
- 当前控制开发：`doc/ees331_ble_axi_bram_development_plan_2026-09-12.md`

## 边界

本目录只保存正式设计文档、复现教程、接口定义和器件原始资料。构建日志、仿真输出、截图和 UART 等原始证据统一放在 `4_metrics/logs/<run-name>`；工程会话记录统一放在 `7_logs/YYYY-MM-DD`。历史解压包、自动提取文本、GitHub 上传草案和工具缓存不放在本目录。Git/GitHub 规则以 `.codex/skills/github-upload-policy/SKILL.md` 为准。

## 2026-09-14 迁移对照表

| 原路径 | 新路径 |
|--------|--------|
| `EES-331_HDMI显示适配修正方案.md` | `doc/` |
| `OV5640_PS以太网传输实施计划_2026-09-08.md` | `doc/` |
| `OV5640_UDP视频传输数据格式与上位机设计_2026-09-08.md` | `doc/` |
| `OV5640配置审计报告_2026-09-08.md` | `doc/` |
| `摄像头采集显示错误分析报告_2026-09-07.md` | `doc/` |
| `设计方案_具身智能视觉分拣.md` | `赛题方向/`（2026-09-12 先期移入，本轮补记） |
| `architecture.md` / `hardware_setup.md` / `interface.md` / `Zynq_PS7_Config_Report.md` | `legacy/` |
| `ADV7511_Hardware_Users_Guide/` | `datasheets/` |
| `ov5640/` | `datasheets/` |
| `pdf/EES-331 User Guide.pdf` | `datasheets/` |
| `pdf/AMD赛题.pdf`、`pdf/amd_sait题_mineru/`、`pdf/scoring_pages/` | `赛题方向/` |
| `pdf/RK3568*.pdf`、`pdf/紫光同创*.pdf` | `赛题方向/平台选型手册/` |
| `YOLOv8n_网络结构_7类_640.png`、`端到端数据流_EES331手势_v1.png`、`绘图1.vsdx` | `figures/` |
| `摄像头底座 .png`（文件名含尾部空格） | `figures/摄像头底座.png`（去空格） |
| `开源舵机控制器-2025款/` | `第三方资料/` |
| `物联网综合课程设计资料/` | `第三方资料/` |
| `doc/ADV7511KSTZ/`（旧副本） | 已删除（2026-09-14，用户确认）：全部文件与 `datasheets/ADV7511_Hardware_Users_Guide/` 一致且后者为超集 |
| `doc/amd_dual_model_arm_design_2026-09-12.md`（初版 08:23） | 已删除（2026-09-14，用户确认留新）：内容被 `赛题方向/amd_dual_model_arm_design_2026-09-12.md`（融合修订 r2，10:11）覆盖；旧版"FPGA 小模型部署程度"主题由 r2 第 5/6 章吸收。历史日志中的旧路径引用不回写 |

遗留说明：原 `物联网综合课程设计资料.zip` 已由用户于 2026-09-14 自行删除，目录本体保留在 `第三方资料/`，非异常。
