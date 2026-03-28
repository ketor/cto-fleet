---
name: team-pipeline
description: 多 team 接力执行器——自动按序调用多个 team-* skill，上一个 skill 的输出作为下一个的输入上下文。支持预定义流水线和自定义组合。使用方式：/team-pipeline --steps=team-security,team-refactor [--auto] [--once] [--lang=zh|en] 任务描述
argument-hint: --steps=skill1,skill2,... [--auto] [--once] [--lang=zh|en] 任务描述
---

<!-- PREAMBLE_SECTION_START -->
## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE <old> <new>`: read `~/.claude/skills/cto-fleet/cto-fleet-upgrade/SKILL.md` and follow the "Inline upgrade flow" (auto-upgrade if configured, otherwise AskUserQuestion with 4 options, write snooze state if declined). If `JUST_UPGRADED <from> <to>`: tell user "Running cto-fleet v{to} (just updated!)" and continue.
<!-- PREAMBLE_SECTION_END -->

**参数解析**：从 `$ARGUMENTS` 中检测以下标志：
- `--steps=skill1,skill2,...`：**必填**，要依次执行的 skill 列表（逗号分隔，如 `--steps=team-security,team-refactor`）
- `--auto`：完全自主模式（不询问用户任何问题，全程自动决策）
- `--once`：单轮确认模式（执行前确认一次，之后全程自动执行）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后保留完整的任务描述（`--steps`、`--auto`、`--once`、`--lang` 之外的所有内容即为任务描述）。

| 模式 | 用户确认范围 | 失败处理 |
|------|-------------|---------|
| **标准模式**（默认） | 执行前确认 + 每步完成后确认继续 | 询问用户：跳过/重试/终止 |
| **单轮确认模式**（`--once`） | 仅执行前确认一次 | 自动重试一次，仍失败则终止 |
| **完全自主模式**（`--auto`） | 不询问用户 | 自动重试一次，仍失败则终止并报告 |

---

## 预定义流水线

支持使用别名代替 `--steps`。当 `--steps` 的值匹配以下别名时，自动展开为对应的 skill 列表：

| 别名 | 展开为 steps | 场景 |
|------|-------------|------|
| `security-fix` | `team-security` → `team-refactor` | 安全审计 + 修复 |
| `design-to-code` | `team-rfc` → `team-dev` → `team-review` | 设计到实现 |
| `incident-full` | `team-incident` → `team-postmortem` → `team-runbook` | 故障全流程 |
| `release-ready` | `team-test` → `team-security` → `team-release` | 发布前检查 |
| `arch-improve` | `team-arch` → `team-adr` → `team-refactor` | 架构改进 |

使用示例：
- `/team-pipeline --steps=security-fix --auto 检查并修复安全问题`
- `/team-pipeline --steps=team-security,team-refactor --once 审计项目安全性并修复`
- `/team-pipeline --steps=design-to-code --lang=en design and implement caching layer`

---

## 流程概览

```
阶段零  参数解析 → 解析 --steps（或别名）→ 构建步骤队列
         ↓
阶段一  计划展示 → 显示执行计划 → 确认（按模式决定）
         ↓
阶段二  逐步执行 → 调用 Skill → 提取关键输出 → 传递上下文 → 下一步
         ↓
阶段三  收尾 → 汇总报告 + 记录日志
```

---

## 角色定义

本 skill 不使用 TeamCreate 创建多 agent 团队。Pipeline 以**单 agent 编排模式**运行，串行调用子 skill 并传递上下文。

<!-- HANDOFF_SECTION_START -->
## 文件交接规范（File-Based Handoff）

所有 agent 间传递详细报告时，必须采用**文件交接模式**（防止上下文溢出触发 20MB 限制）：

1. **写入文件**：将完整报告写入团队工作目录：
   - 目录路径：`/tmp/{team-name}/`（team lead 在 TeamCreate 后执行 `mkdir -p /tmp/{team-name} && chmod 700 /tmp/{team-name}`）
   - 单个文件 ≤ 2000 行；超大报告拆分为 summary + details 文件
2. **发送引用**：通过 SendMessage 仅发送（≤500 字符）：
   - 文件路径（1 行）
   - 关键摘要（含核心指标/发现/评分）
3. **按需读取**：接收方使用 Read 按需读取文件，发送方不内联完整内容
4. **路径转发**：team lead 转发报告时只转发文件路径 + 摘要，不 Read 后再 SendMessage
5. **遵从校验**：team lead 收到超 1000 字符且不含 `/tmp/team-` 路径前缀的消息时，要求 agent 以文件交接模式重发

**文件命名规范**：

