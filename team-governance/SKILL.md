---
name: team-governance
description: 启动一个 AI/Agent 治理团队（scanner/auditor×2/analyst/reporter），通过 Agent 配置扫描+双路独立审计（权限边界+数据流安全 vs prompt 注入+输出可信度）+风险分析+报告生成，输出 Agent 治理审计报告和安全加固建议。使用方式：/team-governance [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--scope=agents|llm-usage|data-flow|full] [--framework=owasp-agentic|custom] [--lang=zh|en] 项目路径或 AI/Agent 治理审计需求
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--scope=agents|llm-usage|data-flow|full] [--framework=owasp-agentic|custom] [--lang=zh|en] 项目路径或 AI/Agent 治理审计需求
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
- `--scope=agents|llm-usage|data-flow|full`：审计范围（可选，默认 `full`）
- `--framework=owasp-agentic|custom`：治理框架（可选，默认 `owasp-agentic`）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后将标志从审计需求描述中移除。

**审计范围说明**：
- `agents`：聚焦 AI Agent 配置和行为（权限、工具调用、自主决策边界）
- `llm-usage`：聚焦 LLM API 调用（prompt 安全、输出验证、成本控制）
- `data-flow`：聚焦 AI 相关数据流（训练数据、用户输入、模型输出的安全传递）
- `full`：全面审计（以上所有维度）

**治理框架说明**：
- `owasp-agentic`：基于 OWASP Agentic AI Top 10 风险清单进行审计
- `custom`：自定义审计规则（根据项目特点灵活配置检查项）

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 审计范围确认 + 最终报告确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅最终报告确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下自动决策规则：
- **Agent 行为分类不确定** → 对应 auditor 自行判断，报告中说明
- **两位 auditor 对同一风险的评级差异过大（相差 2 级及以上）** → **不可跳过，必须暂停问用户**（熔断机制）
- **高危风险超过 8 个** → **不可跳过，必须暂停问用户**（熔断机制）
- **Agent 配置文件不可访问** → scanner 标注"该配置不可用"，不阻塞流程
- **Agent 数量超出预期（> 20 个独立 Agent）** → analyst 自行决定是否分组审计

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效（评级差异过大、高危风险超过 8 个时仍必须暂停问用户）。

使用 TeamCreate 创建 team（名称格式 `team-governance-{YYYYMMDD-HHmmss}`，如 `team-governance-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

## 流程概览

```
阶段零  Agent 发现 + 范围确认 → 识别项目中的 AI/Agent 组件、LLM 调用、数据流，确认审计目标
         ↓
阶段一  配置扫描 + 双路独立审计（并行）
         ├─ scanner：Agent 配置扫描（Agent 发现、工具注册、权限配置、LLM API 调用模式）
         ├─ auditor-1：权限边界与数据流审计（Agent 权限范围、工具调用安全、数据泄露路径、PII 处理）
         └─ auditor-2：Prompt 安全与输出可信度审计（prompt 注入防护、输出验证、幻觉检测、成本控制）
         ↓
阶段二  风险分析 → analyst 合并发现，映射 OWASP Agentic Top 10，输出统一风险评估
         → 熔断检查（评级差异过大 / 高危风险 > 8）
         ↓
阶段三  报告生成 → reporter 生成治理审计报告 + 安全加固建议
         ↓
