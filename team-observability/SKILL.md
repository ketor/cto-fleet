---
name: team-observability
description: 启动一个可观测性设计团队（topology-scanner/designer×2/implementer），通过服务拓扑发现+双路独立设计（SLI/SLO+告警规则）+配置生成，输出可直接部署的监控配置。V1默认Prometheus，其他监控栈尽力支持。使用方式：/team-observability [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--stack=prometheus|datadog|cloudwatch] [--service=服务名] 项目路径或描述
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--stack=prometheus|datadog|cloudwatch] [--service=服务名] 项目路径或描述
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
- `--stack=prometheus|datadog|cloudwatch`：目标监控栈（默认 `prometheus`）
- `--service=服务名`：聚焦特定服务（可选，默认全量扫描）

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 拓扑确认 + 设计分歧仲裁 + 最终配置确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅最终配置确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下条件节点自动决策规则：
- **SLO 阈值不确定** → team lead 根据行业惯例自行判断，在最终配置中说明
- **两位 designer 分歧** → team lead 标注分歧，综合论证后裁决，收尾时汇总
- **分歧超过 50%** → **不可跳过，必须暂停问用户**（熔断机制）
- **交叉验证异议超过 3 项** → **不可跳过，必须暂停问用户**（熔断机制）
- **服务拓扑过大无法完整覆盖** → topology-scanner 识别核心服务链路，designer 聚焦核心链路
- **`--service` 参数处理**：如果用户指定了 `--service`，topology-scanner 和 designer 优先分析指定服务及其上下游，其余服务仅概览级别

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效（分歧超过 50%、交叉验证异议超过 3 项时仍必须暂停问用户）。

监控栈支持说明：

| 栈 | 支持级别 | 说明 |
|------|---------|------|
| `prometheus` | 完整支持 | 原生 YAML 配置生成（Prometheus rules + Alertmanager + Grafana dashboards） |
| `datadog` | 尽力支持 | SLI/SLO 定义和告警逻辑栈无关；配置格式为 Datadog Monitor JSON，best-effort |
| `cloudwatch` | 尽力支持 | SLI/SLO 定义和告警逻辑栈无关；配置格式为 CloudWatch Alarm JSON/CloudFormation，best-effort |

使用 TeamCreate 创建 team（名称格式 `team-observability-{YYYYMMDD-HHmmss}`，如 `team-observability-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

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
阶段零  服务拓扑发现 → topology-scanner 扫描服务结构 + 端点 + 依赖关系 → 输出服务拓扑图
         ↓
阶段一  并行设计 → designer-1 定义 SLI/SLO + designer-2 设计告警规则
         ↓
阶段二  共识合并 → team lead 对比两份设计 → 输出：共识/分歧/盲区清单 → 检查熔断
         ↓
阶段三  配置生成 → implementer 根据选定栈生成部署就绪配置文件
         ↓
阶段四  健康检查端点生成 → implementer 生成 readiness/liveness 探针实现
         ↓
阶段五  收尾 → 保存配置 + 输出跨技能数据 + 清理团队
```

## 角色定义

| 角色 | 职责 |
|------|------|
| topology-scanner | 扫描代码库发现服务拓扑：HTTP 端点、消息队列、数据库连接、外部 API 调用、后台任务。构建服务依赖图。**只做拓扑层面发现，不做监控设计。** |
| designer-1 | 根据服务拓扑为每个服务定义 SLI/SLO：延迟（p50/p95/p99）、错误率、吞吐量、饱和度。**独立设计阶段不与 designer-2 交流。** |
| designer-2 | 根据服务拓扑设计告警规则：阈值定义、升级路径、静默窗口、告警分组策略。**独立设计阶段不与 designer-1 交流。** |
| implementer | 根据合并后的设计方案和选定监控栈，生成部署就绪配置文件（Prometheus rules YAML、Grafana dashboard JSON、Alertmanager 配置等）。生成健康检查端点。**不做设计决策，严格按合并方案执行。** |

---

## 阶段零：服务拓扑发现

### 步骤 1：启动 topology-scanner

Team lead 启动 topology-scanner，指示其扫描以下内容：
- HTTP/gRPC 端点定义（路由、handler、中间件）
- 消息队列生产者/消费者（Kafka、RabbitMQ、Redis Pub/Sub、NATS 等）
- 数据库连接和查询模式（SQL、NoSQL、缓存层）
- 外部 API 调用（第三方服务、内部微服务间调用）
- 后台任务/定时任务（cron、worker、scheduler）
- 服务间通信模式（同步 REST/gRPC、异步消息、事件驱动）

