---
name: team-report
description: 启动一个报告生成团队（data-gatherer/writer×2/reviewer），通过多源数据采集+双写手独立撰写+交叉审查，生成面向不同受众的高质量技术报告。使用方式：/team-report [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--mode=board|team|investor|briefing] [--period=1w|2w|1m|1q] [--output=file|stdout] [--format=markdown|email|slack|ppt-outline] [--lang=zh|en] 项目路径或描述
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--mode=board|team|investor|briefing] [--period=1w|2w|1m|1q] [--output=file|stdout] [--format=markdown|email|slack|ppt-outline] [--lang=zh|en] 项目路径或描述
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
- `--auto`：完全自主模式（不询问用户任何问题，全程自动决策）
- `--once`：单轮确认模式（将所有需要确认的问题合并为一轮提问，确认后全程自动执行）
- `--mode=board|team|investor|briefing`：报告模式（默认 `team`）
- `--period=1w|2w|1m|1q`：报告周期（默认 `1w`）
- `--output=file|stdout`：输出方式（默认 `stdout`）
- `--format=markdown|email|slack|ppt-outline`：输出格式（默认 `markdown`）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

### 多格式输出支持

`--format` 参数控制最终报告的呈现格式，适配不同分发场景：

| 格式 | 说明 | 结构 |
|------|------|------|
| `markdown` | 标准 Markdown 格式（默认） | 完整报告 |
| `email` | 邮件摘要格式 | 主题行 + 3-5 要点 + 行动项 |
| `slack` | Slack 消息格式 | emoji 标记 + 简短段落 + 链接 |
| `ppt-outline` | PPT 大纲格式 | 每页标题 + 3 要点 + speaker notes |

格式与模式组合建议：

| 模式 | 推荐格式 | 原因 |
|------|---------|------|
| `board` | `ppt-outline` 或 `email` | 高管习惯幻灯片或邮件简报 |
| `team` | `markdown` 或 `slack` | 团队常用 Markdown 文档或 Slack 频道 |
| `investor` | `ppt-outline` | 投资方演示场景 |
| `briefing` | `slack` 或 `email` | 晨报适合即时推送 |

各格式输出规范：

**`email` 格式**：
- 第一行为邮件主题：`[{mode}报告] {project_name} — {period} 总结`
- 正文以 3-5 个关键要点开头（bullet points）
- 末尾附"需要关注的行动项"列表
- 总长度控制在屏幕一屏以内

**`slack` 格式**：
- 使用 Slack 兼容 mrkdwn 语法
- 状态用 emoji 标记：✅ 完成、🔴 阻塞、⚠️ 风险、📈 上升、📉 下降
- 段落间用分隔线 `---`
- 关键数字用 `*bold*` 强调
- 末尾附相关链接（如报告完整版文件路径）

**`ppt-outline` 格式**：
- 每页输出格式：`## Slide N: {标题}`
- 每页 3 个要点（bullet points），每点不超过 15 字
- 每页附 `> Speaker Notes:` 块，包含展开说明（2-3 句）
- 建议页数：board 5-8 页，investor 6-10 页，team 8-12 页

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 数据源确认 + 草稿选择 + 最终报告确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅最终报告确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下条件节点自动决策规则：
- **数据源不完整** → data-gatherer 尽力采集可用数据，在最终报告中标注缺失项
- **两位 writer 草稿风格差异大** → reviewer 取各方最佳段落合并，收尾时汇总
- **数据文件过期（>7 天）** → 报告中标注数据新鲜度警告，继续生成
- **关键数据完全缺失（无 git log 且无 JSON 数据）** → **不可跳过，必须暂停问用户**（熔断机制）
- **两位 writer 草稿结论矛盾（如进度判断相反）** → **不可跳过，必须暂停问用户**（熔断机制）

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效（关键数据完全缺失、草稿结论矛盾时仍必须暂停问用户）。

报告模式说明：