阶段四  保存报告 + 清理团队
```

## 角色定义

| 角色 | 职责 |
|------|------|
| scanner | 发现项目中所有 AI/Agent 组件（Claude Agent、LangChain Agent、AutoGPT、自定义 Agent），扫描 Agent 配置（System Prompt、工具注册、权限设置、MCP 服务器配置），统计 LLM API 调用模式（Provider、模型、Token 用量），映射 AI 数据流（输入→处理→输出路径），输出客观扫描数据。**仅在扫描阶段工作，完成后关闭。** |
| auditor-1 | **权限边界与数据流维度审计**：检查 Agent 权限范围（文件系统/网络/数据库/代码执行访问权限）、工具调用安全（工具白名单/参数校验/执行沙箱）、Agent 间通信安全（信息传递边界/权限继承）、数据泄露路径（用户数据→LLM→日志/第三方）、PII 处理合规。输出结构化审计发现。**不修改代码。独立审计，不与 auditor-2 交流。** |
| auditor-2 | **Prompt 安全与输出可信度维度审计**：检查 prompt 注入防护（直接注入/间接注入/越狱攻击）、输出验证（LLM 输出格式校验/内容过滤/执行前审查）、幻觉与可信度（事实核查机制/置信度评分/回退策略）、成本与资源控制（Token 限制/并发控制/费用上限/递归防护）。输出结构化审计发现。**不修改代码。独立审计，不与 auditor-1 交流。** |
| analyst | 合并两份审计报告和 scanner 扫描结果，映射到 OWASP Agentic AI Top 10 风险清单，去重、交叉校验、识别覆盖盲区，输出统一风险评估清单。**不直接阅读代码，只对比和合并报告。完成后关闭。** |
| reporter | 基于统一风险评估清单生成治理审计报告（含风险清单、OWASP 映射、缓解方案、加固路线图），按 `--lang` 语言输出。**完成后关闭。** |

### 角色生命周期

| 角色 | 启动阶段 | 关闭时机 | 说明 |
|------|---------|---------|------|
| scanner | 阶段一（步骤 3） | 阶段一扫描完成后（步骤 3） | 扫描报告交付后即释放 |
| auditor-1 | 阶段一（步骤 3，与 scanner 并行） | 阶段一审计完成后（步骤 5） | 审计报告交付后释放 |
| auditor-2 | 阶段一（步骤 3，与 scanner 并行） | 阶段一审计完成后（步骤 5） | 审计报告交付后释放 |
| analyst | 阶段二（步骤 6） | 阶段二合并完成后（步骤 9） | 统一风险评估清单输出后释放 |
| reporter | 阶段三（步骤 10） | 阶段三报告生成后（步骤 12） | 报告确认后释放 |

---

## OWASP Agentic AI Top 10 风险

每个风险项按合规状态定级：

| 状态 | 含义 | 是否需要整改 |
|------|------|-------------|
| **合规** | 已实施充分的缓解控制 | 无需整改 |
| **部分合规** | 有一定控制但存在缺口 | 需要整改 |
| **不合规** | 缺乏必要的缓解控制 | 必须整改 |
| **不适用** | 该风险项不适用于当前系统 | 无需整改 |

### OWASP Agentic AI Top 10 风险清单

| 编号 | 风险名称 | 描述 | 审计维度 |
|------|---------|------|---------|
| **AG01** | Agentic Excessive Agency | Agent 拥有超出必要的权限和自主权 | auditor-1 |
| **AG02** | Agentic Identity and Access Failures | Agent 身份认证和访问控制缺陷 | auditor-1 |
| **AG03** | Agentic Supply Chain Vulnerabilities | Agent 工具链和依赖的供应链风险 | auditor-1 |
| **AG04** | Agentic Knowledge Poisoning | Agent 知识库/训练数据被污染 | auditor-2 |
| **AG05** | Agentic Memory Threats | Agent 记忆/上下文管理的安全威胁 | auditor-2 |
| **AG06** | Agentic Prompt Injection | 直接/间接 prompt 注入攻击 | auditor-2 |
| **AG07** | Agentic Hallucination Exploitation | 利用 LLM 幻觉进行攻击 | auditor-2 |
| **AG08** | Agentic Misalignment | Agent 行为与预期目标不一致 | auditor-1 |
| **AG09** | Agentic Denial of Service / Wallet | 资源耗尽/成本失控攻击 | auditor-2 |
| **AG10** | Agentic Logging and Monitoring Failures | Agent 行为日志和监控缺失 | auditor-1 |

---

## 审计维度分配

双 auditor 按各自负责的 OWASP 风险项独立审计，analyst 按权重合并为风险评估总分。

| 风险项 | 权重 | 负责人 | 审计内容 |
|--------|------|--------|---------|
| AG01 Excessive Agency | 15% | auditor-1 | 最小权限原则、工具白名单、自主决策边界、人工审批关卡 |
| AG02 Identity & Access | 10% | auditor-1 | Agent 身份管理、API Key 安全、多 Agent 间信任链、权限继承 |
| AG03 Supply Chain | 10% | auditor-1 | MCP 服务器安全、第三方工具审计、插件/扩展安全、依赖完整性 |
| AG04 Knowledge Poisoning | 10% | auditor-2 | RAG 数据源验证、知识库更新审计、训练数据完整性、数据投毒检测 |
| AG05 Memory Threats | 10% | auditor-2 | 上下文窗口管理、会话隔离、记忆持久化安全、跨会话信息泄露 |
| AG06 Prompt Injection | 15% | auditor-2 | 直接注入防护、间接注入（数据中嵌入指令）、越狱攻击、System Prompt 泄露 |
| AG07 Hallucination | 10% | auditor-2 | 输出验证机制、事实核查、置信度评估、回退策略、人工审核流程 |
| AG08 Misalignment | 5% | auditor-1 | 目标对齐验证、行为边界检测、异常行为告警、Agent 评估指标 |
| AG09 DoS / Wallet | 10% | auditor-2 | Token 限制、并发控制、费用上限、递归/循环防护、速率限制 |
| AG10 Logging & Monitoring | 5% | auditor-1 | Agent 行为日志、决策追踪、工具调用审计、异常检测、告警机制 |

**auditor-1 总权重：45%**（AG01 15% + AG02 10% + AG03 10% + AG08 5% + AG10 5%）
**auditor-2 总权重：55%**（AG04 10% + AG05 10% + AG06 15% + AG07 10% + AG09 10%）

---

## 阶段零：Agent 发现 + 范围确认

### 步骤 1：解析审计范围

Team lead 分析项目和参数：

1. 解析 `--scope` 参数，确定审计范围
2. 解析 `--framework` 参数，确定治理框架
3. 阅读项目结构，识别 AI/Agent 组件：
   - Agent 框架（Claude Agent SDK、LangChain/LangGraph、AutoGPT、CrewAI、自定义）
   - LLM API 调用（OpenAI、Anthropic、Google、Azure、本地模型）
   - MCP 服务器配置（`.claude/`、`mcp.json`、工具注册）
   - Agent 配置文件（System Prompt、SKILL.md、Agent 定义文件）
   - 工具/插件注册（函数调用、工具列表、权限配置）
   - RAG/知识库（向量数据库、文档索引、检索配置）
   - AI 数据流（用户输入→预处理→LLM→后处理→输出→存储）
4. 识别 Agent 间关系（编排模式、委托链、并行执行）
5. 输出 AI/Agent 清单和审计范围

### 步骤 2：用户确认审计范围

**标准模式**：向用户展示 AI/Agent 清单和审计范围，AskUserQuestion 确认：
- 确认审计范围和治理框架
- 补充 Agent 配置信息（外部 MCP 服务器、API 密钥管理方式）
- 调整审计重点（特定 Agent 或特定风险维度）

**单轮确认模式**：跳过确认，直接进入阶段一。
**完全自主模式**：自动决策，不询问用户，直接进入阶段一。

---

## 阶段一：配置扫描 + 双路 Agent 审计

### 步骤 3：启动 scanner 和双 auditor

三者并行启动。

**Scanner Agent 配置扫描**：
1. 发现所有 AI/Agent 组件：
   - 扫描 Agent 定义文件（SKILL.md、Agent 配置 YAML/JSON、LangChain Agent 定义）
   - 识别 LLM API 调用点（SDK 初始化、API 请求构造、模型选择）
   - 解析 MCP 服务器配置（工具列表、权限设置、沙箱配置）
   - 发现 RAG/知识库组件（向量 DB 连接、文档加载器、检索器）
2. 统计 LLM 使用模式：
   - 模型/Provider 清单
   - 调用频率和 Token 用量估算
   - 上下文窗口使用模式
   - 流式/批量调用模式
3. 映射 AI 数据流：
   - 输入路径（用户输入来源、数据预处理）
   - 处理路径（Prompt 构造、LLM 调用、输出解析）
   - 输出路径（结果展示、操作执行、数据存储）
   - 敏感数据路径（PII 经过 LLM 的路径、API Key 存储方式）
4. 输出**Agent 配置扫描报告**
5. Scanner 完成后关闭

**双 auditor 同时阅读项目**：
- 阅读 Agent 配置和代码实现
- 理解 Agent 架构和交互模式
- 梳理各自负责维度的审计要点
- 各自输出项目 AI 安全概况给 team lead

### 步骤 4：分发 scanner 报告

Team lead 收到 scanner 报告后，将 Agent 配置数据分发给两位 auditor，作为审计的参考数据。

Auditor 在审计时必须参考 scanner 结果——例如 scanner 发现的 Agent 权限配置是 auditor-1 审计的基础。

### 步骤 5：独立并行 Agent 审计

两位 auditor 各自审计负责的 OWASP 风险项，**互不交流**。

**Auditor-1（权限边界与数据流维度）** — 对应 AG01 / AG02 / AG03 / AG08 / AG10：

逐风险项输出"合规状态 + 发现 + 证据"：

| 风险项 | 审计内容 | 具体检查项 |
|--------|---------|-----------|
| **AG01 Excessive Agency** | Agent 权限范围 | 文件系统访问范围（全盘 vs 目录限制）、网络访问权限（任意 URL vs 白名单）、代码执行权限（沙箱 vs 无限制）、数据库操作权限（读写 vs 只读）、自主决策边界（哪些操作需人工审批）、工具调用白名单/黑名单 |
| **AG02 Identity & Access** | Agent 身份和认证 | Agent 使用的 API Key/Token 管理方式、Key 轮换策略、多 Agent 间认证机制、Agent 代表用户执行时的权限边界、OAuth scope 最小化 |
| **AG03 Supply Chain** | 工具链安全 | MCP 服务器来源验证（官方 vs 第三方 vs 自定义）、工具/插件代码审计状态、依赖完整性（npm/pip 包的 AI 相关依赖）、Agent 框架版本安全 |
| **AG08 Misalignment** | 行为对齐 | System Prompt 是否明确约束 Agent 行为边界、异常行为检测机制（Agent 执行了不在预期范围内的操作）、目标漂移检测（Agent 偏离原始任务目标） |
| **AG10 Logging & Monitoring** | 日志和监控 | Agent 操作日志（工具调用、文件读写、API 请求）、决策追踪（为什么选择这个工具/这个操作）、LLM 调用日志（输入/输出记录，注意不记录敏感数据）、异常行为告警配置 |

- 记录每个发现：风险项编号 + 文件路径 + 行号 + 合规状态 + 描述 + 证据 + 缓解建议

**Auditor-2（Prompt 安全与输出可信度维度）** — 对应 AG04 / AG05 / AG06 / AG07 / AG09：

逐风险项输出"合规状态 + 发现 + 证据"：

| 风险项 | 审计内容 | 具体检查项 |
|--------|---------|-----------|
| **AG04 Knowledge Poisoning** | 知识库安全 | RAG 数据源可信度验证、知识库更新是否有审核流程、用户提交内容是否进入知识库（UGC 投毒风险）、向量数据库访问控制 |
| **AG05 Memory Threats** | 记忆安全 | 会话上下文隔离（不同用户/会话间信息不泄露）、持久化记忆的访问控制、上下文窗口中的敏感数据处理、记忆清除机制 |
| **AG06 Prompt Injection** | 注入防护 | 直接注入（用户输入中嵌入恶意指令）、间接注入（网页/文档/邮件中嵌入恶意指令被 Agent 读取）、越狱攻击（绕过 System Prompt 约束）、System Prompt 泄露风险、输入净化/过滤机制 |
| **AG07 Hallucination** | 幻觉管理 | LLM 输出是否经过验证再执行（尤其是代码执行/API 调用）、事实核查机制（对关键事实进行验证）、置信度评估（Agent 是否表达不确定性）、回退策略（低置信度时请求人工介入）、人工审核流程 |
| **AG09 DoS / Wallet** | 资源控制 | Token 使用上限（单次调用/单会话/日限额）、并发 Agent 数量限制、递归/循环调用防护（Agent 自我调用的深度限制）、费用告警机制、异常高消耗检测 |

- 记录每个发现：风险项编号 + 文件路径 + 行号 + 合规状态 + 描述 + 证据 + 缓解建议

---

## 阶段二：风险分析

### 步骤 6：启动 analyst

两位 auditor 审计完成后，启动 analyst。Team lead 将以下材料发送给 analyst：
- Scanner Agent 配置扫描报告
- Auditor-1 审计报告
- Auditor-2 审计报告
- OWASP Agentic AI Top 10 风险清单

### 步骤 7：合并去重与 OWASP 映射

Analyst 执行合并分析：

1. **去重**：识别 scanner 结果与 auditor 手工发现的重叠项，合并为单条记录
2. **交叉校验**：检查两位 auditor 是否对同一风险有不同评级
3. **OWASP 映射**：逐项标注每个发现对应的 OWASP Agentic AI Top 10 风险编号
4. **盲区识别**：检查是否有 OWASP Top 10 风险项未被任何发现覆盖，标注为"未审计"
5. **影响评估**：评估每个风险的实际业务影响和攻击可能性

**共识度计算公式**：
```
两位 auditor 审计的风险项有部分交叉（如 AG01 权限过大可能同时涉及 AG06 注入后果放大）。
对于重叠区域的发现：

