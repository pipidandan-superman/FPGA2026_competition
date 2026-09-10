# 2026-09-09 Next Start Guide

## First Action

PYNQ 部署若要动工：读 `E:\competition\1_docs\doc\EES-331_PYNQ从零部署计划_2026-09-09.md`，从阶段 0（资源确认）开始；新建工程目录前需用户明确授权（建议 `2_fpga/2_pynq_port/`）。

如仅需回顾赛题结论：读 `7_logs/2026-09-09/03_validation_summary.md` 中“赛题 PYNQ 条款核对”，再读 MinerU 原文 `4_metrics/logs/2026-09-09_amd_sait_pynq_mineru_run01/AMD赛题/auto/AMD赛题.md` 第 62–76、377–455、700–730 行附近段落。

## 起点结论（勿重复推导）

- 本队赛题 3.2 不强制 PYNQ；强制项为 Ryzen AI PC + 真实 FPGA/Zynq 硬件逻辑 + 两端通信。
- PYNQ-Z2 借用与 “Python 打通控制流程” 为鼓励项；通用 PYNQ Skill 为加分项。
- 现行 EES-331 + Vivado/Vitis 路线合规，无需为资格而迁移 PYNQ。

## Forbidden Immediate Actions

- 不得修改 `2_fpga/` 冻结基线。
- 不得在未确认 EES-331 Linux/PYNQ 镜像可用前启动 PYNQ 移植。
- 不得把“能跑 Python”写成“已有 PYNQ 支持”（2026-09-01 结论仍然有效）。

## Success Criteria

若决定评估 PYNQ 路线：产出一份 EES-331 PYNQ 镜像可行性记录（镜像来源/构建方式、启动方式、Overlay 加载演示），存入新的 `4_metrics/logs/YYYY-MM-DD_<task>_runNN`。

## Blocker 与最小下一步

无阻塞。最小下一步：向赛方申请/确认 PYNQ-Z2 借用，或在 EES-331 上验证 PYNQ 镜像启动（二选一，由队伍决策）。
