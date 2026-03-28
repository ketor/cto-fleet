---
name: team-techdebt
description: 启动一个技术债务分析团队（scanner/analyzer×2/reporter），通过自动化指标采集+双路独立分析（复杂度×变更频率+测试覆盖率）+合并评分，输出可操作的技术债务清单和优先级排序。使用方式：/team-techdebt [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--top=N (显示前N个债务项，默认20)] [--module=路径 (聚焦分析特定模块)] [--lang=zh|en] 分析目标描述
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--top=N (显示前N个债务项，默认20)] [--module=路径 (聚焦分析特定模块)] [--lang=zh|en] 分析目标描述
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
- `--top=N`：显示前 N 个债务项（默认 20）
- `--module=路径`：聚焦分析特定模块（默认分析整个项目）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后将标志从分析目标描述中移除。

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 每阶段分析结果确认 + 最终报告确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅首轮指标采集确认 + 收尾汇总 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下自动决策规则：
- **债务优先级不确定** → 按评分公式排序，优先处理分数最高的债务项
- **分析结论有多种解读** → 采纳对应分析维度 analyzer 的建议
- **工具运行失败或数据缺失** → 标注"该指标不可用"，使用替代数据源，不阻塞流程
- **双 analyzer 结论冲突** → reporter 优先采纳共识部分，冲突部分标注"待人工确认"
- **扫描范围过大导致超时** → **不可跳过，必须暂停问用户**（熔断机制）

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效（扫描超时、关键工具全部不可用时仍必须暂停问用户）。

使用 TeamCreate 创建 team（名称格式 `team-techdebt-{YYYYMMDD-HHmmss}`，如 `team-techdebt-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

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
阶段零  指标采集 → scanner 运行静态分析工具，收集原始数据（复杂度、变更频率、覆盖率、TODO/FIXME/HACK）
         ↓
阶段一  双路并行分析 → analyzer-1 复杂度×变更频率分析 + analyzer-2 覆盖率×风险分析（独立并行）
         → 合并分析 + 共识确认 → 债务优先级排序
         ↓
阶段二  评分与排名 → reporter 合并双路分析，应用评分公式，生成排名清单
         ↓
阶段三  生成输出 → TECHDEBT.md + techdebt.json + 趋势对比（如有历史数据）
```

## 角色定义

| 角色 | 职责 |
|------|------|
| scanner | 运行静态分析工具（通过 lizard/radon/gocyclo 等计算复杂度指标，通过 git log 计算变更频率，grep TODO/FIXME/HACK，采集测试覆盖率数据）。输出原始指标数据。**仅在阶段零工作，完成后关闭。** |
| analyzer-1 | **复杂度×变更频率分析**：识别同时具备高复杂度和高变更频率的文件（"经常改动+难以改动"象限），定位最危险的技术债务热点。输出结构化分析报告。**不编写或修改代码。独立分析，不与 analyzer-2 交流。** |
| analyzer-2 | **覆盖率×风险分析**：识别测试覆盖率低且处于关键路径上的模块，评估缺乏测试保护的高风险区域。输出结构化分析报告。**不编写或修改代码。独立分析，不与 analyzer-1 交流。** |
| reporter | 合并双路分析结果，应用评分公式计算债务分数，生成排名清单，输出 TECHDEBT.md 和 techdebt.json。如果存在历史 techdebt.json，与之对比生成趋势报告（改善/恶化）。**输出最终技术债务报告。** |

### 角色生命周期

| 角色 | 启动阶段 | 关闭时机 | 说明 |
|------|---------|---------|------|
| scanner | 阶段零（步骤 2） | 阶段零完成后（步骤 2 指标采集结束） | 原始数据交付后即释放 |
| analyzer-1 | 阶段零（步骤 2，与 scanner 并行启动） | 阶段二完成后（步骤 7 评分排名结束） | 需保留用于共识确认和评分校准 |
| analyzer-2 | 阶段零（步骤 2，与 scanner 并行启动） | 阶段二完成后（步骤 7 评分排名结束） | 需保留用于共识确认和评分校准 |
| reporter | 阶段二（步骤 7） | 阶段三完成后（步骤 9 输出生成结束） | 生成最终报告后释放 |

---

## 评分体系

双 analyzer 按各自负责的维度独立评估，reporter 按评分公式合并为总体债务分数。满分 100 分。

### 评分公式

