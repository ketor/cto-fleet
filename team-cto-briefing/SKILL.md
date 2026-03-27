---
name: team-cto-briefing
description: CTO 晨会编排器——按顺序调用多个 CTO skill（deps/techdebt/sprint/capacity/report），合并输出为一份结构化综合简报。支持自定义模块组合和输出格式。使用方式：/team-cto-briefing [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--modules=deps,techdebt,sprint,capacity,compliance] [--skip=模块名] [--period=1w|2w|1m] [--lang=zh|en]
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--modules=模块列表] [--skip=跳过模块] [--period=1w|2w|1m] [--lang=zh|en]
---

## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE <old> <new>`: read `~/.claude/skills/cto-fleet/cto-fleet-upgrade/SKILL.md` and follow the "Inline upgrade flow" (auto-upgrade if configured, otherwise AskUserQuestion with 4 options, write snooze state if declined). If `JUST_UPGRADED <from> <to>`: tell user "Running cto-fleet v{to} (just updated!)" and continue.

---

**参数解析**：从 `$ARGUMENTS` 中检测以下标志：
- `--auto`：完全自主模式（不询问用户任何问题，全程自动决策）
- `--once`：单轮确认模式（将所有需要确认的问题合并为一轮提问，确认后全程自动执行）
- `--modules=deps,techdebt,sprint,capacity,compliance`：指定要运行的模块（默认全部）
- `--skip=模块名`：跳过指定模块（如 `--skip=compliance,capacity`）
- `--period=1w|2w|1m`：分析周期（默认 `1w`，传递给子 skill）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 模块选择确认 + 各模块关键发现确认 + 最终简报确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅模块选择确认 | 自动汇总所有模块，收尾展示 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动运行，直接输出最终简报 |

单轮确认模式下条件节点自动决策规则：
- **某模块数据缺失** → 跳过该模块，简报中标注"数据不可用"
- **某模块执行失败** → 记录错误，继续执行其他模块，简报中标注"执行失败"
- **数据陈旧（>7天）** → 自动重新运行该模块的源 skill 刷新数据
- **关键风险发现（Critical 级别）** → **不可跳过，必须暂停通知用户**（熔断机制）

完全自主模式下：所有节点均自动决策。熔断机制仍然生效（发现 Critical 级别风险时仍必须暂停通知用户）。

---

## 模块清单

| 模块 ID | 对应 Skill | 数据文件 | 简报章节 | 默认启用 |
|---------|-----------|---------|---------|---------|
| `deps` | `/team-deps` | `deps-health.json` | 依赖健康 | ✅ |
| `techdebt` | `/team-techdebt` | `techdebt.json` | 技术债务 | ✅ |
| `sprint` | `/team-sprint` | `velocity.json` | Sprint 进度 | ✅ |
| `capacity` | `/team-capacity` | `capacity.json` | 团队健康 | ✅ |
| `compliance` | `/team-compliance` | `compliance.json` | 合规状态 | ❌（需显式启用） |
| `report` | `/team-report --mode=briefing` | — | 综合摘要 | ✅（始终最后运行） |

> **注意**：数据文件列（如 `deps-health.json`）描述的是规划中的跨 skill 数据接口。当前版本各子 skill 直接输出到上下文，不经 JSON 文件中转。未来版本将实现结构化 JSON 中间文件以支持增量刷新和缓存。

**模块依赖顺序**：

```
deps ──────┐
techdebt ──┤
sprint ────┤──► report (最后聚合)
capacity ──┤
compliance ┘
```

各模块之间无强依赖，可并行运行。`report` 模块始终最后运行，读取前序模块的 JSON 输出。

---

## 流程概览

```
阶段零  环境检测 → 检查 git 仓库 + ~/.gstack/data/{slug}/ + 已有数据文件时效性
         ↓
阶段一  模块选择 → 确定要运行的模块列表 + 检测数据新鲜度 → 确认
         ↓
阶段二  并行采集 → 对需要刷新的模块，并行调用对应 skill 刷新数据
         ↓
阶段三  数据聚合 → 读取所有模块的 JSON 输出 + 交叉分析 + 风险提取
         ↓
阶段四  简报生成 → 调用 /team-report --mode=briefing 生成最终简报
         ↓
阶段五  收尾 → 输出简报 + 记录执行日志
```

---

## 角色定义