共识发现数 = 两位 auditor 都识别出的问题数量（指向相同 Agent/配置且描述相同风险类型）
总重叠区域发现数 = 重叠区域去重后的问题总数

共识度 = 共识发现数 / 总重叠区域发现数 × 100%（如无重叠区域发现则为 100%）

评级一致性 = 两位 auditor 对同一问题评级完全一致的比例
争议率 = 评级差异 ≥ 2 级的问题数 / 两位 auditor 都识别的问题数 × 100%

争议率 > 50% → 触发熔断，必须暂停问用户
```

### 步骤 8：差异校验与熔断检查

**差异校验**：
- 如果两位 auditor 对同一风险的评级差异 ≥ 2 级（如一方定"不合规"、另一方定"合规"），analyst 标注为"争议项"
- 争议项占比 > 50% → **不可跳过，必须暂停问用户**（熔断机制）

**高危风险熔断**：
- 统一评估清单中"不合规"风险项超过 8 个 → **不可跳过，必须暂停问用户**（熔断机制）
- 向用户展示"不合规"风险列表，确认是否继续生成完整报告

**无熔断触发**时，analyst 输出**统一风险评估清单**：

```
## 统一风险评估清单

### 风险统计
- 合规: X 个 | 部分合规: X 个 | 不合规: X 个 | 不适用: X 个
- OWASP Top 10 覆盖率: X/10 已审计
- Agent 数量: X | LLM 调用点: X | 工具注册数: X

