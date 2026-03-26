---
name: team-adr
description: 启动一个架构决策记录团队（researcher/writer×2/reviewer），通过代码上下文分析+双写手独立撰写+交叉审查，输出标准化ADR文档并提交到代码仓库。使用方式：/team-adr [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--title=标题] [--query=关键词] [--lang=zh|en] ADR主题描述
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--title=标题] [--query=关键词] [--lang=zh|en] ADR主题描述
---

**参数解析**：从 `$ARGUMENTS` 中检测以下标志：
- `--auto`：完全自主模式（不询问用户任何问题，全程自动决策）
- `--once`：单轮确认模式（将所有需要确认的问题合并为一轮提问，确认后全程自动执行）
- `--title=标题`：ADR 标题（可选，未指定时由 researcher 根据上下文生成）
- `--query=关键词`：查询模式——搜索已有 ADR 回答"我们为什么选了 X？"（指定后进入查询模式，不创建新 ADR）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 上下文确认 + 草稿选择 + 最终文档确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅最终文档确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下条件节点自动决策规则：
- **ADR 标题不确定** → researcher 根据上下文自行拟定，在最终文档中说明
- **两位 writer 草稿分歧** → reviewer 标注分歧，team lead 综合论证后裁决，收尾时汇总
- **分歧超过 50%** → **不可跳过，必须暂停问用户**（熔断机制）
- **reviewer 异议超过 3 项** → **不可跳过，必须暂停问用户**（熔断机制）
- **已存在相似 ADR** → researcher 标注已有 ADR 编号和标题，team lead 决定是新建还是 supersede

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效（分歧超过 50%、reviewer 异议超过 3 项时仍必须暂停问用户）。

**工作模式说明**：

| 模式 | 触发条件 | 行为 |
|------|---------|------|
| **记录模式**（默认） | 未指定 `--query` | 根据当前讨论/上下文创建新的 ADR 文档 |
| **查询模式** | 指定 `--query=关键词` | 搜索 `docs/decisions/` 下已有 ADR，回答"我们为什么选了 X？" |

**查询模式流程**：researcher 扫描 `docs/decisions/` 目录，按关键词匹配标题和内容，向用户展示匹配的 ADR 列表及摘要，无需创建团队。以下流程仅适用于**记录模式**。

使用 TeamCreate 创建 team（名称格式 `team-adr-{YYYYMMDD-HHmmss}`，如 `team-adr-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

## 流程概览

```
阶段零  上下文采集 → researcher 扫描 git 历史 + 代码变更 + 已有 ADR → 输出决策上下文报告
         ↓
阶段一  并行撰写 → writer-1 独立撰写 ADR + writer-2 独立撰写 ADR
         ↓
阶段二  合并审查 → reviewer 对比两份草稿 → 输出：共识/分歧/遗漏清单 → 合并最佳部分 → 检查熔断
         ↓
阶段三  用户确认 + 提交 → team lead 展示最终 ADR → 用户确认 → 写入文件 + 更新索引 + 提交
```

## 角色定义

| 角色 | 职责 |
|------|------|
| researcher | 扫描 git 历史、近期代码变更、已有 ADR 目录，收集决策背景信息。识别相关的代码文件、PR、讨论。分析已有 ADR 避免重复。**只做上下文采集，不撰写 ADR 正文。** |
| writer-1 | 基于 researcher 的上下文报告，独立撰写完整 ADR 文档（遵循标准模板）。**独立撰写阶段不与 writer-2 交流。** |
| writer-2 | 同 writer-1 的职责，独立执行相同撰写。**独立撰写阶段不与 writer-1 交流。** |
| reviewer | 对比两份 ADR 草稿，标注共识/分歧/遗漏，合并最佳部分，检查 ADR 完整性和准确性。**只做审查合并，不直接阅读代码，不收集上下文。** |

---

## 阶段零：上下文采集

### 步骤 1：启动 researcher

Team lead 启动 researcher，指示其采集以下信息：
- `docs/decisions/` 目录下已有 ADR 列表（编号、标题、状态）
- 最新 ADR 编号（用于自增生成下一个编号 NNNN）
- Git 近期提交历史（最近 50 条，聚焦与决策主题相关的提交）
- 近期代码变更（与决策主题相关的文件变更）
- 相关 PR 和讨论（如果可从 git log 中获取）
- 是否存在与当前主题相似的已有 ADR（标题/内容匹配）

### 步骤 2：Researcher 输出上下文报告

Researcher 输出**决策上下文报告**，包含：
- 下一个可用 ADR 编号（NNNN）
- 建议的 ADR 标题（如果用户未通过 `--title` 指定）
- 决策背景摘要（从 git 历史和代码变更中提炼）
- 相关代码文件列表（路径 + 简要说明）
- 已有相关 ADR 列表（编号 + 标题 + 状态）
- 已考虑的替代方案线索（从代码注释、PR 讨论中提取）

### 步骤 3：确认上下文

**标准模式**：team lead 向用户展示上下文报告摘要（ADR 编号、标题、背景要点），AskUserQuestion 确认：
- 标题是否合适
- 背景信息是否充分
- 是否需要补充上下文

**单轮确认模式**：team lead 自行确认，收尾汇总时说明
**完全自主模式**：自动决策，不询问用户

---

## 阶段一：并行撰写

### 步骤 4：启动 writer-1 和 writer-2

两者并行启动，全程保持存活直到收尾。

Team lead 将 researcher 的上下文报告分发给两位 writer，并附上 ADR 标准模板。

**Writer-1 和 Writer-2 各自独立撰写**（team lead 必须确保两者不互相看到对方的草稿）：

每位 writer 基于上下文报告撰写完整 ADR，遵循以下标准模板：

```markdown
# ADR-NNNN: {Title}