### 步骤 2：构建服务拓扑

Topology-scanner 根据扫描结果构建服务拓扑，输出**服务拓扑报告**，包含：

| 分析类别 | 输出内容 |
|---------|---------|
| 服务清单 | 每个服务的名称、类型（API/Worker/Gateway 等）、技术栈 |
| 端点清单 | HTTP/gRPC 端点列表（路径、方法、handler） |
| 依赖关系 | 服务间调用关系、数据库依赖、外部依赖 |
| 消息流 | 消息队列主题/队列、生产者/消费者映射 |
| 数据存储 | 使用的数据库/缓存及其访问模式 |
| 后台任务 | 定时任务列表、执行频率、资源需求 |
| 关键链路 | 用户请求的核心调用链路（入口 → 处理 → 响应） |

### 步骤 3：评估覆盖范围

Team lead 根据 topology-scanner 报告评估：
- 如果用户指定了 `--service`，确认目标服务及其上下游是否已完整识别
- 如果未指定：
  - 小型项目（<5 个服务/端点组）→ 全量覆盖
  - 中型项目（5-20 个服务/端点组）→ 全量覆盖
  - 大型项目（>20 个服务/端点组）→ 聚焦核心链路，其余概览级别

**标准模式**：向用户展示服务拓扑 + 覆盖范围建议，AskUserQuestion 确认
**单轮确认模式**：team lead 自行决定，收尾汇总时说明
**完全自主模式**：自动决策，不询问用户

---

## 阶段一：并行设计

### 步骤 4：启动 designer-1 和 designer-2

两者并行启动，全程保持存活直到收尾。

Team lead 将 topology-scanner 的服务拓扑报告分发给两位 designer，作为设计的输入基础。

**Designer-1 SLI/SLO 设计**：

针对每个服务/端点，定义以下指标：

1. **延迟 SLI**：请求延迟分布（p50/p95/p99），区分读/写操作
2. **错误率 SLI**：HTTP 5xx 比例、gRPC 错误码比例、业务错误率
3. **吞吐量 SLI**：每秒请求数（RPS）、消息处理速率
4. **饱和度 SLI**：CPU/内存/连接池使用率、队列深度
5. **SLO 目标值**：每个 SLI 对应的目标值（如 p99 延迟 < 500ms，可用性 > 99.9%）
6. **错误预算**：基于 SLO 计算的错误预算及消耗速率告警

Designer-1 输出结构化 SLI/SLO 设计报告。

**Designer-2 告警规则设计**：

针对每个服务/端点，设计以下告警：

1. **告警规则**：告警条件表达式、持续时间窗口、严重级别（critical/warning/info）
2. **阈值定义**：静态阈值 + 动态基线（如适用），区分业务高峰/低谷
3. **升级路径**：告警触发后的通知路径（即时通知 → 值班升级 → 管理层升级）
4. **静默窗口**：维护窗口、已知部署期间的告警静默策略
5. **告警分组**：按服务/严重级别/类型分组，避免告警风暴
6. **自动恢复检测**：告警恢复条件和恢复通知策略

Designer-2 输出结构化告警规则设计报告。

### 步骤 5：收集报告

两者完成后各自向 team lead 发送报告。Team lead 确认收到全部 2 份报告后，进入阶段二。

---

## 阶段二：共识合并

### 步骤 6：Team lead 对比分析

Team lead 对比两份设计报告，逐项分析：

| 对比结果 | 处理方式 |
|---------|---------|
| **一致结论**（两位 designer 对同一服务的监控策略一致） | 直接采纳，标记为"共识" |
| **互补发现**（designer-1 的 SLI 指标与 designer-2 的告警规则天然互补） | 合并，标记为"互补" |
| **阈值/参数差异**（对同一指标的阈值或窗口有不同建议） | 标注为"待仲裁"，记录双方建议 |
| **设计冲突**（告警规则与 SLO 目标矛盾，或告警策略不兼容） | 标注为"待仲裁"，记录冲突点 |

Team lead 输出：
1. **共识清单**：双方一致的监控策略
2. **互补清单**：SLI/SLO 与告警规则的互补整合点
3. **分歧清单**：阈值差异、策略冲突及双方建议对比
4. **盲区清单**：两人都未覆盖的服务或监控维度（对照 topology-scanner 的服务清单检查遗漏）
5. **共识度评估**：共识度 = (共识发现数 + 互补发现数) / 总发现数(去重并集) * 100%

### 步骤 7：检查熔断条件