### 风险项评估

#### AG01 Excessive Agency — 状态：部分合规
  ├─ [不合规] Agent 拥有全盘文件系统访问权限 - .claude/settings.json - 证据 - 来源：auditor-1
  ├─ [合规] 工具调用有白名单限制 - agent.config.ts:23 - 来源：scanner/auditor-1
  └─ 影响评估：Agent 可读取任意敏感文件

#### AG06 Prompt Injection — 状态：不合规
  ├─ [不合规] 用户输入直接拼接到 Prompt 中无过滤 - llm.service.ts:45 - 来源：auditor-2
  └─ ...

### 争议项（如有）
1. Agent:风险点 - auditor-1 评级: X / auditor-2 评级: Y - analyst 最终评级: Z - 理由
```

Analyst 完成后关闭。

### 步骤 9：风险评估评分

Team lead 根据统一风险评估清单计算各风险项评分：

评分规则：
- 基础分 10.0，按发现扣分
- "不合规"发现：每个扣 2.0 分（该风险项最多扣至 0 分）
- "部分合规"发现：每个扣 1.0 分
- "合规"：不扣分
- "不适用"：不扣分，不计入权重

按权重计算总分，输出各风险项和总体治理评分。

---

## 阶段三：报告生成

### 步骤 10：启动 reporter

Team lead 将以下材料发送给 reporter：
- 统一风险评估清单
- 各风险项评分
- Agent 配置扫描数据
- 输出语言（`--lang`）

### 步骤 11：生成治理审计报告

Reporter 生成结构化治理审计报告：

```
## AI/Agent 治理审计报告