本 skill 不使用 TeamCreate 创建多 agent 团队。CTO 简报编排器以**单 agent 编排模式**运行，直接调用子 skill 并聚合结果。

原因：每个子 skill 内部已有完整的多 agent 团队。编排器再创建团队会导致 agent 嵌套过深、上下文膨胀。编排器的职责是**调度和聚合**，不是分析。

---

## 阶段零：环境检测

### 步骤 1：检查基础环境

```bash
# 检查 git 仓库
git rev-parse --show-toplevel 2>/dev/null || echo "NOT_A_GIT_REPO"

# 检查数据目录
SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
DATA_DIR="$HOME/.gstack/data/$SLUG"
mkdir -p "$DATA_DIR"
echo "DATA_DIR=$DATA_DIR"

# 检查已有数据文件及时效性
for f in deps-health.json techdebt.json velocity.json capacity.json compliance.json; do
  if [ -f "$DATA_DIR/$f" ]; then
    AGE_DAYS=$(( ($(date +%s) - $(date -r "$DATA_DIR/$f" +%s)) / 86400 ))
    echo "$f: exists, ${AGE_DAYS}d old"
  else
    echo "$f: missing"
  fi
done
```

如果不在 git 仓库中：报告"需要在 git 仓库中运行"，退出。

### 步骤 2：解析数据新鲜度

根据步骤 1 的输出，将每个模块分类为：

| 状态 | 含义 | 处理方式 |
|------|------|---------|
| **fresh** | 数据文件存在且 < 7 天 | 直接使用，不重新运行 |
| **stale** | 数据文件存在但 ≥ 7 天 | 需要重新运行子 skill 刷新 |
| **missing** | 数据文件不存在 | 需要首次运行子 skill |

---

## 阶段一：模块选择

### 步骤 3：确定模块列表

根据参数和数据状态，确定最终模块列表：

1. 如果用户指定了 `--modules`，使用指定列表
2. 如果用户指定了 `--skip`，从默认列表中移除
3. 否则使用默认列表（deps, techdebt, sprint, capacity）
4. `compliance` 仅在显式包含时启用（因为运行时间较长）
5. `report` 始终包含（最后运行）

### 步骤 4：展示执行计划

向用户展示将要执行的模块列表和每个模块的数据状态：

```
╔══════════════════════════════════════════════════╗
║           CTO BRIEFING — 执行计划                 ║
╠══════════════════════════════════════════════════╣
║                                                  ║
║  模块          状态        操作                   ║
║  ─────────────────────────────────────────────── ║
║  deps          fresh (2d)  ✅ 使用已有数据         ║
║  techdebt      stale (15d) 🔄 重新运行             ║
║  sprint        missing     🆕 首次运行             ║
║  capacity      fresh (1d)  ✅ 使用已有数据         ║
║  report        —           📝 聚合生成             ║
║                                                  ║
║  预计耗时：~3 分钟（2 个模块需要刷新）             ║
╚══════════════════════════════════════════════════╝
```

**标准模式**：AskUserQuestion 确认执行计划
**单轮确认模式**：AskUserQuestion 确认（这是唯一一次确认）
**完全自主模式**：自动执行，不询问

---

## 阶段二：并行数据采集

### 步骤 5：并行调用子 skill

对所有状态为 `stale` 或 `missing` 的模块，使用 Agent 工具并行调用对应的子 skill。

**关键规则**：
- 每个子 skill 以 `--auto --lang={lang}` 模式运行（完全自主，不中断用户）
- 使用 `run_in_background: true` 并行启动所有需要刷新的模块
- 等待所有后台 agent 完成

调用映射：

| 模块 | 调用命令 |
|------|---------|
| deps | `Skill: team-deps, args: "--auto --lang={lang}"` |
| techdebt | `Skill: team-techdebt, args: "--auto --lang={lang}"` |
| sprint | `Skill: team-sprint, args: "--auto --period={period} --lang={lang}"` |
| capacity | `Skill: team-capacity, args: "--auto --period={period} --lang={lang}"` |
| compliance | `Skill: team-compliance, args: "--auto --lang={lang}"` |

**注意**：不能直接使用 Skill 工具并行调用（Skill 工具是同步的）。改用 Agent 工具启动子 agent，每个 agent 内部调用对应的 Skill。

```
为每个需要刷新的模块启动一个 Agent：
- description: "Run team-{module} for briefing"
- prompt: "调用 /team-{module} skill，使用 --auto --lang={lang} 参数。完成后确认数据文件已生成。"
- run_in_background: true
```

