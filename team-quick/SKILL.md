---
name: team-quick
description: 启动一个轻量级迭代开发团队（planner + coder），快速完成小 feature、配置变更、中小 bugfix 等日常迭代任务。相比 team-dev 大幅精简流程（2 角色 3 阶段），专注速度。使用方式：/team-quick [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--lang=zh|en] 需求描述
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--lang=zh|en] 需求描述
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
- `--once`：单轮确认模式（仅方案确认一次，确认后全程自动执行）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后将标志从需求描述中移除。

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 方案确认 + review 不通过时通知 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅方案确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下自动决策规则：
- **方案细节不确定** → planner 自行判断，收尾时汇总
- **review 不通过** → coder 自行修复，不升级用户
- **修复迭代超 3 轮** → **不可跳过，必须暂停问用户**（熔断机制）

完全自主模式下：所有节点均自动决策。唯一例外：review 迭代超 3 轮仍自动停止（team lead 自行裁决是否继续）。

使用 TeamCreate 创建 team（名称格式 `team-quick-{YYYYMMDD-HHmmss}`，如 `team-quick-20260407-100000`，避免多次调用冲突），你作为 team lead 按以下流程协调。

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


## 适用场景

| 适用 | 不适用（建议用 team-dev） |
|------|------------------------|
| 单一功能点新增/修改 | 跨多模块的新系统/子系统 |
| 小型配置变更 | 架构变更 |
| 中小型 bugfix | 需要双路独立设计验证的复杂需求 |
| 简单性能优化 | 需要集成测试覆盖的大型功能 |
| 工具函数/辅助功能 | 涉及 3 个以上模块联动的需求 |
| 单文件或少量文件改动 | 需要分阶段实施的大型改动 |

> 如果 team lead 在阶段零判断需求超出轻量级范围，应主动建议用户改用 `/team-dev`。

## 流程概览

```
阶段零  快速分析 → planner 阅读代码 + 输出实现方案 → 用户确认
         ↓
阶段一  实现 + 审查 → coder TDD 编码 + 自检 → planner 快速 review → 循环直到通过
         ↓
阶段二  收尾 → 全量测试验证 → 总结 + 清理
```

## 角色定义

| 角色 | 职责 |
|------|------|
| planner | 阅读代码、分析需求、识别技术栈和测试框架、输出实现方案（修改范围 + 具体方法 + 验收标准）。编码完成后快速 review（正确性 + 安全性 + 方案一致性）。**不编写实现代码，只做分析、设计和审查。** |
| coder | 根据实现方案 TDD 编码（先写测试再写实现）、执行自检清单、修复 review 问题。 |

---

## 阶段零：快速分析

### 步骤 1：需求理解与范围评估

Team lead 解析用户需求，快速判断是否适合轻量级流程：
- 如果需求涉及 3 个以上模块联动或架构变更 → 建议用户改用 `/team-dev`
- 否则继续

### 步骤 2：启动 planner

启动 planner，传入用户需求描述。Planner 执行：

1. **阅读相关代码**：根据需求定位相关文件和模块，理解现有实现
2. **识别技术栈**：语言、框架、构建工具、测试框架
3. **输出实现方案**，写入 `/tmp/{team-name}/planner-plan.md`，包含：
   - **需求摘要**：一句话描述要做什么
   - **修改范围**：需要新增/修改的文件列表（精确到文件路径）
   - **实现方法**：每个文件的具体修改逻辑（改什么、怎么改）
   - **验收标准**：可验证的完成条件（2-5 条）
   - **测试策略**：需要编写的测试用例概述（如项目有测试基础设施）
   - **风险点**：可能的坑或需要注意的地方（如有）

通过 SendMessage 向 team lead 发送文件路径和 ≤500 字符摘要。

### 步骤 3：用户确认

确认方式：
- **标准模式**：team lead 向用户输出方案摘要，AskUserQuestion 确认
- **单轮确认模式**：向用户展示方案摘要，AskUserQuestion 确认（这是唯一一次交互）
- **完全自主模式**：跳过确认，直接进入下一阶段

