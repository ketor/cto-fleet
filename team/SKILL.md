---
name: team
description: 智能路由——根据任务描述自动选择最合适的 team-* skill 并调用。无需记忆 29 个 skill 名称，只需 /team 你的任务。使用方式：/team [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--lang=zh|en] 任务描述
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--lang=zh|en] 任务描述
---

## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE <old> <new>`: read `~/.claude/skills/cto-fleet/cto-fleet-upgrade/SKILL.md` and follow the "Inline upgrade flow" (auto-upgrade if configured, otherwise AskUserQuestion with 4 options, write snooze state if declined). If `JUST_UPGRADED <from> <to>`: tell user "Running cto-fleet v{to} (just updated!)" and continue.

---

**参数解析**：从 `$ARGUMENTS` 中检测以下标志：
- `--auto`：传递给目标 skill 的完全自主模式标志（不询问用户任何问题）
- `--once`：传递给目标 skill 的单轮确认模式标志（所有问题合并为一轮提问，之后全程自动执行）
- `--lang=zh|en`：传递给目标 skill 的输出语言标志

解析后保留完整的任务描述（含未识别的参数，如 `--focus`、`--depth` 等，一并传递给目标 skill）。

---

## 路由决策流程

```
用户输入 → 提取任务关键词和意图
         → 匹配决策矩阵（按优先级）
         → 单一匹配 → 确认并调用
         → 多个候选 → AskUserQuestion 让用户选择
         → 无匹配   → AskUserQuestion 让用户指定
```

---

## 决策矩阵

按**任务意图**匹配，优先匹配排在前面的规则。当多条规则同时匹配时，选择最具体的那条。支持中英文混合输入。

### 开发与修复

| 意图信号（中/英） | 目标 Skill | 传递参数 |
|---------|-----------|---------|
| "开发""实现""新增功能""添加""创建功能""做一个" / "implement""add feature""build""create" | `/team-dev` | `[--auto] [--once] [--lang]` |
| "重构""迁移""拆分模块""合并模块""重命名""提取接口" / "refactor""migrate""split""merge module""extract interface" | `/team-refactor` | `[--auto] [--once] [--scope=module\|package\|system] [--lang]` |
| "修复 bug""debug""定位问题""排查""为什么报错""崩溃" / "fix bug""debug""troubleshoot""why error""crash" | `/team-debug` | `[--auto] [--once] [--lang]` |

### 审查与分析

| 意图信号（中/英） | 目标 Skill | 传递参数 |
|---------|-----------|---------|
| "review 代码""代码审查""代码质量""review PR" / "code review""review pull request""code quality" | `/team-review` | `[--auto] [--once] [--focus] [--lang]` |
| "分析架构""架构评估""模块关系""依赖分析" / "analyze architecture""architecture review""dependency analysis" | `/team-arch` | `[--auto] [--once] [--depth] [--focus] [--lang]` |
| "性能优化""性能分析""慢""延迟高""OOM""内存泄漏" / "performance""optimize""slow""high latency""memory leak" | `/team-perf` | `[--auto] [--once] [--focus] [--lang]` |
| "安全审计""安全扫描""漏洞""安全检查""渗透""安全隐患" / "security audit""vulnerability""security scan""penetration test" | `/team-security` | `[--auto] [--once] [--scope] [--lang]` |
| "测试策略""测试覆盖率""补测试""flaky test""测试金字塔""缺少测试" / "test strategy""test coverage""missing tests""flaky tests""test pyramid" | `/team-test` | `[--auto] [--once] [--focus=unit\|integration\|e2e\|all] [--fix] [--lang]` |
| "威胁建模""STRIDE""DREAD""攻击面""威胁分析" / "threat model""STRIDE""DREAD""attack surface""threat analysis" | `/team-threat-model` | `[--auto] [--once] [--framework=stride\|dread\|both] [--scope] [--lang]` |
| "无障碍""WCAG""可访问性""accessibility""ARIA""屏幕阅读器" / "accessibility""WCAG""a11y""screen reader""ARIA" | `/team-accessibility` | `[--auto] [--once] [--level=A\|AA\|AAA] [--fix] [--lang]` |
| "契约测试""API 兼容性""breaking change""消费者驱动" / "contract test""API compatibility""breaking change""consumer-driven" | `/team-contract-test` | `[--auto] [--once] [--style=pact\|openapi\|grpc\|auto] [--scope] [--lang]` |