```
debt_score = (complexity_percentile × 0.3) + (churn_percentile × 0.3) + ((1 - coverage) × 0.2) + (incident_proximity × 0.2)

其中：
- complexity_percentile：圈复杂度在所有文件中的百分位排名（0~1）
- churn_percentile：变更频率在所有文件中的百分位排名（0~1）
- coverage：测试覆盖率（0~1），无覆盖数据时默认为 0
- incident_proximity：近期缺陷关联度（1 = 文件近期参与了 bug 修复，0 = 未参与）
```

最终分数 = debt_score × 100，范围 0~100 分。分数越高，技术债务越严重。

### 维度分配

| 维度 | 权重 | 负责人 | 分析内容 |
|------|------|--------|---------|
| 圈复杂度 | 30% | analyzer-1 | 函数/方法级圈复杂度、嵌套深度、认知复杂度 |
| 变更频率 | 30% | analyzer-1 | git log 统计的提交次数/月、变更行数/月、作者数量 |
| 测试覆盖率 | 20% | analyzer-2 | 行覆盖率、分支覆盖率、关键路径覆盖情况 |
| 近期缺陷关联 | 20% | analyzer-2 | 近期 bug fix 提交涉及的文件、issue 关联、回归历史 |

**analyzer-1 总权重：60%**（圈复杂度 30% + 变更频率 30%）
**analyzer-2 总权重：40%**（测试覆盖率 20% + 近期缺陷关联 20%）

### 严重程度分级

| 级别 | 分数范围 | 含义 | 建议动作 |
|------|---------|------|---------|
| **Critical** | 80~100 | 高复杂度+高变更频率+低覆盖率+近期有 bug | 必须立即处理 |
| **High** | 60~79 | 多个维度表现较差 | 强烈建议近期处理 |
| **Medium** | 40~59 | 部分维度存在问题 | 纳入迭代计划 |
| **Low** | 0~39 | 整体状况尚可 | 持续关注 |

### 共识合并机制

**共识度计算公式**：
```
对比每个债务发现，统计两位 analyzer 的重叠情况：

共识债务数 = 两者都识别出的债务数量（指向相同文件/模块且描述相同类型问题）
总债务数 = 去重后的债务总数（合并两方发现后去重）

共识度 = 共识债务数 / 总债务数 × 100%
分歧度 = 100% - 共识度

分歧度 > 50%（超过一半债务仅单方识别）→ team lead 将冲突部分升级，
reporter 优先处理共识部分，冲突部分标注"待人工确认"。
```

独立分析后，team lead 将合并的完整报告（含双方分析和评分）发给两位 analyzer：
- 各自可调整**自己负责维度**的评分（看到对方的分析后校准）
- 不得修改对方维度的评分
- 两者共同识别的债务标记为"共识债务"，优先处理
- 仅单方识别的债务标记为"待验证债务"
- **盲区检查**：team lead 检查是否存在两方都未覆盖的债务类型，如有则在报告中标注"未覆盖风险"

---

## 阶段零：指标采集

### 步骤 1：解析分析目标

Team lead 解析用户提供的分析目标描述：

1. 明确分析范围（整个项目 / 特定模块，根据 `--module` 参数）
2. 确定展示数量（根据 `--top` 参数，默认 20）
3. 识别特殊关注点（如有），未提供则默认全面分析

### 步骤 2：启动 scanner 和双 analyzer

三者并行启动。

**Scanner 指标采集**：
1. 阅读项目结构，识别技术栈、语言、框架和包管理器
2. **按技术栈选择并运行静态分析工具**。Scanner 必须先识别项目语言和框架，然后按以下决策树选择工具：

**工具选择决策树**（按项目语言/框架匹配）：