---

## 阶段一：实现与审查

### 步骤 4：启动 coder，TDD 编码

启动 coder，传入 planner 的实现方案。

**TDD 编码**（如项目有测试基础设施）：
- 根据方案中的测试策略编写测试用例
- 运行测试确认失败（红）
- 编写实现代码使测试通过（绿）
- 测试全部通过后，执行自检清单

**无测试基础设施时**：
- 直接编写实现代码
- 执行自检清单（跳过测试相关项）

### 步骤 5：Coder 自检

自检清单（提交审查前必须完成）：
1. 运行 lint/format（如项目有配置）
2. 全量单测通过（如项目有测试）
3. 无编译警告
4. 修改范围与方案一致（无超出范围的改动）

自检全部通过后，通知 planner 和 team lead。

### 步骤 6：Planner 快速 review

Planner 审查 coder 的代码变更，聚焦三个维度：

| 维度 | 审查内容 | 是否阻塞 |
|------|---------|---------|
| 正确性 | 逻辑是否正确，边界条件是否处理 | 是 |
| 安全性 | 是否有注入/XSS/敏感数据泄露等风险 | 是 |
| 方案一致性 | 实现是否符合方案，无超出范围的改动 | 是 |

Review 结果写入 `/tmp/{team-name}/review-round-{N}.md`，通过 SendMessage 向 team lead 发送文件路径和 ≤500 字符摘要。

### 步骤 7：Review 不通过处理

不通过则列出具体问题，coder 修复后重新自检并提交，循环直到通过。

**最大迭代轮次：3 轮。** 超出后触发熔断，team lead 向用户汇报当前状态，由用户决定继续、调整方向或终止。

---

## 阶段二：收尾

### 步骤 8：全量测试验证

Review 通过后，coder 运行全量测试（如项目有测试基础设施），确认无回归。

如有测试失败：
- coder 自行修复 → planner 重新 review → 循环（计入步骤 7 的迭代上限）

### 步骤 9：最终总结

Team lead 按 `--lang` 指定的语言向用户输出：
- 实现了什么（对照验收标准逐项确认）
- 修改的文件列表
- 测试覆盖情况（如有）
- 已知的限制或遗留问题（如有）
- **（单轮确认模式/完全自主模式）自动决策汇总**：列出所有自动决策的节点、决策内容和理由

### 步骤 9.5：跨团队衔接建议（可选）

Team lead 根据情况向用户建议后续动作：
- **修改涉及多处相似逻辑**：建议运行 `/team-review` 做全面审查
- **修改涉及 API 接口变更**：建议检查 API 兼容性
- 用户可选择执行或跳过，不强制。

### 步骤 10：清理

关闭所有 teammate，执行 `rm -rf /tmp/{team-name}` 清理工作目录，用 TeamDelete 清理 team。

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| 需求超出轻量级范围 | Team lead 建议改用 `/team-dev`，AskUserQuestion 确认 |
| Coder 编译/运行失败 | Coder 自行修复；无法修复则升级 team lead，由 planner 协助分析 |
| Review 迭代超 3 轮 | 触发熔断，向用户汇报当前状态 |
| 全量测试发现非相关失败 | Coder 评估是否为已有问题（git stash + 测试确认）；是已有问题则记录并继续，是新引入则修复 |
| Planner 方案与实际代码不符 | Planner 重新阅读代码修正方案，通知 coder 调整 |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从最近的检查点恢复 |

---

## 核心原则

- **速度优先**：2 角色 3 阶段，最小化协调开销
- **够用就好**：不搞双路独立设计、不搞组会讨论、不搞集成测试阶段
- **TDD 保底**：有测试基础设施就 TDD，保证基本质量
- **快速 review**：聚焦正确性、安全性、方案一致性三个维度，不做面面俱到的审查
- **有限迭代**：review 最多 3 轮，超出则暂停问用户
- **知道边界**：超出轻量级范围时主动建议用 team-dev

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