### 设计与方案

| 意图信号（中/英） | 目标 Skill | 传递参数 |
|---------|-----------|---------|
| "写 RFC""技术方案""设计文档""技术设计""写方案" / "write RFC""technical proposal""design doc" | `/team-rfc` | `[--auto] [--once] [--type] [--lang]` |
| "评审方案""评审设计""review RFC""评审文档""评估可行性" / "review proposal""review design""evaluate feasibility" | `/team-design-review` | `[--auto] [--once] [--lang]` |
| "设计 API""API 评审""接口设计""定义接口""重新设计 API" / "design API""API review""define interface""redesign API" | `/team-api-design` | `[--auto] [--once] [--style] [--lang]` |

### 运维与发布

| 意图信号（中/英） | 目标 Skill | 传递参数 |
|---------|-----------|---------|
| "线上故障""生产事故""告警""服务不可用""紧急""生产环境...尽快" / "production outage""alert""service down""urgent""emergency" | `/team-incident` | `[--auto] [--once] [--severity] [--lang]` |
| "复盘""事后分析""postmortem""故障总结""经验教训" / "postmortem""retrospective""lessons learned""incident review" | `/team-postmortem` | `[--auto] [--once] [--lang]` |
| "发布""上线""release""版本""changelog" / "release""deploy""publish version""release notes" | `/team-release` | `[--auto] [--once] [--type] [--from] [--lang]` |
| "监控""可观测性""告警规则""SLO""SLI""dashboard""仪表盘" / "monitoring""observability""alert rules""SLO""SLI""dashboard" | `/team-observability` | `[--auto] [--once] [--stack] [--service] [--lang]` |
| "运维手册""runbook""on-call""值班手册""故障处理手册" / "runbook""on-call""operations manual""playbook" | `/team-runbook` | `[--auto] [--once] [--service] [--lang]` |
| "CI/CD""流水线""pipeline""构建慢""构建失败""GitHub Actions""GitLab CI" / "CI/CD""pipeline""build slow""build failing""GitHub Actions""GitLab CI" | `/team-cicd` | `[--auto] [--once] [--platform] [--fix] [--lang]` |
| "混沌工程""故障注入""韧性测试""chaos""resilience""blast radius" / "chaos engineering""fault injection""resilience testing""chaos""blast radius" | `/team-chaos` | `[--auto] [--once] [--target] [--dry-run] [--lang]` |

### 调研与文档

| 意图信号（中/英） | 目标 Skill | 传递参数 |
|---------|-----------|---------|
| "调研""研究""对比""技术选型""了解""分析趋势" / "research""compare""tech selection""evaluate options" | `/team-research` | `[--auto] [--once] [--depth] [--lang]` |
| "入职文档""知识库""上手指南""项目文档""新人""改进文档""更新文档""完善文档" / "onboarding""knowledge base""getting started""improve docs""update documentation" | `/team-onboard` | `[--auto] [--once] [--target] [--lang]` |
| "成本优化""成本分析""降本""资源利用率""GPU 利用率" / "cost optimization""cost analysis""reduce cost""resource utilization" | `/team-cost` | `[--auto] [--once] [--scope] [--lang]` |
| "供应商评估""工具对比""选型对比""vendor""哪个好" / "vendor evaluation""compare tools""which is better""tool comparison" | `/team-vendor` | `[--auto] [--once] [--candidates] [--usecase] [--lang]` |

### CTO 决策与管理