| 语言/框架 | 复杂度分析 | 变更频率 | TODO/FIXME/HACK | 覆盖率采集 | 检测方法 |
|-----------|-----------|---------|-----------------|-----------|---------|
| **Go** | `gocyclo ./...` 或 `gocognit ./...` | `git log --format=format: --name-only` | `grep -rn "TODO\|FIXME\|HACK"` | `go test -coverprofile=coverage.out ./...` + `go tool cover -func=coverage.out` | 检测 `go.mod` 文件 |
| **Python** | `radon cc -s -a .` + `radon mi .` | `git log --format=format: --name-only` | `grep -rn "TODO\|FIXME\|HACK"` | `pytest --cov --cov-report=json` 或 `coverage json` | 检测 `pyproject.toml`/`requirements.txt`/`setup.py` |
| **Rust** | `cargo clippy -- -W clippy::cognitive_complexity` 或使用 `scc` | `git log --format=format: --name-only` | `grep -rn "TODO\|FIXME\|HACK\|todo!\|unimplemented!"` | `cargo tarpaulin --out Json` 或 `cargo llvm-cov --json` | 检测 `Cargo.toml` |
| **Java/Kotlin** | `pmd check -R category/java/design.xml` 或 `lizard` | `git log --format=format: --name-only` | `grep -rn "TODO\|FIXME\|HACK"` | 解析 JaCoCo 报告 `target/site/jacoco/jacoco.xml` | 检测 `pom.xml`/`build.gradle` |
| **Node.js/TypeScript** | `lizard` 或 `cr` (complexity-report) 或 `eslint --rule complexity` | `git log --format=format: --name-only` | `grep -rn "TODO\|FIXME\|HACK"` | `nyc report --reporter=json` 或 `jest --coverage --coverageReporters=json` | 检测 `package.json` |
| **C/C++** | `lizard` 或 `cppcheck --enable=all` | `git log --format=format: --name-only` | `grep -rn "TODO\|FIXME\|HACK"` | `gcov` + `lcov --capture -o coverage.info` | 检测 `CMakeLists.txt`/`Makefile` |

**工具选择优先级**：① 项目已有的分析配置/CI 报告 > ② 语言原生工具 > ③ 跨语言通用工具（lizard/scc）> ④ 手动代码分析

3. **复杂度指标采集**：
   - 运行复杂度工具，收集每个文件/函数的圈复杂度
   - 计算项目整体复杂度统计（平均值、中位数、P90、P95、最大值）

4. **变更频率采集**（git log 分析）：
   - `git log --since="6 months ago" --format=format: --name-only | sort | uniq -c | sort -rn`：统计近 6 个月每个文件的提交次数
   - `git log --since="6 months ago" --numstat`：统计每个文件的变更行数
   - `git log --since="3 months ago" --diff-filter=M --grep="fix\|bug\|hotfix" --format=format: --name-only`：识别近期 bug fix 涉及的文件

5. **TODO/FIXME/HACK 扫描**：
   - `grep -rn "TODO\|FIXME\|HACK\|XXX\|WORKAROUND" --include="*.{语言扩展名}"`：扫描代码标记
   - 按文件聚合统计数量和类型

6. **覆盖率采集**：
   - 优先解析项目 CI 中已有的覆盖率报告
   - 如无现有报告，运行覆盖率工具生成
   - 如无法生成覆盖率，标注"覆盖率数据不可用"，该维度默认按 coverage=0 计算

7. 输出**原始指标报告**发送给 team lead
8. Scanner 完成后关闭（不参与后续阶段）

**如果某工具未安装或无法运行**：scanner 标注"该指标不可用"，尝试替代工具（如 lizard 作为通用复杂度工具），不阻塞流程。

**如果指定了 `--module` 参数**：scanner 仅扫描指定模块路径，git log 分析也限定在该路径范围内。

**双 analyzer 同时阅读项目**：
- 阅读项目结构，理解技术栈、模块划分和依赖关系
- 了解已有测试基础设施（测试框架、CI 配置、覆盖率工具）
- 各自输出项目概况给 team lead

收集原始数据的输出要求：

| 分析类别 | 必须输出的指标 |
|---------|-------------|
| 复杂度指标 | 每个文件/函数的圈复杂度 + 项目统计（均值/中位数/P90/P95/最大值） |
| 变更频率 | 每个文件近 6 月的提交次数 + 变更行数 + 作者数量 |
| TODO/FIXME/HACK | 每个文件的标记数量 + 类型分布 + 标记内容摘要 |
| 测试覆盖率 | 每个文件/模块的行覆盖率 + 分支覆盖率（如可用） |
| Bug Fix 关联 | 近 3 月参与 bug fix 的文件列表 + fix 次数 |
| 耦合度 | 经常同时变更的文件对（co-change 分析） |

### 步骤 3：分发指标数据

Team lead 收到 scanner 报告后，将原始指标数据分发给两位 analyzer，作为后续分析的依据。

Analyzer 在分析时必须以 scanner 的量化数据为依据——例如 scanner 显示某文件复杂度 P95 以上且月提交 20 次，analyzer-1 应重点分析该文件的债务风险。