### 步骤 6：收集执行结果

等待所有后台 agent 完成。记录每个模块的执行结果：

| 状态 | 含义 |
|------|------|
| ✅ success | 数据文件已更新 |
| ❌ error | 子 skill 执行失败，记录错误信息 |
| ⏭️ skipped | 用户选择跳过或模块不适用 |

如果有模块执行失败：不阻塞整体流程，在最终简报中标注"该模块数据不可用"。

---

## 阶段三：数据聚合与交叉分析

### 步骤 7：读取所有 JSON 数据

```bash
DATA_DIR="$HOME/.gstack/data/$SLUG"
for f in deps-health.json techdebt.json velocity.json capacity.json compliance.json; do
  [ -f "$DATA_DIR/$f" ] && echo "=== $f ===" && cat "$DATA_DIR/$f"
done
```

读取每个 JSON 文件，提取关键指标。

### 步骤 8：交叉分析

从多个数据源中提取**交叉洞察**——这是编排器的核心价值，单独运行子 skill 无法获得：

1. **依赖风险 × 技术债务**：高 CVE 漏洞的依赖是否位于高债务模块中？如果是 → Critical 风险（漏洞修复因债务而更困难）
2. **巴士因子 × 技术债务**：高债务模块的巴士因子是否为 1？如果是 → Critical 风险（唯一了解该模块的人 + 模块本身质量差）
3. **Sprint 速率 × 技术债务**：速率是否在下降？同时技术债务是否在上升？如果是 → 技术债务正在拖慢团队
4. **团队负载 × Sprint 范围**：是否存在团队成员超载（Gini > 0.6）同时 Sprint 范围偏大？如果是 → 过载风险
5. **合规差距 × 依赖漏洞**：合规控制缺失是否与已知漏洞重叠？如果是 → 审计风险

### 步骤 9：风险提取与分级

从所有模块数据和交叉分析中提取风险项，按严重程度分级：

| 级别 | 定义 | 处理 |
|------|------|------|
| 🔴 Critical | 需要立即关注（生产安全、数据泄露风险、审计阻断） | **触发熔断**：即使 `--auto` 模式也暂停通知用户 |
| 🟠 High | 本周需要处理（高 CVE、巴士因子=1 的核心模块） | 在简报中突出显示 |
| 🟡 Medium | 本月关注（速率下降、债务增长趋势） | 在简报中列出 |
| 🟢 Low | 知晓即可（信息性指标） | 在简报中简要提及 |

**熔断规则**：如果发现任何 Critical 级别风险，无论哪种模式都必须暂停，向用户展示风险详情并等待确认后继续。

---

## 阶段四：简报生成

### 步骤 10：生成综合简报

基于聚合数据和交叉分析，生成最终简报。不再调用 `/team-report`（避免额外 agent 开销），直接在编排器中生成。

简报格式：

```markdown
# CTO 简报
> 生成时间：YYYY-MM-DD HH:MM | 分析周期：{period} | 模块：{modules}

---

## 🚨 需要立即关注

{Critical 和 High 级别的风险项，每项包含：}
- **问题描述**（一句话）
- **影响范围**（哪些模块/服务受影响）
- **建议操作**（具体下一步）
- **来源模块**（哪个分析发现的）

---

## 📊 关键指标

| 指标 | 当前值 | 趋势 | 状态 |
|------|--------|------|------|
| 依赖漏洞（Critical/High） | X/Y | ↑↓→ | 🔴🟡🟢 |
| 技术债务 Top 3 模块 | {模块名} | ↑↓→ | 🔴🟡🟢 |
| Sprint 速率（PR/周） | X | ↑↓→ | 🔴🟡🟢 |
| 团队巴士因子（最低） | X ({模块}) | — | 🔴🟡🟢 |
| 合规控制通过率 | X% | — | 🔴🟡🟢 |

---

## 🔍 交叉洞察

{从步骤 8 交叉分析中提取的洞察，每条包含：}
1. **发现**：{描述}
2. **为什么重要**：{一句话解释}
3. **建议**：{具体操作}

---

## 📦 依赖健康
{来自 deps-health.json 的摘要}
- Critical CVE: X 个
- 过期依赖（>6个月）: X 个
- 建议升级: {列表}

## 🏗️ 技术债务
{来自 techdebt.json 的摘要}
- 债务总项: X 个 (Critical: X, High: X)
- Top 3 热点: {模块列表 with scores}
- 趋势: 较上次 ↑/↓ X%

## 🏃 Sprint 进度
{来自 velocity.json 的摘要}
- 本周速率: X PR merged
- 周期时间: X 天 (趋势: ↑/↓)
- 聚焦分数: X (趋势: ↑/↓)

## 👥 团队健康
{来自 capacity.json 的摘要}
- 巴士因子最低模块: {模块} (因子=X)
- 知识孤岛: X 个模块
- 负载均衡 Gini: X

## ✅ 合规状态（如启用）
{来自 compliance.json 的摘要}
- 控制通过率: X/Y (XX%)
- 关键差距: {列表}

---

## 📋 建议操作清单

按优先级排列的操作建议（聚合自所有模块）：

1. 🔴 {Critical 操作} — 来源: {模块}
2. 🟠 {High 操作} — 来源: {模块}
3. 🟡 {Medium 操作} — 来源: {模块}

---

> 数据来源: {列出每个模块的数据文件及其时间戳}
> 不可用模块: {列出执行失败或跳过的模块}
```