### 元信息
- 生成时间：YYYY-MM-DD HH:mm:ss
- 团队名称：team-governance-{YYYYMMDD-HHmmss}
- 执行模式：标准模式 / 单轮确认模式 / 完全自主模式
- 输出语言：zh / en
- 治理框架：OWASP Agentic AI Top 10 / Custom
- 审计范围：agents / llm-usage / data-flow / full
- 审计参数：--scope=[scope 值] --framework=[framework 值]

### 1. 审计概述
- 审计日期：YYYY-MM-DD
- 治理框架：OWASP Agentic AI Top 10
- Agent 架构：[Agent 框架/数量/编排模式]
- LLM Provider：[模型/Provider 清单]
- 工具/MCP 数量：X 个

### 2. 治理评分总览
| 风险项 | 权重 | 评分 | 状态 | 主要风险 |
|--------|------|------|------|---------|
| AG01 Excessive Agency | 15% | X.X/10 | 合规/部分/不合规 | [概述] |
| AG02 Identity & Access | 10% | X.X/10 | ... | [概述] |
| AG03 Supply Chain | 10% | X.X/10 | ... | [概述] |
| AG04 Knowledge Poisoning | 10% | X.X/10 | ... | [概述] |
| AG05 Memory Threats | 10% | X.X/10 | ... | [概述] |
| AG06 Prompt Injection | 15% | X.X/10 | ... | [概述] |
| AG07 Hallucination | 10% | X.X/10 | ... | [概述] |
| AG08 Misalignment | 5% | X.X/10 | ... | [概述] |
| AG09 DoS / Wallet | 10% | X.X/10 | ... | [概述] |
| AG10 Logging & Monitoring | 5% | X.X/10 | ... | [概述] |
| **总分** | **100%** | **X.X/10** | | |