| 意图信号（中/英） | 目标 Skill | 传递参数 |
|---------|-----------|---------|
| "架构决策""ADR""为什么选了""决策记录""记录这个决定" / "architecture decision""ADR""why did we choose""record this decision" | `/team-adr` | `[--auto] [--once] [--title] [--query] [--lang]` |
| "技术债务""tech debt""代码质量评估""债务清单""哪些代码该重构" / "tech debt""code health""debt inventory""what needs refactoring" | `/team-techdebt` | `[--auto] [--once] [--top] [--module] [--lang]` |
| "周报""月报""汇报""状态报告""给老板看""board报告""投资人报告" / "status report""weekly report""board update""investor update""executive summary" | `/team-report` | `[--auto] [--once] [--mode] [--period] [--lang]` |
| "迁移""升级框架""从X迁到Y""数据库迁移""技术栈迁移" / "migration""migrate from""upgrade framework""database migration""tech stack migration" | `/team-migration` | `[--auto] [--once] [--from] [--to] [--lang]` |
| "合规""审计""SOC2""GDPR""HIPAA""合规检查" / "compliance""audit""SOC2""GDPR""HIPAA""compliance check" | `/team-compliance` | `[--auto] [--once] [--framework] [--lang]` |
| "sprint规划""迭代规划""速率""velocity""下个迭代做什么" / "sprint planning""iteration planning""velocity""what should we work on next" | `/team-sprint` | `[--auto] [--once] [--period] [--team-size] [--lang]` |
| "面试题""技术面试""出题""面试准备""评估标准" / "interview questions""technical interview""generate questions""assessment""hiring" | `/team-interview` | `[--auto] [--once] [--role] [--level] [--count] [--lang]` |
| "团队健康""巴士因子""知识孤岛""人员风险""团队容量" / "team health""bus factor""knowledge silo""team capacity""people risk" | `/team-capacity` | `[--auto] [--once] [--period] [--module] [--lang]` |
| "依赖检查""漏洞扫描""CVE""供应链安全""依赖更新""SBOM" / "dependency check""vulnerability scan""CVE""supply chain""dependency update""SBOM" | `/team-deps` | `[--auto] [--once] [--scope] [--lang]` |
| "晨会简报""CTO简报""技术总览""综合报告""今天关注什么""项目健康" / "morning briefing""CTO briefing""tech overview""what needs attention""project health" | `/team-cto-briefing` | `[--auto] [--once] [--modules] [--skip] [--period] [--lang]` |
| "DORA指标""部署频率""变更前置时间""工程效能""交付效率" / "DORA metrics""deployment frequency""lead time""engineering productivity""delivery efficiency" | `/team-dora` | `[--auto] [--once] [--period] [--compare] [--lang]` |
| "feature flag""功能开关""灰度发布""flag清理""stale flag" / "feature flag""feature toggle""flag cleanup""stale flags""rollout strategy" | `/team-feature-flag` | `[--auto] [--once] [--action=audit\|cleanup\|strategy] [--provider] [--lang]` |
| "数据库设计""schema""表结构""迁移脚本""索引优化""DDL" / "database design""schema""table structure""migration script""index optimization""DDL" | `/team-schema` | `[--auto] [--once] [--db] [--action=design\|migrate\|audit\|optimize] [--lang]` |
| "国际化""i18n""本地化""多语言""hardcoded string""RTL" / "internationalization""i18n""localization""multi-language""hardcoded strings""RTL" | `/team-i18n` | `[--auto] [--once] [--target-locales] [--fix] [--lang]` |
| "Agent 治理""AI 安全""prompt 注入""权限边界""OWASP Agentic" / "agent governance""AI safety""prompt injection""permission boundary""OWASP agentic" | `/team-governance` | `[--auto] [--once] [--scope] [--framework] [--lang]` |

---

## 路由执行步骤

### 步骤 1：意图识别

分析 `$ARGUMENTS` 中的任务描述，提取：
1. **动作动词**：开发/修复/审查/设计/发布/调研/优化/...
2. **对象名词**：代码/架构/API/安全/性能/成本/...
3. **紧急程度**：是否包含"紧急""线上""生产"等关键词
4. **是否指定了目标 skill**：如果用户已经写了 `team-xxx`，直接转发