| 角色输出 | 文件名 |
|---------|--------|
| Scanner 报告 | `scanner-report.md` |
| Reviewer-N 第R轮 | `reviewer-{N}-round-{R}.md` |
| 合并报告第R轮 | `merged-report-round-{R}.md` |
| 根因分组 | `root-cause-groups-round-{R}.md` |
| Fixer 第R轮 | `fixer-round-{R}.md` |
| Tester 第R轮 | `tester-round-{R}.md` |
| Architect-N 方案 | `architect-{N}-design.md` |
| 任务拆解 | `task-breakdown.md` |
| Coder-N 任务T | `coder-{N}-task-{T}.md` |
| 审查任务T | `review-task-{T}.md` |
| 集成测试第R轮 | `integration-test-round-{R}.md` |
| 最终报告 | `final-report.md` |

> 仅当角色存在于当前 skill 时使用对应命名。未列出的角色用 `{role}-{context}.md` 格式。
<!-- HANDOFF_SECTION_END -->


原因：每个子 skill 内部已有完整的多 agent 团队。编排器再创建团队会导致 agent 嵌套过深、上下文膨胀。编排器的职责是**调度、传递上下文和汇总**，不是分析。

---

## 阶段零：参数解析

### 步骤 1：解析 --steps 并构建步骤队列

1. 从 `$ARGUMENTS` 中提取 `--steps=...` 的值
2. 如果值匹配预定义别名 → 展开为对应的 skill 列表
3. 如果值是逗号分隔的 skill 名称 → 直接使用
4. 验证每个 skill 名称以 `team-` 开头（如用户省略前缀，自动补全 `team-`）
5. 如果 `--steps` 缺失 → 报告错误："必须指定 --steps 参数"，退出

**构建步骤队列**：将 skill 列表转为有序队列，记录总步骤数。

### 步骤 2：提取任务描述

从 `$ARGUMENTS` 中移除所有已识别的标志（`--steps`、`--auto`、`--once`、`--lang`），剩余部分即为任务描述。

如果任务描述为空 → 报告错误："请提供任务描述"，退出。

---

## 阶段一：计划展示与确认

### 步骤 3：显示执行计划

向用户展示将要执行的流水线：

```
╔══════════════════════════════════════════════════════╗
║              PIPELINE — 执行计划                      ║
╠══════════════════════════════════════════════════════╣
║                                                      ║
║  任务：{任务描述}                                     ║
║                                                      ║
║  执行步骤：                                           ║
║  [1] team-security    安全审计                        ║
║   ↓                                                  ║
║  [2] team-refactor    重构修复                        ║
║                                                      ║
║  模式：{标准/单轮确认/完全自主}                        ║
║  语言：{zh/en}                                        ║
║                                                      ║
║  将依次执行：team-security → team-refactor             ║
╚══════════════════════════════════════════════════════╝
```

### 步骤 4：确认执行

- **标准模式**：AskUserQuestion 确认执行计划（选项：开始执行 / 调整步骤 / 取消）
- **单轮确认模式**（`--once`）：AskUserQuestion 确认一次（选项：开始执行 / 取消）。确认后全程自动。
- **完全自主模式**（`--auto`）：跳过确认，直接开始执行。

---

## 阶段二：逐步执行

### 步骤 5：执行循环

初始化上下文摘要为空字符串。对步骤队列中的每个 skill，按顺序执行：

#### 5a. 显示进度

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[{当前步}/{ 总步数}] 启动 {skill-name}...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

#### 5b. 构建调用参数

为当前 skill 构建 args 字符串：
- 传递模式标志：如果是 `--auto` 模式，传 `--auto`；如果是 `--once` 模式，传 `--auto`（子 skill 在 pipeline 内应自动执行）
- 传递语言：`--lang={lang}`
- 传递任务描述：原始任务描述
- 传递上一步摘要（如有）：`\n\n---\n上一步（{上一步skill名}）的关键发现：\n{上下文摘要}`

最终 args 格式：`--auto --lang={lang} {任务描述} {上一步摘要}`

#### 5c. 调用 Skill

使用 **Skill 工具**（同步调用）执行当前 skill：
```
Skill: {skill-name}
args: {构建好的 args}
```

**重要**：使用 Skill 工具同步调用，不要用 Agent 并行。Pipeline 是串行的，每步必须等上一步完成。

#### 5d. 提取关键输出

当前 skill 完成后，提取其关键输出作为下一步的上下文。提取内容包括：
- **发现清单**：问题列表、风险项、审计结果
- **评分/指标**：共识度、严重度分级、覆盖率等量化数据
- **建议/决策**：修复建议、架构决策、改进方案
- **变更清单**：修改了哪些文件、重构了什么

将提取的内容压缩为**不超过 500 字的摘要**，作为上下文传递给下一步。

**上下文结构模板**（LLM 提取时参考此格式）：

```
{
  "status": "completed|failed",
  "key_findings": ["发现1", "发现2", ...],
  "metrics": {"score": 85, "issues_found": 3, ...},
  "changes": ["修改了文件A", "重构了模块B", ...]
}
```

> 注意：此模板为 LLM 提取的格式指引，非强制 JSON 输出。实际上下文以自然语言摘要形式传递，但应涵盖上述四个维度。

#### 5e. 显示步骤完成摘要