### 3. Agent 清单与权限矩阵
| Agent | 框架 | 工具数 | 文件权限 | 网络权限 | 代码执行 | 数据库 | 人工审批 |
|-------|------|--------|---------|---------|---------|--------|---------|
| agent-1 | Claude SDK | 5 | 目录限制 | 白名单 | 沙箱 | 只读 | 是 |
| agent-2 | LangChain | 8 | 全盘 | 无限制 | 无限制 | 读写 | 否 |

### 4. 风险详情（按合规状态排序）

#### 不合规风险项
| # | 风险项 | 检查点 | 位置 | 风险描述 | 证据引用 | 缓解方案 | 优先级 |
|---|--------|--------|------|---------|---------|---------|--------|
| 1 | AG06 | 输入无过滤 | llm.service.ts:45 | 用户输入直拼 Prompt | E-001 | 输入净化+结构化 Prompt | P0 |

#### 部分合规风险项
...

#### 合规风险项
...

### 5. 数据流安全评估
| 数据类型 | 流经路径 | 安全控制 | 风险 | 建议 |
|---------|---------|---------|------|------|
| 用户 PII | 输入→LLM→输出 | 无脱敏 | AG04/AG05 | 输入脱敏+输出过滤 |
| API Key | 环境变量→Agent | .env 存储 | AG02 | KMS/Vault 管理 |