Date: YYYY-MM-DD
Status: Proposed | Accepted | Deprecated | Superseded by ADR-XXXX

## Context
[What is the issue that we're seeing that is motivating this decision or change?]

## Decision
[What is the change that we're proposing and/or doing?]

## Consequences
### Positive
- [What becomes easier or possible as a result of this change?]

### Negative
- [What becomes harder or impossible as a result of this change?]

### Risks
- [What risks does this decision introduce?]

## Alternatives Considered
| Alternative | Pros | Cons | Why Not Chosen |
|------------|------|------|----------------|

## References
- [Links to relevant code, PRs, discussions]
```

撰写要求：
1. **Context** 必须基于 researcher 提供的真实代码/git 证据，不得编造
2. **Decision** 必须清晰明确，说明具体做什么、怎么做
3. **Consequences** 必须同时包含正面和负面影响，以及风险
4. **Alternatives Considered** 至少列出 2 个替代方案，并说明未选择的原因
5. **References** 必须包含实际的代码路径或 PR 链接

### 步骤 5：收集草稿

两者完成后各自向 team lead 发送草稿。Team lead 确认收到全部 2 份草稿后，进入阶段二。

---

## 阶段二：合并审查

### 步骤 6：启动 reviewer

Team lead 启动 reviewer，将以下内容传递：
- Researcher 的上下文报告
- Writer-1 的 ADR 草稿（标记为"草稿 A"）
- Writer-2 的 ADR 草稿（标记为"草稿 B"）

**重要**：传递时不透露 writer 编号，仅用"草稿 A"和"草稿 B"标记，避免暗示优先级。

### 步骤 7：Reviewer 对比审查

Reviewer 逐节对比两份 ADR 草稿，输出结构化审查结果：

| 对比结果 | 处理方式 |
|---------|---------|
| **一致结论** | 直接采纳，标记为"共识" |
| **互补内容**（A 提到了 B 没覆盖的点，或反之） | 合并，标记为"互补" |
| **措辞/粒度差异**（本质相同，表述不同） | 选择更清晰准确的表述，标记为"共识" |
| **分歧/矛盾**（对同一决策有不同判断） | 标注为"待仲裁"，记录双方观点 |

Reviewer 输出：
1. **共识清单**：双方一致的核心内容
2. **互补清单**：一方独有的有价值内容
3. **分歧清单**：矛盾之处及双方观点对比
4. **遗漏清单**：两人都未充分覆盖的 ADR 必要部分（对照模板检查遗漏）
5. **共识度评估**：共识度 = (共识内容数 + 互补内容数) / 总内容数(去重并集) x 100%
6. **合并后的最终 ADR 文档**：基于共识和互补内容合并生成

**Reviewer 处理矛盾的原则**：reviewer 不直接阅读代码，当两份草稿对同一决策存在根本性矛盾时，必须标注为"待仲裁"并升级给 team lead，不得自行裁决。

### 步骤 8：检查熔断条件

如果共识度 < 50%（分歧占比超过一半）：
- **必须暂停**，team lead 向用户报告情况
- 可能原因：决策主题描述不够明确、上下文信息不足
- 建议：补充上下文或明确决策范围

共识度 >= 50%：继续下一阶段。

### 步骤 9：处理遗漏

如果遗漏清单非空：
- Team lead 将遗漏清单分配给两位 writer，要求补充撰写遗漏的部分
- Writer 补充后将补充内容发送给 reviewer
- Reviewer 将补充内容整合到合并 ADR 中

如果遗漏清单为空：直接进入下一阶段。

### 步骤 10：分歧仲裁

如果分歧清单为空 -> 跳过仲裁，直接进入阶段三。

Team lead 对分歧清单中的每个分歧点：

1. 将分歧描述分别发给 writer-1 和 writer-2，要求各自提供论证：
   - 你的判断是什么？
   - 依据是哪些代码/文件/历史记录？
   - 为什么你认为对方的表述不准确？

2. 收到双方论证后：
   - **标准模式**：team lead 向用户展示分歧摘要和双方论证，AskUserQuestion 让用户裁决
   - **单轮确认模式/完全自主模式**：team lead 综合双方论证和代码证据自行裁决

3. 将仲裁结果发送给 reviewer 更新合并 ADR

### 步骤 11：Reviewer 更新合并 ADR

Reviewer 根据仲裁结果和补充内容更新合并 ADR，将所有"待仲裁"项替换为最终结论。输出**最终 ADR 文档**。

---

## 阶段三：用户确认 + 提交

### 步骤 12：用户确认

Team lead 向用户展示最终 ADR 摘要：
- ADR 编号和标题
- 决策概要（一句话）
- 替代方案数量
- 正面/负面后果要点
- 共识度
- 分歧数量及处理结果

AskUserQuestion 确认：
- 接受 ADR
- 需要修改某些部分
- 需要补充信息

**单轮确认模式**：必须经用户确认。
**完全自主模式**：自动决策，不询问用户。

### 步骤 13：写入文件

将最终 ADR 文档保存到项目的 `docs/decisions/` 目录：
- 文件名：`NNNN-{slug}.md`（NNNN 为自增编号，slug 由标题生成，小写字母+连字符）
- 如果目录不存在，创建之

### 步骤 14：更新索引

更新 `docs/decisions/README.md` 索引文件：
- 如果文件不存在，创建包含表头的索引文件
- 在索引表中追加新 ADR 记录

索引文件格式：
```markdown
# Architecture Decision Records

| 编号 | 标题 | 状态 | 日期 |
|------|------|------|------|
| ADR-NNNN | [标题](NNNN-slug.md) | Proposed | YYYY-MM-DD |
```

### 步骤 15：提交到代码仓库

执行 git 提交：
- `git add docs/decisions/NNNN-{slug}.md docs/decisions/README.md`
- `git commit -m "docs(adr): ADR-NNNN {title}"`

### 步骤 16：最终总结

Team lead 向用户输出：
- 创建了什么（ADR 编号、标题、状态）
- 决策概要
- 文件保存位置
- 索引更新情况
- git 提交信息
- **（单轮确认模式/完全自主模式）自动决策汇总**：列出所有自动决策的节点、决策内容和理由

### 步骤 17：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 核心原则

- **上下文先行**：researcher 先采集 git 历史和代码变更，为 writer 提供真实证据
- **独立撰写**：两位 writer 必须完全独立工作，不互相看到对方草稿，确保内容的多样性和完整性
- **职责分离**：researcher 只做上下文采集，writer 只做撰写，reviewer 只做审查合并
- **证据驱动**：ADR 中的每个论点必须有代码/git/PR 证据支撑，不得编造
- **标准化模板**：所有 ADR 遵循统一模板，确保可读性和一致性
- **索引维护**：每次创建 ADR 同步更新索引文件，保证可查询性
- **版本控制**：ADR 通过 git 提交管理，与代码变更保持同步

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| `docs/decisions/` 目录不存在 | 自动创建目录及 README.md 索引文件 |
| 无法确定下一个 ADR 编号 | Researcher 扫描目录获取最大编号后 +1，目录为空则从 0001 开始 |
| Git 历史中找不到相关上下文 | Researcher 标注"无历史记录"，writer 基于用户提供的描述撰写 |
| 已存在相似标题的 ADR | Researcher 标注已有 ADR，team lead 决定新建还是 supersede 旧 ADR |
| 两位 writer 草稿差异极大（共识度 < 50%） | 触发熔断，暂停问用户确认决策范围 |
| Reviewer 异议 >= 3 项 | 触发熔断，暂停问用户确认是否存在理解偏差 |
| Writer 无法理解决策上下文 | 在草稿中标注"上下文不足"，reviewer 归入遗漏清单 |
| 项目缺少 git 历史 | Researcher 基于当前代码结构和用户描述推断上下文 |
| 遗漏清单非空 | Writer 补充撰写遗漏部分后 reviewer 更新合并结果 |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前阶段恢复。如果是 writer 崩溃，检查已发送的部分草稿决定是否需要重新撰写。 |
| git commit 失败 | Team lead 展示错误信息，建议用户手动提交，不阻塞 ADR 文档生成 |
| 查询模式无匹配结果 | 向用户展示所有已有 ADR 列表，建议调整关键词或创建新 ADR |

---

## 需求

$ARGUMENTS