### 步骤 11：展示简报

向用户展示最终简报。

**标准模式**：展示完整简报，AskUserQuestion 确认是否满意
**单轮确认模式**：直接展示完整简报
**完全自主模式**：直接展示完整简报

---

## 阶段五：收尾

### 步骤 12：记录执行日志

```bash
mkdir -p ~/.gstack/analytics
echo '{"skill":"team-cto-briefing","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","modules":"MODULES","fresh":FRESH_COUNT,"refreshed":REFRESH_COUNT,"failed":FAIL_COUNT,"critical_risks":CRITICAL_COUNT,"high_risks":HIGH_COUNT}' >> ~/.gstack/analytics/skill-usage.jsonl 2>/dev/null || true
```

替换占位符为实际值。

### 步骤 13：建议后续操作

根据简报中发现的问题，建议后续操作：

- 如果有 Critical CVE → 建议运行 `/team-deps --fix` 自动修复
- 如果有高债务模块 → 建议运行 `/team-refactor` 针对该模块
- 如果有巴士因子=1 的模块 → 建议安排 pair programming 或知识分享
- 如果合规差距 > 3 项 → 建议运行 `/team-compliance --evidence` 生成证据
- 如果速率连续下降 → 建议运行 `/team-sprint` 重新评估 Sprint 范围

不使用 AskUserQuestion——只是在简报末尾列出建议。用户可以自行决定是否执行。

---

## 快捷别名

以下自然语言触发短语应路由到本 skill：

- "晨会简报" / "morning briefing"
- "CTO briefing" / "CTO 简报"
- "技术总览" / "tech overview"
- "综合报告" / "comprehensive report"
- "今天有什么需要关注的" / "what needs my attention"
- "项目健康检查" / "project health check"

---

## 核心原则

- **编排不分析**：编排器只负责调度子 skill 和聚合结果，不直接分析代码或数据
- **交叉洞察是核心价值**：单独运行子 skill 无法获得的跨模块洞察是本 skill 的独特价值
- **数据新鲜度优先**：优先使用新鲜数据，自动刷新陈旧数据
- **优雅降级**：某个模块失败不阻塞整体简报，标注不可用即可
- **Critical 熔断**：无论什么模式，发现严重风险都必须通知用户
- **不创建团队**：使用单 agent 编排 + 子 skill 内部团队，避免 agent 嵌套
- **快速产出**：大多数情况下 fresh 数据可直接使用，简报应在 1-2 分钟内完成

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| 不在 git 仓库中 | 报告错误，退出 |
| 数据目录不存在 | 自动创建 `~/.gstack/data/{slug}/` |
| 子 skill 未安装 | 跳过该模块，简报中标注"skill 不可用" |
| 子 skill 执行超时（>5分钟） | 终止该 agent，跳过该模块 |
| 子 skill 执行失败 | 记录错误，跳过该模块，简报中标注失败原因 |
| JSON 文件格式错误 | 跳过该模块，建议重新运行对应 skill |
| 所有模块都失败 | 报告"无法生成简报"，列出所有失败原因 |
| Critical 风险熔断 | 暂停执行，展示风险详情，等待用户确认 |
| 用户中断执行 | 输出已收集的部分数据作为不完整简报 |

---

## 需求

$ARGUMENTS