### 步骤 2：匹配决策

按以下优先级匹配：

1. **精确匹配**：任务描述中直接包含 skill 名称（如"用 team-perf 分析性能"）→ 直接调用
2. **紧急优先**：包含紧急信号 → 优先匹配 `/team-incident`
   - 强信号（直接路由）："紧急""线上故障""告警""服务不可用""production outage""urgent"
   - 弱信号（需组合判断）："生产环境""尽快""ASAP" — 单独出现不足以触发，但两个弱信号组合 或 弱信号+问题描述（如"CPU跑满""挂了"）= 路由到 incident
   - 例外：如果任务明确是**过去时态**（"昨天的故障""上周的事故"），即使包含紧急信号，也路由到 `/team-postmortem`
3. **意图匹配**：按决策矩阵匹配最具体的规则。当对象名词比动作动词更具体时，以对象名词为准（如"review 安全隐患"→ team-security，因为"安全隐患"比"review"更具体）
4. **多意图处理**：
   - **顺序型**（"先...然后..."）：选第一个意图，完成后建议下一个
   - **并列型**（"A也差，B也有问题"）：3个以上并列意图 → 降为中等置信度，用 AskUserQuestion 让用户选择优先处理哪个
   - **主次型**（一个明显核心诉求+附带提及）：选核心意图

### 步骤 3：确认与调用

**单一匹配**（置信度高）：
- 向用户简要说明匹配结果：`"根据任务描述，我将使用 /team-xxx 来处理。"`
- 用 AskUserQuestion 确认（提供匹配的 skill 和 2 个最近的候选）
- 确认后，使用 **Skill 工具** 调用目标 skill，将完整参数传递

**多个候选**（置信度中等）：
- 列出 2-3 个候选 skill 及匹配理由
- 用 AskUserQuestion 让用户选择
- 确认后调用

**无匹配**（置信度低）：
- 展示全部 29 个 skill 的简表
- 用 AskUserQuestion 让用户选择

### 步骤 4：调用目标 Skill

使用 Skill 工具调用选中的 team-* skill：
- 将 `--auto`（如有）传递
- 将 `--once`（如有）传递
- 将 `--lang`（如有）传递
- 将其余参数和任务描述作为 args 传递
- 如果用户提供了目标 skill 特有的参数（如 `--depth`、`--focus`、`--scope`），一并传递

---

## Skill 速查表

路由无法匹配时展示此表：