### 6. 缓解优先级矩阵
| 优先级 | 时间窗口 | 风险数量 | 涉及风险项 |
|--------|---------|---------|-----------|
| P0 - 立即整改 | 24 小时内 | X | AG06, AG01 |
| P1 - 尽快整改 | 1 周内 | X | AG02, AG09 |
| P2 - 计划整改 | 1 个月内 | X | AG07, AG10 |
| P3 - 择机整改 | 下个迭代 | X | AG08 |

### 7. 安全加固路线图
按优先级列出每个风险的具体加固方案：
1. [AG-XX: 风险描述]
   - 当前状态：[描述]
   - 缓解方案：[技术方案]
   - 实施步骤：[具体步骤]
   - 验证方法：[如何验证]
   - 预计工时：[评估]

### 8. 治理建议
- 短期（1-2 周）：[紧急安全加固]
- 中期（1-3 个月）：[Agent 治理框架建设]
- 长期（持续）：[AI 安全文化和持续监控]
```

### 步骤 12：用户确认报告

Team lead 向用户展示治理审计报告摘要：
- 治理评分总览
- Agent 权限矩阵
- 不合规风险统计
- 缓解优先级矩阵

AskUserQuestion 确认：
- 确认报告，保存并结束
- 要求补充审计某个 Agent 或风险维度
- 调整风险评级或缓解优先级

**单轮确认模式**：最终报告必须经用户确认。
**完全自主模式**：自动决策，不询问用户。

Reporter 完成后关闭。

---

## 阶段四：保存报告与清理

### 步骤 13：保存报告

Team lead 按 `--lang` 指定的语言保存最终报告：

1. 将完整治理审计报告保存到项目目录（如 `agent-governance-audit-YYYYMMDD.md`）
2. 保存治理数据到 `~/.gstack/data/{slug}/governance.json`（供跨 skill 消费）：

```json
{
  "framework": "owasp-agentic",
  "scope": "full",
  "date": "YYYY-MM-DD",
  "score": 6.0,
  "agents": {
    "total": 3,
    "compliant": 1,
    "at_risk": 2
  },
  "owasp_top10": {
    "AG01": { "status": "partial", "score": 6.0, "findings": 3 },
    "AG02": { "status": "compliant", "score": 9.0, "findings": 1 },
    "AG03": { "status": "partial", "score": 7.0, "findings": 2 },
    "AG04": { "status": "not_applicable", "score": 10.0, "findings": 0 },
    "AG05": { "status": "partial", "score": 7.5, "findings": 2 },
    "AG06": { "status": "non_compliant", "score": 3.0, "findings": 5 },
    "AG07": { "status": "partial", "score": 6.5, "findings": 3 },
    "AG08": { "status": "compliant", "score": 8.5, "findings": 1 },
    "AG09": { "status": "non_compliant", "score": 4.0, "findings": 4 },
    "AG10": { "status": "partial", "score": 5.0, "findings": 4 }
  },
  "summary": { "compliant": 2, "partial": 5, "non_compliant": 2, "not_applicable": 1 }
}
```

3. 向用户输出报告保存路径和审计总结：

```
## Agent 治理审计完成

### 审计总结
- 治理框架：OWASP Agentic AI Top 10
- 审计范围：[agents/llm-usage/data-flow/full]
- 治理评分：X.X / 10.0
- Agent 数量：X 个（合规 X / 存在风险 X）
- OWASP Top 10 状态：合规 X / 部分合规 X / 不合规 X / 不适用 X
- 报告路径：[文件路径]
- 治理数据：~/.gstack/data/{slug}/governance.json

### 关键风险
1. [最严重风险概述]
2. ...