如果共识度 < 50%（分歧占比超过一半）：
- **必须暂停**，team lead 向用户报告情况
- 可能原因：服务过多导致两位 designer 设计了不同侧重点、需求描述不够明确
- 建议：调整监控范围或聚焦核心服务

共识度 >= 50%：继续下一阶段。

### 步骤 8：处理盲区

如果盲区清单非空：
- Team lead 将盲区清单分配给两位 designer，要求补充设计遗漏的服务/监控维度
- Designer 补充后将补充报告发送给 team lead
- Team lead 将补充发现整合到已有分析中

如果盲区清单为空：直接进入下一步。

### 步骤 9：分歧仲裁

如果分歧清单为空 → 跳过仲裁，直接进入阶段三。

Team lead 对分歧清单中的每个分歧点：

1. 将分歧描述分别发给 designer-1 和 designer-2，要求各自提供论证：
   - 你的设计建议是什么？
   - 依据是什么（行业标准、服务特性、历史经验）？
   - 为什么你认为对方的建议不够合理？

2. 收到双方论证后：
   - **标准模式**：team lead 向用户展示分歧摘要和双方论证，AskUserQuestion 让用户裁决
   - **单轮确认模式/完全自主模式**：team lead 综合双方论证和行业惯例自行裁决

3. 将仲裁结果更新到合并设计方案中，将所有"待仲裁"项替换为最终结论。输出**最终合并设计方案**。

---

## 阶段三：配置生成

### 步骤 10：启动 implementer 生成配置文件

Team lead 启动 implementer，将以下内容传递：
- Topology-scanner 的服务拓扑报告
- 最终合并设计方案（含 SLI/SLO 定义 + 告警规则）
- 仲裁结果（如有）
- `--stack` 参数

Implementer 根据选定监控栈生成部署就绪配置文件。

**Prometheus 栈（完整支持）**：

```
monitoring/
├── prometheus-rules.yml          # Prometheus 告警/录制规则
├── alertmanager.yml              # Alertmanager 告警路由配置
├── grafana-dashboards/
│   ├── overview.json             # 全局服务概览 dashboard
│   ├── {service-name}.json       # 每个服务的详细 dashboard
│   └── slo-tracking.json         # SLO 追踪 dashboard
└── prometheus-config-snippet.yml # Prometheus scrape 配置片段（参考用）
```

**Datadog 栈（尽力支持）**：

```
monitoring/
├── datadog-monitors.json         # Datadog Monitor 定义
├── datadog-dashboards.json       # Datadog Dashboard 定义
└── datadog-slo.json              # Datadog SLO 定义
```

**CloudWatch 栈（尽力支持）**：

```
monitoring/
├── cloudwatch-alarms.json        # CloudWatch Alarm 定义
├── cloudwatch-dashboards.json    # CloudWatch Dashboard 定义
└── cloudformation-monitoring.yml # CloudFormation 模板（可选）
```

### 步骤 11：配置文件验证

Implementer 对生成的配置文件进行基本验证：
- YAML 语法校验（`prometheus-rules.yml`、`alertmanager.yml`）
- JSON 语法校验（Grafana dashboard JSON）
- PromQL 表达式基本语法检查（如适用）
- 告警规则引用的指标名称与 SLI 定义一致性检查

如果验证发现问题，implementer 自行修复后重新输出。

---

## 阶段四：健康检查端点生成

### 步骤 12：Implementer 生成健康检查

Implementer 根据服务拓扑报告，为每个服务生成健康检查端点实现：

```
monitoring/
└── health-checks/
    ├── readiness.go/py/ts/...    # 就绪探针（检查依赖连接）
    ├── liveness.go/py/ts/...     # 存活探针（检查进程健康）
    └── README.md                 # 集成说明
```

健康检查实现内容：
- **Readiness 探针**：检查数据库连接、消息队列连接、外部依赖可达性
- **Liveness 探针**：检查进程存活、关键 goroutine/线程状态、死锁检测
- 探针实现语言与项目技术栈一致
- 包含 Kubernetes Deployment YAML 片段示例（探针配置）

### 步骤 13：用户确认

Team lead 向用户展示配置摘要：
- 监控栈：选定的栈
- 覆盖服务数量和核心服务列表
- SLI/SLO 概要（每个服务的关键 SLO 目标）
- 告警规则数量和严重级别分布
- 生成的配置文件清单
- 健康检查端点清单
- 共识度和分歧处理情况

AskUserQuestion 确认：
- 接受配置
- 需要调整某些阈值或告警规则
- 需要补充某些服务的监控

**单轮确认模式**：必须经用户确认。
**完全自主模式**：自动决策，不询问用户。

---

