---
name: engineering-organization
description: Safely organize the competition engineering workspace, classify files, normalize live paths, and audit migration references without deleting or overwriting files. Use for explicit file migration or directory organization tasks.
---

# Engineering Organization

## Responsibility boundary

只处理用户明确要求的文件分类、迁移、路径规范化和引用核验。普通整理不触发全局同步，不更新长期状态或交接文件，除非用户明确把它作为关键节点交接的一部分。

## Safety rules

- 默认不可删除、不可覆盖、不可静默替换文件。
- 删除行为必须有用户明确授权、精确目标核验和结果记录。
- `7_logs` 中的历史日志和 `4_metrics` 中已接受证据不得做美容式批量改写。
- 不移动冻结参数、已接受证据、活动 RTL 或第三方环境，除非用户明确授权并完成依赖审计。
- 保持活动源文件唯一，必要时使用说明性指针而不是复制品。

## Workflow

1. 盘点并分类活动源、配置、文档、日志、验证证据、生成物和历史资产。
2. 记录源路径、目标路径、原因和基线计数。
3. 核验目标冲突和所有活动引用。
4. 使用明确路径执行小批量迁移；每批完成后复核。
5. 更新活动脚本、工程清单和文档中的 live path；历史证据不做美容式批量改写。
6. 记录迁移结果和剩余兼容入口。

## Acceptance checks

- 目标冲突为零；
- 活动引用可解析；
- 删除目标均有授权和记录；
- 历史证据未被误删或覆盖；
- 当前工程的日志权威入口是顶层 `7_logs/`；指标原始证据入口是 `4_metrics/`。若新增项目状态文件，必须在 README 中明确其权威性。