---

## 阶段一：双路并行分析

### 步骤 4：独立并行分析

两位 analyzer 各自分析负责的维度，**互不交流**。

**Analyzer-1（复杂度×变更频率）**：
- 将所有文件按复杂度和变更频率绘制四象限：
  - **高复杂度+高变更频率**（危险区）：最需要重构的文件
  - **高复杂度+低变更频率**（冰冻区）：复杂但很少改动，风险可控
  - **低复杂度+高变更频率**（活跃区）：频繁改动但尚可维护
  - **低复杂度+低变更频率**（安全区）：无需关注
- 重点分析"危险区"文件：
  - 函数级复杂度热点（哪些函数贡献了最多复杂度）
  - 变更模式分析（频繁改动的原因——功能迭代？bug 修复？适配变更？）
  - 耦合度分析（co-change 文件对，识别隐式耦合）
- 识别 TODO/FIXME/HACK 密集区域及其与复杂度的关联
- 记录每个债务项：文件路径 + 函数 + 严重程度 + 债务描述 + 影响量化 + 建议动作

**Analyzer-2（覆盖率×风险）**：
- 识别测试覆盖率低于项目平均值的模块
- 交叉分析覆盖率与关键路径：
  - 低覆盖率 + 高业务重要性 = 高风险
  - 低覆盖率 + 近期 bug fix 记录 = 验证债务
  - 低覆盖率 + 高复杂度 = 测试困难
- 评估测试质量（不仅看覆盖率数字）：
  - 是否有集成测试/端到端测试覆盖
  - 是否存在只有 happy path 测试、缺少边界和异常测试
- 识别近期 bug fix 热点文件，评估其测试保护程度
- 记录每个债务项：文件路径 + 模块 + 严重程度 + 债务描述 + 影响量化 + 建议动作

### 步骤 5：合并分析 + 共识确认

两份分析报告完成后：

1. **Team lead 合并报告**：将两份报告合并为一份完整技术债务分析报告（4 个维度全覆盖）
2. **共识确认**：将合并报告发给两位 analyzer，各自查看对方的分析，可调整自己维度的评分
3. **标记共识**：两者共同指出的债务标记为"共识债务"
4. **Team lead 计算总分**：按评分公式加权

分析报告格式：

```
## 技术债务分析报告

### 总体债务评估
- 分析文件数：XXX 个
- 识别债务项：XXX 个（Critical: X | High: X | Medium: X | Low: X）
- 项目平均债务分：XX.X / 100

### 原始指标摘要（来自 scanner）
- 平均圈复杂度：XX.X | P90 复杂度：XX | 最高复杂度：XX（文件名）
- 月均变更频率 Top5：[文件列表 + 提交次数]
- 测试覆盖率：整体 XX% | 最低模块 XX%（模块名）
- TODO/FIXME/HACK 总数：XXX 个
- 近期 bug fix 涉及文件数：XX 个

### 各维度评分
**复杂度×变更频率维度（analyzer-1）**：
- 危险区文件数：XX 个 - [说明]
- 耦合度热点：XX 对 - [说明]

**覆盖率×风险维度（analyzer-2）**：
- 低覆盖高风险模块：XX 个 - [说明]
- 缺陷热点无保护：XX 个 - [说明]

### 债务列表（按分数排序）
1. [Critical] ★共识 文件路径 - 债务描述 - 分数：XX/100 - 建议动作 - 来源：analyzer-1/analyzer-2/共识
2. [High] 文件路径 - 债务描述 - 分数：XX/100 - 建议动作 - 来源：analyzer-1/analyzer-2
...
```

### 步骤 6：用户确认分析结果

Team lead 向用户展示：
- 技术债务分析报告摘要（总体评估 + 指标摘要 + 各维度评分）
- 排名前 N（`--top` 参数）的债务项列表
- 建议的处理优先级

AskUserQuestion 确认：接受分析 / 调整排序 / 排除某些项目 / 补充约束

**单轮确认模式**：首轮分析报告必须经用户确认。
**完全自主模式**：自动决策，不询问用户。

---

## 阶段二：评分与排名

### 步骤 7：启动 reporter，应用评分公式

Reporter 基于合并后的分析数据：