### 建议下一步
1. 立即处理 P0 级风险（Prompt 注入/权限过大）
2. 本周内完成 P1 级加固
3. 建立 Agent 行为监控和告警
4. 整改完成后重新运行 /team-governance 验证

### 自主决策汇总（单轮确认模式/完全自主模式）
| 决策节点 | 决策内容 | 理由 |
|---------|---------|------|
| [阶段/步骤] | [决策描述] | [理由] |

### 附录：审计共识说明
- auditor-1 发现数：[数量] 个（风险覆盖：AG01/AG02/AG03/AG08/AG10）
- auditor-2 发现数：[数量] 个（风险覆盖：AG04/AG05/AG06/AG07/AG09）
- scanner 发现数：[数量] 个
- 重叠区域共识发现：[数量] 个（共识度 = XX%）
- 评级一致性：XX%
- 争议项：[数量] 个（争议率 = XX%）
  - [Agent:风险点] — auditor-1 评级: X / auditor-2 评级: Y → analyst 最终评级: Z（理由）
- 仅 auditor-1 发现：[列表]
- 仅 auditor-2 发现：[列表]
- 仅 scanner 发现（人工未确认）：[列表]
```

### 步骤 13.5：跨团队衔接建议（可选）

Team lead 根据审计结果向用户建议后续动作：
- **发现权限过大需要加固**：建议运行 `/team-dev` 实施权限收缩和沙箱化
- **发现 Prompt 注入风险**：建议运行 `/team-security` 进行深度安全审计
- **Agent 架构需要重设计**：建议运行 `/team-arch` 评估 Agent 架构改进
- **需要合规验证（如 SOC2 中的 AI 治理）**：建议运行 `/team-compliance` 进行合规审计
- **需要持续监控 Agent 行为**：建议运行 `/team-observability` 设计 Agent 监控告警
- 用户可选择执行或跳过，不强制。

### 步骤 14：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 核心原则

- **双路独立**：权限/数据流审计和 Prompt/输出审计独立进行，互不交流，确保安全覆盖面最大化
- **OWASP 对齐**：以 OWASP Agentic AI Top 10 为基准框架，确保风险覆盖的完整性和行业一致性
- **最小权限**：Agent 应遵循最小权限原则，任何超出必要的权限都视为风险
- **输出不可信**：LLM 输出默认不可信，必须经过验证才能执行（尤其是代码执行、API 调用、数据写入）
- **可操作性**：每个风险必须给出具体缓解方案，可直接实施，避免空泛建议
- **纵深防御**：不依赖单一安全控制，多层防护（输入过滤+Prompt 隔离+输出验证+行为监控）
- **持续治理**：Agent 治理不是一次性活动，需要持续监控和定期审计

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| 项目无 AI/Agent 组件 | Scanner 标注"未发现 AI/Agent 组件"，检查是否有 LLM API 调用（可能是轻量集成而非 Agent） |
| Agent 配置文件加密/不可读 | Scanner 标注"该配置不可访问"，不阻塞流程，auditor 基于代码推断 |
| MCP 服务器配置为外部服务 | Auditor-1 将外部 MCP 服务器标注为"黑盒"，基于接口信息评估风险 |
| 两位 auditor 评级差异过大（争议率 > 50%） | 触发熔断，暂停问用户裁决争议项 |
| 高危风险超过 8 个 | 触发熔断，暂停向用户确认是否继续完整报告 |
| Agent 数量过多（> 20 个） | Analyst 按 Agent 类型分组，优先审计高权限 Agent |
| LLM API Key 在代码中硬编码 | 立即标注为 P0 风险（AG02），不等待后续流程 |
| 自定义 Agent 框架（非主流） | Scanner 基于代码模式识别 Agent 行为，标注"自定义框架，部分检查可能不完整" |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前步骤恢复 |
| Agent 涉及多仓库（微服务架构） | Scanner 标注"仅审计当前仓库"，建议对其他仓库分别运行审计 |

---

## 需求

$ARGUMENTS