| 模式 | 目标受众 | 内容要求 | 篇幅 |
|------|---------|---------|------|
| `board` | 董事会/高管 | 非技术语言。进度指标、风险、阻塞项、资源请求。 | 1-2 页 |
| `team` | 团队内部 | 迭代总结。已交付功能、阻塞项、速度趋势、团队表彰。 | 2-3 页 |
| `investor` | 投资方 | 产品动量叙事。用户影响、技术壁垒、团队扩展情况。 | 1-2 页 |
| `briefing` | 团队晨报 | 快速概览。隔夜事件、依赖漏洞、关键指标。 | 半页 |

报告周期说明：

| 周期 | 数据范围 | 说明 |
|------|---------|------|
| `1w` | 最近 1 周 | 默认值，适合周报和晨报 |
| `2w` | 最近 2 周 | 适合双周迭代总结 |
| `1m` | 最近 1 个月 | 适合月度汇报 |
| `1q` | 最近 1 个季度 | 适合季度回顾和投资方报告 |

使用 TeamCreate 创建 team（名称格式 `team-report-{YYYYMMDD-HHmmss}`，如 `team-report-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

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


## 流程概览

```
阶段零  数据采集 → data-gatherer 读取所有数据源 → 输出结构化数据包
         ↓
阶段一  并行撰写 → writer-1 独立撰写 + writer-2 独立撰写（面向目标受众）
         ↓
阶段二  审查合并 → reviewer 对比两份草稿 → 确保受众语言匹配 → 合并最佳内容
         ↓
阶段三  输出 → 终端显示或文件保存