1. **计算每个文件的百分位排名**：
   - `complexity_percentile`：该文件圈复杂度在所有文件中的百分位
   - `churn_percentile`：该文件变更频率在所有文件中的百分位
   - `coverage`：该文件的测试覆盖率（0~1）
   - `incident_proximity`：近期是否参与 bug fix（1 或 0）

2. **应用评分公式**：
   ```
   debt_score = (complexity_percentile × 0.3) + (churn_percentile × 0.3) + ((1 - coverage) × 0.2) + (incident_proximity × 0.2)
   最终分数 = debt_score × 100
   ```

3. **按分数降序排名**，取前 N 项（`--top` 参数）

4. **分类统计**：按严重程度和债务类型汇总

### 步骤 8：趋势对比（如有历史数据）

检查 `~/.gstack/data/{slug}/techdebt.json` 是否存在：

- **存在**：与历史数据对比，为每个债务项标注趋势：
  - ↑ 恶化（分数上升）
  - ↓ 改善（分数下降）
  - → 持平（分数变化 < 5%）
  - 🆕 新增（上次不在列表中）
  - ✅ 已解决（上次在列表中，本次不在）
- **不存在**：跳过趋势对比，标注"首次分析"

---

## 阶段三：生成输出

### 步骤 9：生成 TECHDEBT.md 和 techdebt.json

Reporter 按 `--lang` 指定的语言生成最终输出。

**TECHDEBT.md**（项目根目录）格式：

```markdown
# 技术债务清单
生成时间：YYYY-MM-DD | 分析模块数：N | 发现债务项：M

## 总览
| 类别 | Critical | High | Medium | 合计 |
|------|----------|------|--------|------|
| 复杂度热点 | X | X | X | X |
| 覆盖率缺口 | X | X | X | X |
| TODO/FIXME/HACK | X | X | X | X |
| 耦合度问题 | X | X | X | X |

## 排名前 N 的债务项（按分数排序）
### 1. [模块/文件] — 分数：XX/100
- 复杂度：XX（圈复杂度） | 变更频率：XX 次提交/月
- 覆盖率：XX% | 近期缺陷：X 次
- **建议动作**：[具体操作建议]
- **预估修复工作量**：人工 X / CC Y

### 2. [模块/文件] — 分数：XX/100
...

## 趋势对比（如有历史数据）
| 文件 | 上次分数 | 本次分数 | 趋势 |
|------|---------|---------|------|
| ... | XX | XX | ↑/↓/→ |

## 分析方法说明
- 评分公式：debt_score = (complexity_percentile × 0.3) + (churn_percentile × 0.3) + ((1 - coverage) × 0.2) + (incident_proximity × 0.2)
- 数据来源：[所使用的工具列表]
- 分析范围：[整个项目 / 指定模块]
- 时间窗口：变更频率统计近 6 个月，缺陷关联统计近 3 个月
```

**techdebt.json**（`~/.gstack/data/{slug}/techdebt.json`）：
```json
{
  "generated_at": "YYYY-MM-DDTHH:mm:ssZ",
  "project": "项目名",
  "module": "分析范围",
  "summary": {
    "total_files_analyzed": N,
    "total_debt_items": M,
    "critical": X,
    "high": X,
    "medium": X,
    "low": X,
    "average_score": XX.X
  },
  "items": [
    {
      "rank": 1,
      "file": "路径",
      "score": XX.X,
      "severity": "Critical",
      "complexity": XX,
      "churn": XX,
      "coverage": XX,
      "incident_proximity": 1,
      "recommendation": "建议动作",
      "trend": "↑/↓/→/新增"
    }
  ],
  "metadata": {
    "tools_used": ["工具列表"],
    "time_window_churn": "6 months",
    "time_window_incidents": "3 months",
    "scoring_formula": "debt_score = (complexity_percentile × 0.3) + (churn_percentile × 0.3) + ((1 - coverage) × 0.2) + (incident_proximity × 0.2)"
  }
}
```

### 步骤 10：最终报告

Team lead 按 `--lang` 指定的语言向用户输出：