## 阶段五：收尾

### 步骤 14：保存配置文件

将所有生成的配置文件保存到项目的 `monitoring/` 目录：
- 如果目录不存在，创建之
- 保留已有配置文件（不覆盖），新文件使用时间戳后缀避免冲突

### 步骤 15：生成跨技能数据

将可观测性设计摘要保存到 `~/.gstack/data/{slug}/observability.json`，供其他技能消费：

```json
{
  "generated_at": "YYYY-MM-DDTHH:mm:ssZ",
  "stack": "prometheus|datadog|cloudwatch",
  "services": [
    {
      "name": "服务名",
      "type": "API|Worker|Gateway",
      "slos": [
        { "metric": "latency_p99", "target": "500ms", "error_budget": "0.1%" }
      ],
      "alerts": [
        { "name": "告警名", "severity": "critical|warning|info", "condition": "表达式" }
      ],
      "health_checks": ["readiness", "liveness"]
    }
  ],
  "config_files": ["monitoring/prometheus-rules.yml", "..."]
}
```

### 步骤 16：生成 Runbook 存根

在 `docs/runbooks/` 目录下为每条告警规则生成基础 Runbook 模板：

```markdown
# [告警名称] Runbook

## 告警描述
[告警触发条件和含义]

## 影响范围
[受影响的服务和用户影响]

## 诊断步骤
1. [ ] 检查 [指标/日志/仪表盘]
2. [ ] 确认 [根因类别]

## 缓解措施
1. [ ] [临时缓解方案]
2. [ ] [根本修复方案]

## 升级路径
- 15 分钟未恢复 → [升级对象]
- 30 分钟未恢复 → [管理层升级]

> 此 Runbook 为自动生成的存根，建议由 /team-runbook 进一步充实。
```

### 步骤 17：最终总结

Team lead 向用户输出：
- 分析了什么（项目名称、服务拓扑概要、监控栈）
- 核心产出（SLI/SLO 数量、告警规则数量、Dashboard 数量、健康检查数量）
- 关键 SLO 目标摘要
- 共识度和分歧处理情况
- 配置文件保存位置
- 跨技能数据输出位置
- Runbook 存根位置
- **（单轮确认模式/完全自主模式）自动决策汇总**：列出所有自动决策的节点、决策内容和理由

### 步骤 18：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 核心原则

- **拓扑先行**：topology-scanner 先发现服务拓扑，为 designer 提供完整的服务地图
- **独立设计**：两位 designer 必须完全独立工作，不互相看到对方结果，确保设计的多样性和互补性
- **职责分离**：designer 只做设计，implementer 只做配置生成，不交叉职责
- **SLO 驱动**：以 SLI/SLO 为核心，告警规则围绕 SLO 目标设计，避免无意义告警
- **可部署优先**：输出的配置文件必须语法正确、可直接部署，不是伪代码
- **并行高效**：两位 designer 并行工作，最大化效率
- **栈适配**：Prometheus 完整支持，其他栈尽力适配核心逻辑
- **跨技能协作**：输出标准化 JSON 供 /team-runbook 等其他技能消费

---

### 共识度计算

team lead 按五维度评估双路分析的共识度：

| 维度 | 权重 |
|------|------|
| 设计方案一致性（相同问题/结论） | 20% |
| 互补性（独有但不矛盾的设计方案） | 20% |
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
| 项目无法识别服务拓扑 | Topology-scanner 输出代码结构和文件类型统计，designer 基于代码内容推断监控目标 |
| 服务过多无法完整覆盖 | Topology-scanner 识别核心链路，designer 聚焦核心服务设计，配置说明覆盖范围限制 |
| 不支持的监控栈 | 回退到 Prometheus 栈，同时输出栈无关的 SLI/SLO 定义供用户手动适配 |
| 两位 designer 设计差异极大（共识度 < 50%） | 触发熔断，暂停问用户确认设计方向 |
| 交叉验证异议 >= 3 项 | 触发熔断，暂停问用户确认是否存在系统性设计偏差 |
| 无法生成有效 PromQL 表达式 | Implementer 标注为"需手动调整"，附上表达式意图说明 |
| 服务缺少指标暴露点 | 在配置中标注"需添加 metrics endpoint"，健康检查中包含基础指标暴露建议 |
| 项目缺少 README/文档 | Topology-scanner 基于代码结构和框架约定推断服务信息 |
| 盲区清单非空 | Designer 补充设计遗漏服务后 team lead 更新合并结果 |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前阶段恢复。如果是 designer 崩溃，检查已发送的部分报告决定是否需要重新设计。 |

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