| Skill | 一句话描述 | 中文示例 | English Example |
|-------|-----------|---------|----------------|
| `/team-dev` | 完整研发流程 | "帮我实现用户登录功能" | "implement user login" |
| `/team-debug` | 系统化 Bug 诊断 | "这个接口偶尔返回 500" | "debug intermittent 500 errors" |
| `/team-perf` | 性能剖析优化 | "列表页加载太慢了" | "optimize slow page load" |
| `/team-security` | 安全审计 | "检查一下项目的安全性" | "security audit this project" |
| `/team-review` | 代码审查 | "review 代码质量" | "review code quality" |
| `/team-arch` | 架构分析 | "分析一下项目的架构" | "analyze the architecture" |
| `/team-rfc` | 技术方案撰写 | "写一个缓存方案的 RFC" | "write RFC for caching" |
| `/team-design-review` | 方案评审 | "评审一下这个设计文档" | "review this design doc" |
| `/team-api-design` | API 设计 | "设计用户管理的 API" | "design user management API" |
| `/team-incident` | 故障响应 | "线上订单服务挂了" | "production order service is down" |
| `/team-postmortem` | 复盘分析 | "复盘一下昨天的故障" | "postmortem on yesterday's outage" |
| `/team-release` | 发布管理 | "准备发布 v2.1.0" | "prepare release v2.1.0" |
| `/team-refactor` | 重构工程 | "把这个模块拆成微服务" | "split this into microservices" |
| `/team-research` | 技术调研 | "调研 Rust vs Go 的选型" | "research Rust vs Go" |
| `/team-onboard` | 知识库构建 | "生成项目入职文档" | "generate onboarding docs" |
| `/team-cost` | 成本优化 | "分析 GPU 集群使用效率" | "analyze GPU cluster cost" |
| `/team-adr` | 架构决策记录 | "记录为什么选了 PostgreSQL" | "record why we chose PostgreSQL" |
| `/team-techdebt` | 技术债务清单 | "哪些代码最该重构" | "where is our tech debt" |
| `/team-report` | 管理报告生成 | "生成本周的 board 报告" | "generate weekly board report" |
| `/team-migration` | 迁移规划 | "从 Express 迁到 Fastify" | "plan migration from Express to Fastify" |
| `/team-compliance` | 合规审计 | "SOC2 审计准备" | "SOC2 audit readiness" |
| `/team-sprint` | Sprint 规划 | "规划下个迭代" | "plan next sprint" |
| `/team-interview` | 面试题生成 | "出一套后端面试题" | "generate backend interview questions" |
| `/team-capacity` | 团队健康分析 | "看看团队的巴士因子" | "check team bus factor" |
| `/team-deps` | 依赖健康检查 | "扫描依赖漏洞" | "scan for dependency vulnerabilities" |
| `/team-vendor` | 供应商评估 | "对比 Redis vs Memcached" | "compare Redis vs Memcached" |
| `/team-observability` | 可观测性设计 | "设置监控和告警" | "set up monitoring and alerts" |
| `/team-runbook` | 运维手册生成 | "写 on-call 手册" | "generate on-call runbooks" |
| `/team-cto-briefing` | CTO 晨会简报 | "给我一份晨会简报" | "morning briefing" |

---

## 组合任务处理

当任务描述包含多个阶段时，路由建议分步执行：

| 组合模式 | 推荐顺序 |
|---------|---------|
| "开发 + 审查" | `/team-dev` → `/team-review` |
| "设计 + 开发" | `/team-rfc` → `/team-dev` |
| "故障 + 复盘" | `/team-incident` → `/team-postmortem` |
| "审计 + 修复" | `/team-security` → `/team-dev` |
| "架构分析 + 重构" | `/team-arch` → `/team-refactor` |
| "调研 + 方案" | `/team-research` → `/team-rfc` |
| "开发 + 发布" | `/team-dev` → `/team-release` |
| "性能分析 + 优化代码" | `/team-perf`（内含优化实施） |
| "审查 + 安全 + 性能" | AskUserQuestion 让用户选优先级 |
| "API设计 + 开发实现" | `/team-api-design` → `/team-dev` |
| "安全审计 + 性能优化" | `/team-security` → `/team-perf` |
| "技术债务 + Sprint规划" | `/team-techdebt` → `/team-sprint` |
| "依赖检查 + 合规审计" | `/team-deps` → `/team-compliance` |
| "监控设计 + 运维手册" | `/team-observability` → `/team-runbook` |
| "故障响应 + 运维手册更新" | `/team-incident` → `/team-runbook --update` |
| "架构决策 + 迁移规划" | `/team-adr` → `/team-migration` |
| "供应商评估 + 架构决策" | `/team-vendor` → `/team-adr` |
| "团队健康 + Sprint规划" | `/team-capacity` → `/team-sprint` |
| "技术债务 + 汇报" | `/team-techdebt` → `/team-report` |

路由只执行第一个 skill。第一个 skill 完成后，其跨团队衔接建议会自然引导到下一个。

---

## 核心原则

- **零记忆负担**：用户不需要记住 28 个 skill 名称，自然语言描述任务即可
- **保守路由**：不确定时宁可多问一次，不误导到错误的 skill
- **紧急优先**：包含紧急信号的任务优先匹配 `/team-incident`
- **参数透传**：所有用户指定的参数完整传递给目标 skill，不丢失
- **单一职责**：路由只做选择和转发，不做任何实际工作

---

## 需求

$ARGUMENTS
