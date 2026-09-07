# GitHub 协同上传准则（审核草案）

- 状态：`DRAFT_FOR_REVIEW`
- 版本：v1.1-draft
- 适用仓库：`FPGA2026_competition`
- 适用路径：`E:\competition`
- 目标：两人并行开发时保持提交可审计、冲突可控、`main` 始终可运行。
- 生效方式：本文件必须先由两名成员审核批准；批准后才能转化为项目 skill、分支保护和检查脚本。

## 1. 核心结论

`main` 是受保护的集成基线：

1. 全员禁止直接 `git push origin HEAD:main`。
2. 任何内容进入 `main` 都必须通过 Pull Request。
3. 任何进入 `main` 的 PR 必须由另一名成员审核通过。
4. 两人各保留一条长期完整开发分支；分支内可以包含代码、文档、日志和证据。
5. 不再按“硬件路径 / 软件路径 / 共同路径”做硬性所有权拆分。

## 2. 分支模型

两位成员各使用一条长期完整开发分支：

```text
codex/full/member-a
codex/full/member-b
```

长期分支规则：

1. 每条分支由对应成员负责推进，可直接 push 自己的分支。
2. 禁止强推、删除远端分支、重写已共享历史。
3. 分支应保持相对可用；大实验可以先在临时分支验证，再合回自己的长期分支。
4. 临时分支可以按需建立，但不是必选：

   ```text
   codex/tmp/YYYY-MM-DD-短主题
   ```

5. 不允许把长期分支当作未审查的 `main` 使用；每次要合入 `main` 时仍必须开 PR 并由另一人审核。

## 3. 标准上传流程

### 3.1 开始工作

1. 先确认本地状态：

   ```powershell
   git status --short
   git branch --show-current
   git rev-parse HEAD
   ```

2. 同步受保护的基线：

   ```powershell
   git switch main
   git pull --ff-only
   ```

3. 切换或更新自己的完整开发分支：

   ```powershell
   git switch codex/full/member-a
   git pull --ff-only
   ```

### 3.2 提交变更

1. 一次提交只说明一个明确目的。
2. 只显式添加目标文件：

   ```powershell
   git add -- path/to/file
   git diff --cached --name-only
   git diff --cached --check
   ```

3. 禁止 `git add .`。
4. 禁止把 Vivado/Vitis 运行目录、缓存、临时波形、大体积压缩包默认提交；只有纳入证据清单的产物才能进入 `4_metrics/**`。
5. 工程日志只写入 `7_logs/YYYY-MM-DD/`，原始证据只写入 `4_metrics/logs/<run-name>/`。

### 3.3 提交信息

```text
feat: 简短说明新增能力
fix: 简短说明修复缺陷
docs: 简短说明文档变更
evidence: 简短说明证据归档
freeze: 简短说明冻结基线变更
```

冻结产物必须在提交信息和 PR 描述中明确列出 SHA-256、来源路径和对应证据目录。

## 4. Pull Request 规则

### 4.1 必要条件

1. 源分支必须是 `codex/full/member-a`、`codex/full/member-b` 或明确的临时分支。
2. 目标分支必须是 `main`。
3. PR 必须至少获得另一名成员 approve。
4. PR 不能包含 force push 或历史重写。
5. CI 或本地检查必须通过。
6. PR 描述必须包含：
   - 变更原因；
   - 变更范围；
   - 验证结果和 PASS/FAIL 边界；
   - 证据路径；
   - 已知限制；
   - 是否影响冻结基线。

### 4.2 PR 标题

推荐使用：

```text
feat: 主题
fix: 主题
docs: 主题
evidence: 主题
freeze: 主题
```

如果影响冻结基线，额外加 `[FREEZE]` 前缀。

### 4.3 粒度要求

1. 不再强制按路径域拆 PR，但仍建议按主题拆分。
2. 一个 PR 避免同时混合新功能、大重构和无关整理。
3. 大型 PL、PS、文档或证据变更可以分开提交，但合入节奏由成员协商。

## 5. 审核规则

审核人重点检查：