```
✅ [{当前步}/{总步数}] {skill-name} 完成
   关键发现：{1-3 条核心要点}
```

#### 5f. 步间确认（仅标准模式）

- **标准模式**：AskUserQuestion 确认是否继续下一步（选项：继续 / 跳过下一步 / 终止流水线）
- **单轮确认模式**：自动继续
- **完全自主模式**：自动继续

---

## 阶段三：收尾

### 步骤 6：汇总报告

所有步骤完成后，按 `--lang` 指定的语言输出汇总报告：

```markdown
# Pipeline 执行报告

> 任务：{任务描述}
> 步骤：{skill-1} → {skill-2} → ... → {skill-N}
> 模式：{标准/单轮确认/完全自主}
> 完成时间：YYYY-MM-DD HH:MM

---

## 执行摘要

| 步骤 | Skill | 状态 | 关键结论 |
|------|-------|------|---------|
| 1 | team-security | ✅ 完成 | 发现 3 个高危漏洞，2 个中危 |
| 2 | team-refactor | ✅ 完成 | 修复 3 个高危漏洞，重构 2 个模块 |

---

## 各步骤详情

### [1/N] {skill-name}
{该步骤的关键输出摘要}

### [2/N] {skill-name}
{该步骤的关键输出摘要}

---

## 总体状态

- **成功步骤**：X/{总步数}
- **跳过步骤**：X（{原因}）
- **失败步骤**：X（{原因}）

## 后续建议

{根据流水线结果，建议的下一步操作}
```

### 步骤 7：记录执行日志

```bash
mkdir -p ~/.gstack/analytics
echo '{"skill":"team-pipeline","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","steps":"STEPS_LIST","completed":COMPLETED_COUNT,"skipped":SKIPPED_COUNT,"failed":FAILED_COUNT}' >> ~/.gstack/analytics/skill-usage.jsonl 2>/dev/null || true
```

替换占位符为实际值。

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| `--steps` 参数缺失 | 报告错误，展示预定义别名表，退出 |
| 别名或 skill 名称无法识别 | 报告错误，列出可用的 team-* skill，退出 |
| 任务描述为空 | 报告错误，提示用户提供任务描述，退出 |
| 某步骤执行失败（标准模式） | 显示失败原因，AskUserQuestion：跳过继续 / 重试 / 终止 |
| 某步骤执行失败（`--once`/`--auto`） | 自动重试一次；仍失败则终止流水线并输出已完成步骤的部分报告 |
| 子 skill 未安装 | 跳过该步骤，报告中标注"skill 不可用" |
| 用户中断执行 | 输出已完成步骤的部分汇总报告 |

---

## 核心原则

- **串行不并行**：Pipeline 严格按序执行，每步等待上一步完成后再开始
- **上下文接力**：每步的关键输出自动提炼并传递给下一步，形成完整的分析-修复链
- **编排不分析**：编排器只负责调度、上下文传递和汇总，不直接做分析或修改
- **优雅降级**：某步失败不一定终止整个流水线，视模式和用户选择决定
- **Skill 同步调用**：使用 Skill 工具同步调用每个 step，不用 Agent 并行
- **不创建团队**：使用单 agent 编排 + 子 skill 内部团队，避免 agent 嵌套

---

## 需求

$ARGUMENTS

<!-- ERROR_HANDLING_SECTION_START -->
### 错误处理

| 场景 | 处理方式 |
|------|---------|
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从最近的检查点恢复 |
| 某阶段产出质量不达标 | 记录问题，在收尾阶段汇总，不阻塞后续流程（除非是熔断条件） |
| 用户中途修改需求 | 暂停当前阶段，重新评估影响范围，必要时回退到受影响的最早阶段 |

### 熔断机制（不可跳过）

以下条件触发时，**无论 `--auto` 还是 `--once` 模式，都必须暂停并向用户确认**：

- 共识度 < 50%（双路分析严重分歧）
- 迭代超过最大轮数仍未达标
- 关键依赖缺失（无法继续执行的前置条件不满足）

触发熔断时，向用户展示：当前状态、分歧/问题摘要、建议的下一步选项。
<!-- ERROR_HANDLING_SECTION_END -->


<!-- CONSENSUS_SECTION_START -->
### 共识度计算

team lead 按五维度评估双路分析的共识度：

| 维度 | 权重 |
|------|------|
| 发现一致性（相同问题/结论） | 20% |
| 互补性（独有但不矛盾的发现） | 20% |
| 分歧程度（直接矛盾的结论） | 20% |
| 严重度一致性（同一问题的严重等级差异） | 20% |
| 覆盖完整性（两路合并后的覆盖面） | 20% |

共识度 = 各维度加权得分之和

- **≥ 60%**：自动合并，分歧项由 team lead 裁决
- **50-59%**：合并但标注分歧，收尾时汇总争议点
- **< 50%**：触发熔断，暂停并向用户确认方向
<!-- CONSENSUS_SECTION_END -->

