# ViTA 可复用 Skill 审核清单

状态：A1、A2、A3 已批准并完成本地化；ModelSim/Vivado 参考副本已于
2026-09-06 完成 `E:\competition` 路径适配；A4 暂缓；C1 不迁移。

## 目标与边界

- 来源工程：历史 ViTA 工程（仅作来源说明，不作为执行根）。
- 目标工程：`E:\competition\6_skill\`
- 本项目日志根目录：`E:\competition\7_logs\YYYY-MM-DD\`
- 性能/构建原始证据：`E:\competition\4_metrics\logs\<run-name>\`
- 迁移原则：复制而非剪切；路径、平台、结果标记和输出目录必须适配本工程；
  不修改来源工程原文件。

## 候选清单

| 编号 | ViTA Skill | 状态 | 目标路径 | 主要适配/风险 |
|---|---|---|---|---|
| A1 | `engineering-organization` | 已批准 | `6_skill/engineering-organization/` | 已将 ViTA 的 `11_process`、`HANDOFF`、`2_log` 规则改为本项目 `1_docs`–`7_logs`；保留“不删除、不覆盖、先核验引用”。 |
| A2 | `rtl-coding-standards` | 已批准 | `6_skill/rtl-coding-standards/` | 已补充本工程 `2_fpga/` 和 Logos-2/PDS 项目说明。 |
| A3 | `log-management` | 已批准（合并） | `6_skill/daily-engineering-log/SKILL.md` | 已将 `2_log` 改为 `7_logs`，大型证据路径改为 `4_metrics/logs`，未建立第二套日志入口。 |
| A4 | `project-handoff` | 条件批准 | `6_skill/project-handoff/` | 内容质量标准可复用；需移除/改写 ViTA 根 `HANDOFF.md`、`2_log/PROGRESS.md` 的固定假设。 |
| B1 | `modelsim_simulation` | 条件批准 | `6_skill/modelsim-simulation/` | 依赖 Mintty/Git Bash、ModelSim SE-64、Xilinx IP 库及 ViTA 路径；仅当本项目确实采用 ModelSim 时迁移，并须连同脚本做本地化。 |
| C1 | `global-node-sync` | 不建议迁移 | — | 强绑定历史工程根、`HANDOFF.md`、旧进度入口和旧 `5_verify`；本项目没有同等权威状态入口，直接迁移会制造错误同步规则。 |
| C2 | `vita-vivado-batch-sim` | 已适配（仅 XSim） | `6_skill/vita-vivado-batch-sim/` | 保留历史 skill 名，但输出统一到 `4_metrics/logs`，目标改为 EES-331 XC7Z020 CLG484-1/Vivado 2025.2，结果标记改为 `EES_VIVADO_RESULT`。AXI DMA 用例仍需按本项目 IP 重新生成后才可执行。 |

## 当前已存在的本地 Skill

`6_skill/daily-engineering-log/SKILL.md` 已是本项目专用副本，已使用 `7_logs` 路径。它不应与新的 `log-management` 并行维护两套互相冲突的日志规则。

## 审核结果与落地

- A1 `engineering-organization`：已复制到 `6_skill/engineering-organization/` 并改为本工程路径。
- A2 `rtl-coding-standards`：已复制到 `6_skill/rtl-coding-standards/` 并补充本工程项目说明。
- A3 `log-management`：未建立独立副本，已合并到 `6_skill/daily-engineering-log/SKILL.md`，日志根目录统一为 `7_logs/`。
- A4：暂缓，不执行复制。
- C1：不迁移。
- C2：保留历史目录名，已按 EES-331/Vivado 2025.2 完成路径与结果标记适配。

## 后续审核顺序

1. A1、A2、A3 已完成，无需重复迁移。
2. 如需交接质量标准，再单独审核 A4。
3. 如需 ModelSim 项目专用启动脚本，再审核 B1。
4. C1 保持不迁移。

## 历史批准格式

请按编号回复，例如：

```text
批准：A1、A2、A3（并入现有 daily-engineering-log）
暂缓：A4、B1
不迁移：C1、C2
```

本轮批准已执行完成；后续若要调整 A4 或 B1，请单独给出批准编号，避免扩大本次迁移范围。

## 2026-09-06 用户指令更新

用户明确要求将 ModelSim 后台仿真、ModelSim GUI 仿真和 Vivado 后台仿真 Skill
复制到本目录。已完成以下项目适配：

- `modelsim-local-sim/`
- `modelsim-gui-sim/`
- `vita-vivado-batch-sim/`

- 统一工作区根：`E:\competition`。
- 统一运行证据根：`E:\competition\4_metrics\logs\YYYY-MM-DD_<task>_runNN`。
- 统一工程日志根：`E:\competition\7_logs\YYYY-MM-DD`。
- 禁止把库、日志、波形或报告写入仓库根目录或冻结的 `E:\competition\2_fpga`。
- Vivado 脚本改为本工程 canonical launcher/checker 包装器，并使用
  `EES_VIVADO_RESULT`。

AXI DMA 参考流程仍不能直接声明 PASS；必须先按本项目 XCI/IP/BD 重新生成并
跑 no-IP smoke，再执行真实 IP 仿真。此次操作不修改原始全局 Skill。