briefing 流程：阶段零 → 阶段一（精简，仅 writer-1） → 跳过阶段二 → 阶段三
```

## 角色定义

| 角色 | 职责 |
|------|------|
| data-gatherer | 读取 git log、CHANGELOG、TODOS.md、`~/.gstack/data/{slug}/*.json`（velocity、techdebt、deps-health、compliance）等数据源，执行数据清洗和结构化整理。**只做数据采集和整理，不做分析和撰写。** |
| writer-1 | 基于 data-gatherer 的数据包，按目标受众风格独立撰写报告草稿。**独立撰写阶段不与 writer-2 交流。** |
| writer-2 | 同 writer-1 的职责，独立执行相同撰写。**独立撰写阶段不与 writer-1 交流。** |
| reviewer | 对比两位 writer 的草稿，检查受众语言匹配度、数据准确性、叙事一致性，合并最佳段落生成最终报告。**只做审查和合并，不直接读取原始数据源。** |

### 角色生命周期

| 角色 | 启动阶段 | 活跃阶段 | 关闭条件 |
|------|---------|---------|---------|
| data-gatherer | 阶段零 | 阶段零→一 | 数据采集完成，交付数据包 |
| writer-1 | 阶段一 | 阶段一→二 | 初稿完成，进入交叉审查 |
| writer-2 | 阶段一 | 阶段一→二 | 初稿完成，进入交叉审查 |
| reviewer | 阶段二 | 阶段二→三 | 审查通过或达到最大迭代 |

### 共识度计算

双写手独立撰写后，team lead 按以下维度评估共识度：

共识度 = (一致观点数 + 互补观点数) / (一致观点数 + 互补观点数 + 冲突观点数) × 100%

- ≥ 60%：自动合并，冲突部分由 team lead 裁决
- < 60%：触发熔断，暂停并向用户确认报告方向

### 跨团队衔接建议

报告完成后，根据报告内容自动建议后续行动：
- 报告揭示技术债务 → 建议 `/team-techdebt` 深入分析
- 报告揭示安全隐患 → 建议 `/team-security` 审计
- 报告揭示性能瓶颈 → 建议 `/team-perf` 优化
- 报告用于 board 汇报 → 建议 `/team-sprint` 规划下一迭代

---

## 阶段零：数据采集

### 步骤 1：启动 data-gatherer

Team lead 启动 data-gatherer，指示其采集以下数据源：

**Git 数据**（根据 `--period` 确定时间范围）：
- `git log` — 提交历史（作者、日期、消息、文件变更）
- `git shortlog` — 按作者统计提交数量
- `git diff --stat` — 代码变更量统计（新增/删除行数）
- 标签和版本发布记录

**项目文件**：
- `CHANGELOG.md` / `CHANGELOG` — 变更日志
- `TODOS.md` / `TODO.md` — 待办事项
- `README.md` — 项目描述（用于上下文理解）

**跨技能数据文件**（`~/.gstack/data/{slug}/`）：
- `velocity.json` — 速度趋势数据
- `techdebt.json` — 技术债务数据
- `deps-health.json` — 依赖健康度数据
- `compliance.json` — 合规状态数据

### 步骤 2：数据新鲜度检查

Data-gatherer 对每个 JSON 数据文件检查 `generated_at` 字段：
- 如果 `generated_at` 距今超过 7 天 → 标记为"数据过期"，在数据包中附带警告
- 如果文件不存在 → 标记为"数据不可用"

**优雅降级**：如果所有 JSON 数据文件均不存在，data-gatherer 仅基于 git log 生成数据包，在包中注明"仅基于 git 数据，建议运行相关技能获取完整数据"。

### 步骤 3：输出数据包

Data-gatherer 输出**结构化数据包**，包含：
- **提交摘要**：总提交数、活跃贡献者、每日/每周提交趋势
- **代码变更摘要**：新增行数、删除行数、净变更、变更最多的文件/模块
- **里程碑和发布**：期间内的版本发布、重要标签
- **待办事项摘要**：新增/已完成/剩余待办数量
- **速度趋势**（如可用）：故事点完成趋势、吞吐量
- **技术债务摘要**（如可用）：债务分类、严重程度分布
- **依赖健康度**（如可用）：过期依赖数、漏洞数量
- **合规状态**（如可用）：合规检查通过率、未解决项
- **数据新鲜度报告**：每个数据源的可用性和新鲜度

### 步骤 4：确认数据范围

**标准模式**：向用户展示数据包摘要（可用数据源、时间范围、数据新鲜度），AskUserQuestion 确认
**单轮确认模式**：team lead 自行确认，收尾汇总时说明
**完全自主模式**：自动确认，不询问用户

---

## 阶段一：并行撰写

### 步骤 5：启动 writer-1 和 writer-2

**`briefing` 模式**：仅启动 writer-1（晨报篇幅短，无需双写手），跳过 writer-2。

其他模式下，两者并行启动，全程保持存活直到收尾。

Team lead 将 data-gatherer 的数据包分发给两位 writer，同时传递：
- 目标报告模式（`--mode`）
- 目标受众描述
- 报告周期（`--period`）
- 输出语言（`--lang`）

**重要**：team lead 必须确保两位 writer 不互相看到对方的草稿。

### 步骤 6：Writer 撰写规范

每位 writer 根据报告模式撰写草稿，遵循以下受众语言规范：

**`board` 模式撰写规范**：
- 使用非技术语言，避免技术术语
- 重点：进度百分比、风险红黄绿灯标记、资源请求、时间线影响
- 结构：执行摘要 → 关键指标 → 风险与阻塞 → 资源请求 → 下期展望
- 用具体数字而非模糊描述（如"完成 87%"而非"进展顺利"）

**`team` 模式撰写规范**：
- 允许技术术语，面向工程团队
- 重点：已交付功能清单、阻塞项及负责人、速度趋势图表（文本表示）、团队贡献表彰
- 结构：本期交付 → 进行中 → 阻塞项 → 速度趋势 → 技术债务动态 → 团队表彰
- 包含具体 PR/commit 引用

**`investor` 模式撰写规范**：
- 叙事驱动，强调产品势能
- 重点：用户影响故事、技术壁垒构建、团队成长、市场竞争力
- 结构：产品亮点 → 用户影响 → 技术优势 → 团队动态 → 展望
- 将技术成就转化为商业价值语言

**`briefing` 模式撰写规范**：
- 极简风格，快速扫读
- 重点：隔夜事件/告警、依赖漏洞更新、关键指标变化、今日重点
- 结构：告警 → 依赖更新 → 关键指标 → 今日重点
- 每项不超过一行

### 模板库

每种模式提供预置报告骨架，Writer 可基于模板填充数据，确保格式一致性。模板中 `{变量名}` 为占位符，Writer 需替换为实际数据。

**`board` 模式模板**：
```
# {project_name} — {period} 执行摘要

## 关键指标
- 整体进度：{progress_pct}%（目标：{target_pct}%）
- 本期提交：{total_commits} 次，活跃贡献者 {active_contributors} 人
- 风险等级：{risk_level}（🟢 绿 / 🟡 黄 / 🔴 红）

## 风险与阻塞
{risk_items}

## 资源请求
{resource_requests}

## 下期展望
{next_period_outlook}
```

**`team` 模式模板**：
```
# {project_name} — {period} 团队周报

## 本期交付
{delivered_features}

## 进行中
{in_progress_items}

## 阻塞项
{blockers}

## 速度趋势
- 提交速率：{commits_per_week}/周（{velocity_trend}）
- 变更最多的模块：{top_module}

## 技术债务动态
- 新增债务：{new_debt_count} 项
- 已偿还：{resolved_debt_count} 项
- 当前债务比率：{debt_ratio}%

## 团队表彰
{team_shoutouts}
```

**`investor` 模式模板**：
```
# {project_name} — {period} 产品动量报告

## 产品亮点
{product_highlights}

## 用户影响
{user_impact_stories}

## 技术壁垒
- 核心技术优势：{tech_moat}
- 本期技术投入：{tech_investment}

## 团队动态
- 活跃贡献者：{active_contributors} 人
- 团队产出趋势：{team_output_trend}

## 展望
{forward_looking}
```

**`briefing` 模式模板**：
```
# 晨报 — {date}

⚠️ 告警：{overnight_alerts}
📦 依赖更新：{dep_updates}
📊 关键指标：提交 {total_commits} | 贡献者 {active_contributors} | 债务比率 {debt_ratio}%
🎯 今日重点：{today_focus}
```

### 步骤 7：收集草稿

两位 writer 完成后各自向 team lead 发送草稿。Team lead 确认收到全部草稿后，进入阶段二。

---

## 阶段 2.5：历史趋势对比

当 `--period` 覆盖多周或多月时（`2w`、`1m`、`1q`），team lead 指示 data-gatherer 在步骤 3 的数据包中额外提供**历史趋势对比数据**。

### 对比逻辑

| `--period` 值 | 当前期 | 对比期 | 说明 |
|---------------|--------|--------|------|
| `1w` | 本周 | 上周 | 仅当用户显式请求趋势时启用 |
| `2w` | 最近 2 周 | 前 2 周 | 自动启用 |
| `1m` | 最近 1 个月 | 上个月 | 自动启用 |
| `1q` | 最近 1 个季度 | 上个季度 | 自动启用 |

### 追踪指标

Data-gatherer 对以下关键指标计算"本期 vs 上期"变化：

| 指标 | 数据来源 | 趋势标记 |
|------|---------|---------|
| **提交速率** (commits/week) | `git log` 按周聚合 | ↑ 提升 / ↓ 下降 / → 稳定 |
| **活跃贡献者数** | `git shortlog` 去重作者 | ↑ / ↓ / → |
| **代码净增长** (net lines changed) | `git diff --stat` | ↑ / ↓ / → |
| **技术债务比率** | `techdebt.json` 的 `debt_ratio` 字段 | ↑ 恶化 / ↓ 改善 / → 稳定 |
| **测试覆盖率变化** | `velocity.json` 的 `test_coverage` 字段 | ↑ 改善 / ↓ 退步 / → 稳定 |
| **依赖漏洞数** | `deps-health.json` 的 `vulnerabilities` 字段 | ↑ 恶化 / ↓ 改善 / → 稳定 |

趋势判定规则：变化幅度 ≤ 5% 标记为 → 稳定；> 5% 按方向标记 ↑ 或 ↓。

### Writer 使用趋势数据

Writer 在撰写报告时，应在相关章节插入趋势对比表：

```
### 本期 vs 上期

| 指标           | 上期     | 本期     | 趋势 |
|---------------|---------|---------|------|
| 提交速率       | {prev_commits_per_week} | {curr_commits_per_week} | {trend_indicator} |
| 活跃贡献者     | {prev_contributors}     | {curr_contributors}     | {trend_indicator} |
| 技术债务比率   | {prev_debt_ratio}       | {curr_debt_ratio}       | {trend_indicator} |
| 测试覆盖率     | {prev_test_coverage}    | {curr_test_coverage}    | {trend_indicator} |
```

对于 `board` 和 `investor` 模式，趋势数据应转化为自然语言叙述（如"提交活跃度环比提升 23%，团队产出持续增长"），而非直接展示表格。

---

## 阶段二：审查合并

**`briefing` 模式跳过此阶段，直接进入阶段三。**

### 步骤 8：启动 reviewer

Team lead 启动 reviewer，将以下内容传递：
- Data-gatherer 的数据包（作为事实基准）
- Writer-1 的草稿（标记为"草稿 A"）
- Writer-2 的草稿（标记为"草稿 B"）
- 目标报告模式和受众描述

**重要**：传递时不透露 writer 编号，仅用"草稿 A"和"草稿 B"标记，避免暗示优先级。

### 步骤 9：Reviewer 审查对比

Reviewer 从以下维度对比两份草稿：

| 审查维度 | 检查内容 |
|---------|---------|
| **数据准确性** | 草稿中引用的数据是否与数据包一致 |
| **受众匹配度** | 语言风格是否适合目标受众（如 board 模式不应有技术术语） |
| **叙事完整性** | 是否覆盖了数据包中的所有关键信息 |
| **结构合理性** | 报告结构是否符合该模式的规范 |
| **结论一致性** | 两份草稿对项目状态的判断是否一致 |

Reviewer 输出：
1. **各维度评分**：每个维度对两份草稿分别评分（优/良/可）
2. **最佳段落标记**：每个报告章节标记哪份草稿更优及原因
3. **结论矛盾标记**（如有）：两份草稿对同一事项判断矛盾时标注
4. **合并策略**：说明最终报告各章节取自哪份草稿

### 步骤 10：检查熔断条件

如果两份草稿存在结论矛盾（如一份说项目进度正常，另一份说严重延期）：
- **必须暂停**，team lead 向用户报告矛盾情况
- 可能原因：数据解读歧义、关键数据缺失导致推断不同
- 建议：用户裁决正确结论，或补充缺失数据

无结论矛盾：继续合并。

### 步骤 11：合并生成最终报告

Reviewer 按合并策略，从两份草稿中取最佳段落，合并生成最终报告。合并时确保：
- 语言风格统一（不出现前后风格断裂）
- 数据引用无冲突
- 逻辑叙事连贯

### 步骤 12：用户确认

Team lead 向用户展示最终报告摘要：
- 报告模式和目标受众
- 报告周期和数据来源
- 数据新鲜度警告（如有）
- 报告主要结论

AskUserQuestion 确认：
- 接受报告
- 需要调整语气/风格
- 需要补充某些数据

**单轮确认模式**：必须经用户确认。
**完全自主模式**：自动决策，不询问用户。

---

## 阶段三：输出

### 步骤 13：输出报告

根据 `--output` 参数：
- `stdout`（默认）：直接在终端输出最终报告全文
- `file`：保存到项目的 `docs/reports/` 目录
  - 文件名格式：`{mode}-report-YYYY-MM-DD.md`（如 `team-report-2026-03-21.md`）
  - 如果目录不存在，创建之

### 步骤 13.5：自动分发建议

根据 `--format` 参数，在输出报告后附加分发就绪内容：

**`--format=email` 时**：
- 生成可直接复制粘贴的邮件内容块，包含：
  - **Subject 行**：`[{mode}报告] {project_name} — {period} ({date})`
  - **Body**：报告正文（email 格式）
  - **收件人建议**：根据 `--mode` 推荐收件人角色（如 board → C-level + VP Engineering，team → 全体工程师）
- 用 `---BEGIN EMAIL---` 和 `---END EMAIL---` 标记，方便用户整段复制

**`--format=slack` 时**：
- 生成 Slack 消息块，可直接粘贴到 Slack 频道：
  - 使用 Slack mrkdwn 语法（`*bold*`、`_italic_`、`>` 引用）
  - 包含 emoji 状态标记
  - 建议发送频道：根据 `--mode` 推荐（如 board → `#leadership`，team → `#engineering`，briefing → `#standup`）
- 如果报告保存为文件（`--output=file`），在消息末尾附文件路径供引用

**`--format=ppt-outline` 时**：
- 生成逐页 PPT 大纲，每页包含：
  - `## Slide {N}: {页面标题}`
  - 3 个要点（每点 ≤ 15 字）
  - `> Speaker Notes:` 展开说明（演讲者备注，2-3 句话）
- 附加演示建议：
  - 预计演示时长（根据页数估算，每页约 2 分钟）
  - 建议重点停留的页面
  - Q&A 环节预测问题（基于报告中的风险项和数据异常点）

**`--format=markdown` 时**（默认）：
- 无额外分发建议，直接输出完整 Markdown 报告

### 步骤 14：最终总结

Team lead 向用户输出：
- 报告模式和目标受众
- 数据来源和覆盖情况（哪些 JSON 数据可用、哪些缺失）
- 数据新鲜度警告（如有过期数据）
- 报告周期和时间范围
- 报告核心结论摘要（2-3 句话）
- 输出位置（终端或文件路径）
- **（单轮确认模式/完全自主模式）自动决策汇总**：列出所有自动决策的节点、决策内容和理由

### 步骤 15：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 核心原则

- **多源采集**：data-gatherer 从 git、项目文件、跨技能 JSON 数据多渠道采集，确保数据全面性
- **独立撰写**：两位 writer 必须完全独立工作，不互相看到对方草稿，确保视角多样性
- **职责分离**：data-gatherer 只做数据采集，writer 只做撰写，reviewer 只做审查合并
- **受众适配**：严格按目标受众调整语言风格，board 无技术术语，team 允许技术细节
- **优雅降级**：数据不完整时仍可生成报告，明确标注缺失和过期数据
- **并行高效**：两位 writer 并行撰写，最大化效率
- **数据新鲜度**：自动检查跨技能数据文件时效性，超期警告用户

---

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

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| 项目无 git 历史 | Data-gatherer 基于项目文件和 JSON 数据生成数据包，报告中注明无 git 数据 |
| 所有数据源均不可用 | 触发熔断，暂停问用户确认数据来源 |
| JSON 数据文件格式异常 | Data-gatherer 跳过异常文件，标注"数据解析失败"，不阻塞流程 |
| JSON 数据文件过期（>7 天） | 报告中标注过期警告，建议用户重新运行来源技能 |
| 两位 writer 草稿结论矛盾 | 触发熔断，暂停问用户裁决 |
| `--period` 范围内无提交记录 | Data-gatherer 标注"该周期无提交活动"，writer 据此撰写（如标注为静默期） |
| git log 数据量过大（>1000 条） | Data-gatherer 采样统计，不逐条分析，在数据包中注明采样方式 |
| `~/.gstack/data/{slug}/` 目录不存在 | Data-gatherer 仅基于 git 和项目文件生成数据包，报告注明建议运行相关技能 |
| Writer 无响应/崩溃 | Team lead 重新启动同名 writer（传入完整上下文），从当前阶段恢复 |
| Reviewer 无响应/崩溃 | Team lead 重新启动 reviewer，传入两份草稿和数据包，从审查步骤恢复 |
| 输出文件写入失败 | 回退到 stdout 输出，提示用户手动保存 |

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