```
## 技术债务分析最终报告

### 元信息
- 生成时间：YYYY-MM-DD HH:mm:ss
- 团队名称：team-techdebt-{YYYYMMDD-HHmmss}
- 执行模式：标准模式 / 单轮确认模式 / 完全自主模式
- 输出语言：zh / en
- 分析范围：[整个项目 / --module 指定路径]
- 展示数量：前 N 项（--top 参数）

### 总体评估
- 分析文件数：XXX 个
- 识别债务项：XXX 个（Critical: X | High: X | Medium: X | Low: X）
- 项目平均债务分：XX.X / 100

### 关键发现
1. [最重要的发现 1]
2. [最重要的发现 2]
3. [最重要的发现 3]

### 趋势总结（如有历史数据）
- 与上次对比：新增 X 项 | 改善 X 项 | 恶化 X 项 | 已解决 X 项
- 整体趋势：改善 / 恶化 / 持平

### 输出文件
- TECHDEBT.md：项目根目录（完整债务清单）
- techdebt.json：~/.gstack/data/{slug}/techdebt.json（结构化数据，供跨技能消费）

### 自主决策汇总（单轮确认模式/完全自主模式）
| 决策节点 | 决策内容 | 理由 |
|---------|---------|------|
| [阶段/步骤] | [决策描述] | [理由] |

### 附录：分析共识说明
- analyzer-1 识别的债务：[数量] 个
- analyzer-2 识别的债务：[数量] 个
- 共识债务：[数量] 个（共识度 = XX%）
- 仅 analyzer-1 识别：[列表]
- 仅 analyzer-2 识别：[列表]
- 分歧处理记录：[如有评分校准，记录校准前后差值和理由]
- 盲区标注：[未覆盖的债务类型，如有]
```

### 步骤 10.5：跨团队衔接建议（可选）

Team lead 根据项目情况向用户建议后续动作：
- **发现大量复杂度热点**：建议运行 `/team-arch` 评估架构重构方案
- **发现覆盖率严重不足**：建议补充测试（可结合 CC 自动生成测试用例）
- **发现安全相关技术债务（如硬编码密钥、过期依赖）**：建议运行 `/team-security` 评估安全风险
- **发现性能相关技术债务（如 O(n²) 算法热点）**：建议运行 `/team-perf` 进行性能优化
- 用户可选择执行或跳过，不强制。

### 步骤 11：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 核心原则

- **数据驱动**：所有分析基于 scanner 量化数据，不做主观臆断
- **双路互补**：复杂度×变更频率分析 + 覆盖率×风险分析独立并行，共识优先处理
- **公式透明**：评分公式公开透明，每个债务项的分数可追溯到具体维度
- **量化对比**：如有历史数据，展示趋势变化，用数字说明改善/恶化
- **可操作性**：每个债务项附带具体建议动作和预估工作量
- **增量分析**：支持 `--module` 聚焦分析，支持历史对比跟踪趋势

---

## 常用静态分析工具参考

| 语言/平台 | 复杂度分析 | 覆盖率 | 代码质量 |
|-----------|-----------|--------|---------|
| Go | gocyclo, gocognit | go test -cover | golangci-lint |
| Python | radon, flake8 | pytest-cov, coverage.py | pylint, ruff |
| Rust | clippy | tarpaulin, llvm-cov | clippy |
| Java/Kotlin | PMD, SpotBugs | JaCoCo | Checkstyle |
| Node.js/TypeScript | eslint complexity | nyc, jest --coverage | eslint |
| C/C++ | lizard, cppcheck | gcov, lcov | cppcheck |
| 通用 | lizard, scc | — | — |

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| 项目不是 git 仓库 | 跳过变更频率和缺陷关联分析，仅基于复杂度和覆盖率评分（权重重新分配：复杂度 50% + 覆盖率 50%） |
| 复杂度工具未安装/无法运行 | 尝试 lizard（跨语言通用工具），仍失败则手动代码分析 Top10 最大文件 |
| 无测试框架/覆盖率数据 | 覆盖率维度默认 coverage=0，在报告中标注"覆盖率数据不可用" |
| git 历史过短（< 3 个月） | 调整时间窗口为全部历史，在报告中标注 |
| `--module` 路径不存在 | 暂停，向用户报告路径无效，要求确认 |
| 项目过大导致扫描超时 | 触发熔断，暂停问用户，建议使用 `--module` 缩小范围 |
| 双 analyzer 结论冲突 | Reporter 优先采纳共识部分，冲突部分标注"待人工确认" |
| 历史 techdebt.json 格式不兼容 | 跳过趋势对比，标注"历史数据格式不兼容，视为首次分析" |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前阶段恢复 |
| 外部依赖导致的技术债务 | Analyzer 标注为外部债务，建议应用层缓解策略（封装、抽象、替换计划） |

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