1. 是否能解释为什么做这个变更。
2. 是否只包含声明过的范围。
3. 是否有完整证据，且证据路径可访问。
4. 是否混淆了仿真 PASS、编译 PASS、板级视觉 PASS 和完整验收 PASS。
5. 是否改动、删除或覆盖冻结 BIT/XSA/ELF。
6. 是否把无证据结论写成 PASS。
7. 是否存在意外生成物。
8. 是否保持工程日志和原始证据边界。
9. 是否有可回退方式。
10. 是否影响队友正在进行的实验。

审核结果：

- `APPROVE`：可合入。
- `REQUEST_CHANGES`：必须修改后重新审核。
- `COMMENT`：只提出说明或后续问题，不阻塞合入。
- `HOLD`：存在未澄清的冻结基线、证据或冲突风险，暂不合入。

## 6. 冻结与证据边界

1. `2_fpga/` 是冻结板级验证工程，默认只读。
2. 没有当前明确授权时，禁止编辑、重建、移动或覆盖 `2_fpga/`。
3. 冻结 BIT/XSA/ELF/关键源码必须保留 SHA-256。
4. 新实验使用新的证据目录：

   ```text
   4_metrics/logs/YYYY-MM-DD_<task>_runNN/
   ```

5. `4_metrics/logs/...` 是原始证据；`7_logs/YYYY-MM-DD/` 是工程记录和索引。
6. `7_logs/YYYY-MM-DD/03_validation_summary.md` 必须链接对应原始证据目录。
7. 没有 raw log、UART、照片、波形或构建日志时，不能宣称功能 PASS。

## 7. 同步与冲突处理

### 7.1 日常同步

1. 每次开始前从最新 `origin/main` 同步自己的长期分支。
2. PR 合入后，另一名成员不必立刻逐文件审查队友的完整分支，只需在下次开发前同步。
3. 集成由 GitHub PR 完成；不要用人工复制文件替代 PR。

### 7.2 同一文件冲突

1. 先保留双方的事实、日期、哈希、PASS/FAIL 边界和证据路径。
2. 再重新组织文字或代码结构。
3. 冲突解决不得删除对方证据结论。
4. 如果无法判断事实归属，把 PR 设为 `HOLD`，在评论中说明问题。

### 7.3 长期分支落后

1. 使用 GitHub 的 update branch，或在本地：

   ```powershell
   git switch codex/full/member-a
   git pull --ff-only
   git merge main
   ```

2. 禁止强推。
3. 如果历史已经分叉，不能强推覆盖；必须保留双方提交并用普通 merge 解决。

## 8. 必须拒绝合入的情况

出现下列任一情况，reviewer 必须拒绝合入：

1. 缺少另一名成员 approve。
2. 缺少验证证据，或把无证据结果写成 PASS。
3. 使用 `git add .` 导致无关生成物、缓存或临时目录进入提交。
4. 强推、重写历史、绕过分支保护。
5. 没有说明原因就覆盖、移动或重建冻结 BIT/XSA/ELF。
6. 删除对方的哈希、证据、PASS/FAIL 边界或禁止动作。
7. PR 描述无法说明变更目的。
8. 工程日志写入禁止路径。
9. 把冻结工程当普通实验对象随意重建。
10. 冲突解决时丢失可回退信息。

## 9. 批准后的实施物

用户审核通过后创建或配置：

1. 项目 skill：

   ```text
   E:\competition\.codex\skills\github-upload-policy\SKILL.md
   ```

2. `main` branch protection：

   ```text
   require pull request
   require one approval
   dismiss stale approvals
   require status checks
   禁止 force push
   禁止删除分支
   ```

3. 上传前检查脚本：

   ```text
   E:\competition\4_metrics\scripts\audit_github_upload_discipline.ps1
   ```

4. 合入检查清单模板。
5. 正式版文档：

   ```text
   E:\competition\1_docs\GitHub协同上传准则.md
   ```

批准字段：

```text
成员 A 批准：
成员 B 批准：
批准日期：
生效版本：
```

## 10. 审核问题

请明确回答：

1. 两位成员对应 `codex/full/member-a` 和 `codex/full/member-b` 中的哪一条？
2. 是否接受 `main` 全员禁止直接 push？
3. 是否接受 PR 必须由另一名成员 approve？
4. 长期分支是否允许直接 push 自己名下分支？
5. 冻结产物是否只做哈希/清单检查，不由 CI 自动重建？
