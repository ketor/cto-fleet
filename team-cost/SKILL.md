---
name: team-cost
description: 启动一个成本优化分析团队（scanner/analyzer×2/analyst/reporter），通过基础设施扫描+双路独立分析（infra+code）+合并量化+ROI 评估，输出结构化成本优化报告和实施路线图。使用方式：/team-cost [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--scope=infra|code|full] [--lang=zh|en] 成本优化目标或项目路径
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--scope=infra|code|full] [--lang=zh|en] 成本优化目标或项目路径
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
- `--scope=infra|code|full`：分析范围（默认 `full`）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后将标志从成本优化目标或项目路径中移除。

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 范围确认 + 分歧仲裁 + 最终报告确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅最终报告确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下条件节点自动决策规则：
- **分析范围不确定** → team lead 根据项目配置文件自行判断，在最终报告中说明
- **两位 analyzer 分歧** → analyst 标注分歧，team lead 综合论证后裁决，收尾时汇总
- **分歧超过 50%** → **不可跳过，必须暂停问用户**（熔断机制，单轮确认模式和完全自主模式均适用）
- **项目过大无法完整分析** → scanner 识别核心资源和高成本模块，analyzer 聚焦高成本区域
- **`--scope` 参数处理**：
  - `infra`：仅启动 analyzer-1（基础设施分析），跳过 analyzer-2
  - `code`：仅启动 analyzer-2（代码/应用分析），跳过 analyzer-1
  - `full`：两路分析均启动

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效——触发熔断条件时是唯一会暂停询问用户的情况。

成本优化分类：

| 类别 | 范围 | 示例 |
|------|------|------|
| 计算资源 | infra | GPU/CPU 实例超配、未使用的预留实例、可降级的实例类型 |
| 存储 | infra | 过期数据未清理、存储类型不匹配（SSD vs HDD）、未压缩 |
| 网络 | infra | 跨区域流量、CDN 未启用、API 调用冗余 |
| 数据库 | both | 慢查询、索引缺失、连接池配置、读写分离 |
| 缓存 | code | 缓存命中率低、缓存穿透、无缓存的热点查询 |
| 算法 | code | O(n^2) 可优化为 O(n log n)、重复计算、批处理化 |
| CI/CD | infra | 构建时间过长、测试并行度不足、镜像过大 |
| GPU 利用率 | infra | GPU 空闲率高、batch size 不合理、显存利用不足 |

ROI 评分标准：

| ROI 等级 | 比率 | 优先级 |
|---------|------|--------|
| 高 ROI | 投入小，节省大 (>5x) | P0 - 立即执行 |
| 中 ROI | 投入与节省相当 (2-5x) | P1 - 计划执行 |
| 低 ROI | 投入较大，节省有限 (1-2x) | P2 - 有余力时 |
| 负 ROI | 投入大于预期节省 (<1x) | 不建议 |

使用 TeamCreate 创建 team（名称格式 `team-cost-{YYYYMMDD-HHmmss}`，如 `team-cost-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

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
阶段零  范围确定 → 解析 scope，识别配置文件和代码入口 → 输出分析范围
         ↓
阶段一  扫描 + 双路分析（并行）→ scanner 扫描资源配置 + analyzer-1 基础设施分析 + analyzer-2 代码/应用分析
         ↓
阶段二  合并分析 → analyst 合并去重 + ROI 量化 + 优先级排序 → 检查熔断
         ↓
阶段三  报告生成 → reporter 生成成本优化报告 + 实施路线图 → 用户确认
         ↓
阶段四  收尾 → 保存报告 + 清理团队

scope=infra 流程：阶段零 → 阶段一（仅 scanner + analyzer-1）→ 阶段二 → 阶段三 → 阶段四
scope=code 流程：阶段零 → 阶段一（仅 scanner + analyzer-2）→ 阶段二 → 阶段三 → 阶段四
```

## 角色定义

| 角色 | 职责 |
|------|------|
| scanner | 扫描基础设施配置（Terraform/K8s manifests/Docker configs/CI configs）和代码中的资源使用模式。识别配置文件、资源定义、环境变量中的规格参数。输出资源清单和使用模式报告。**只做扫描和数据采集，不做成本评估。** **阶段一扫描完成后关闭。** |
| analyzer-1 | 基础设施层面成本分析：资源规格合理性、利用率评估、预留实例策略、存储策略、网络成本、GPU 利用率、CI/CD 效率。**独立分析阶段不与 analyzer-2 交流。** **阶段二仲裁完成后关闭（步骤 10 完成后）。** |
| analyzer-2 | 代码/应用层面成本分析：算法效率、缓存策略、数据库查询优化、API 调用模式、资源泄漏、批处理机会。**独立分析阶段不与 analyzer-1 交流。** **阶段二仲裁完成后关闭（步骤 10 完成后）。** |
| analyst | 合并两位 analyzer 的分析报告，去重、分组、量化每项优化的 ROI（投入成本 vs 预期节省），按 ROI 排序输出优化清单。**只做合并和量化，不直接阅读代码或配置，不生成最终报告。** 根本性矛盾必须标注为"待仲裁"升级 team lead。**阶段二完成后关闭（步骤 11 完成后）。** |
| reporter | 基于 analyst 的合并分析和 scanner 的资源清单，生成最终成本优化报告，包含优化建议、ROI 评估、实施路线图。**不做分析判断，不直接阅读代码或配置。** **阶段三完成后关闭。** |

---

## 阶段零：范围确定

### 步骤 1：解析分析范围

Team lead 解析 `$ARGUMENTS`，确定：
- `--scope` 值（默认 `full`）
- 项目路径或目标描述
- 项目类型识别（智算云平台/AI 训练/模型推理/通用云服务）

### 步骤 2：识别配置文件和代码入口

Team lead 快速扫描项目目录，识别以下文件：

| 类别 | 文件类型 |
|------|---------|
| 基础设施定义 | `*.tf`、`*.tfvars`、`pulumi.*`、CloudFormation 模板 |
| 容器/编排 | `Dockerfile*`、`docker-compose*.yml`、`k8s/`、`helm/`、`*.yaml`（K8s manifests） |
| CI/CD | `.github/workflows/`、`.gitlab-ci.yml`、`Jenkinsfile`、`.circleci/` |
| 云服务配置 | 云厂商 SDK 配置、环境变量文件（`.env*`）、配置中心文件 |
| 数据库 | 迁移文件、Schema 定义、ORM 配置 |
| 缓存 | Redis/Memcached 配置、缓存相关代码 |
| AI/GPU | 训练脚本、模型配置、GPU 调度配置、batch size 参数 |

### 步骤 3：确认分析范围

**标准模式**：向用户展示识别到的配置文件和分析范围，AskUserQuestion 确认
**单轮确认模式**：team lead 自行决定，收尾汇总时说明
**完全自主模式**：自动决策，不询问用户

---

## 阶段一：扫描 + 双路分析（并行）

### 步骤 4：启动 scanner

Team lead 启动 scanner，指示其扫描以下内容。**具体操作方法**：

**基础设施资源清单**：
- **Terraform 配置**：`Glob("**/*.tf", "**/*.tfvars")` → 提取 `resource` 块中的实例类型、规格、数量
  - `Grep("instance_type|machine_type|vm_size|gpu_type|accelerator_type", glob="*.tf")` 提取计算规格
  - `Grep("disk_size|volume_size|storage_gb|size_gb", glob="*.tf")` 提取存储容量
- **Kubernetes 配置**：`Glob("**/k8s/**/*.yaml", "**/k8s/**/*.yml", "**/manifests/**/*.yaml", "**/helm/**/*.yaml")`
  - `Grep("resources:|requests:|limits:|cpu:|memory:|nvidia.com/gpu", glob="*.yaml")` 提取 Pod 资源配置
  - `Grep("replicas:|minReplicas:|maxReplicas:|HorizontalPodAutoscaler", glob="*.yaml")` 提取扩缩容配置
- **Docker 配置**：`Glob("**/Dockerfile*", "**/docker-compose*.yml")`
  - `Grep("FROM |COPY |RUN |--cpus|--memory|--gpus", glob="Dockerfile*")` 分析镜像大小因素
- **CI/CD 配置**：`Glob("**/.github/workflows/*.yml", "**/.gitlab-ci.yml", "**/Jenkinsfile")`
  - `Grep("runs-on|image:|runner|cache:|artifacts:", glob="*.yml")` 提取构建资源配置
- **云服务配置**：`Glob("**/.env*", "**/config/**/*.yaml", "**/config/**/*.json")`
  - `Grep("REGION|ZONE|INSTANCE|ENDPOINT|API_KEY|BUCKET|DATABASE_URL", glob=".env*")` 识别云服务参数
- **GPU/AI 配置**：`Glob("**/slurm*", "**/training*.yaml", "**/inference*.yaml")`
  - `Grep("gpu|cuda|torch\.device|tf\.device|batch_size|num_workers|distributed", type="py")` 识别 GPU 使用模式
- 计算实例汇总：类型、规格（CPU/内存/GPU）、数量、区域
- 存储资源汇总：类型（块存储/对象存储/文件存储）、容量、存储类别
- 网络资源汇总：负载均衡、NAT 网关、带宽配置、CDN 配置
- 数据库实例汇总：类型、规格、副本数
- 容器资源汇总：Pod 资源请求/限制、HPA 配置、节点池配置
- GPU 资源汇总：GPU 型号、数量、调度策略、显存配置

**代码资源使用模式**：
- **数据库查询模式**：`Grep("\.query\(|\.execute\(|\.find\(|\.findAll\(|SELECT |INSERT |UPDATE |DELETE |\.where\(", type="代码文件")` 识别查询模式；`Grep("include:|join:|eager_load|prefetch_related|\.Include\(", type="代码文件")` 检查 N+1 查询风险
- **缓存使用模式**：`Grep("redis|memcache|cache\.get|cache\.set|@Cacheable|lru_cache|TTL|expire", type="代码文件")` 识别缓存读写
- **API 调用模式**：`Grep("fetch\(|axios\.|requests\.(get|post)|http\.Get|HttpClient|\.call\(|grpc\.", type="代码文件")` 识别外部 API 调用
- **文件/IO 操作**：`Grep("readFile|writeFile|open\(|fopen|io\.Reader|bufio|streaming", type="代码文件")` 识别 IO 模式
- **AI/ML 相关**：`Grep("DataLoader|Dataset|model\.load|torch\.load|tf\.saved_model|batch_size|num_workers", type="py")` 识别训练和推理模式

Scanner 输出**资源清单报告**，完成后关闭。

### 步骤 5：启动 analyzer-1 和 analyzer-2（并行）

Team lead 将 scanner 的资源清单报告分发给两位 analyzer，作为分析的基准数据。

**Analyzer-1 基础设施层分析**（scope 为 `code` 时跳过）：

每项分析输出：当前状态 → 问题描述 → 优化建议 → 预估影响

1. **计算资源优化**：
   - 实例规格 vs 实际负载匹配度
   - GPU 利用率评估（空闲率、显存利用率、计算利用率）
   - 预留实例 / Spot 实例策略
   - 自动伸缩（HPA/VPA/Cluster Autoscaler）配置合理性
   - AI 训练任务调度效率（排队时间、资源碎片）

2. **存储优化**：
   - 存储类型与访问模式匹配（热/温/冷数据分层）
   - 数据生命周期管理（过期数据清理策略）
   - 压缩和去重机会
   - 快照和备份策略（频率、保留期）

3. **网络优化**：
   - 跨区域/跨 AZ 流量评估
   - CDN 缓存策略
   - API 网关和负载均衡配置
   - 内网 vs 公网流量优化

4. **CI/CD 优化**：
   - 构建时间分析（缓存利用率、并行度）
   - 镜像大小和层数优化
   - 测试并行化机会
   - 制品存储清理策略

**Analyzer-2 代码/应用层分析**（scope 为 `infra` 时跳过）：

每项分析输出：当前模式 → 问题描述 → 优化建议 → 预估影响

1. **数据库优化**：
   - 慢查询识别（全表扫描、缺失索引、不合理 JOIN）
   - 连接池配置（最大连接数、空闲超时）
   - 读写分离机会
   - 查询结果缓存机会

2. **缓存策略**：
   - 缓存命中率评估（从代码模式推断）
   - 缓存穿透/击穿/雪崩风险
   - 热点数据缓存覆盖
   - 多级缓存（本地 + 分布式）机会

3. **算法效率**：
   - 高复杂度算法识别（O(n^2) 及以上）
   - 重复计算识别（可 memoize 的函数）
   - 批处理机会（逐条 → 批量）
   - 异步化机会（同步阻塞 → 异步）

4. **资源泄漏与浪费**：
   - 未关闭的连接/文件句柄
   - 内存泄漏模式
   - 不必要的数据拷贝
   - 过度日志/监控数据

5. **AI/ML 应用优化**（如适用）：
   - 模型加载策略（预加载 vs 按需加载）
   - 推理批处理（batch inference）
   - 数据管道效率（ETL/数据加载瓶颈）
   - 模型量化/蒸馏机会

### 步骤 6：收集报告

Scanner 完成后关闭。Analyzer-1 和 Analyzer-2 完成后各自向 team lead 发送分析报告。Team lead 确认收到全部报告后，进入阶段二。

---

## 阶段二：合并分析

### 步骤 7：启动 analyst

Team lead 启动 analyst，将以下内容传递：
- Scanner 的资源清单报告
- Analyzer-1 的基础设施分析报告（标记为"分析师 A"）
- Analyzer-2 的代码/应用分析报告（标记为"分析师 B"）

**重要**：传递时不透露 analyzer 编号，仅用"分析师 A"和"分析师 B"标记，避免暗示优先级。

### 步骤 8：Analyst 合并 + ROI 量化

Analyst 对两份报告进行以下处理：

**合并去重**：

| 对比结果 | 处理方式 |
|---------|---------|
| **相同发现**（同一问题从不同角度识别） | 合并为一项，标记为"共识" |
| **独立发现**（各自领域的独有发现） | 直接采纳，标记来源 |
| **分歧/矛盾**（对同一资源有不同优化建议） | 标注为"待仲裁"，记录双方观点 |

**ROI 量化**（每项优化）：

| 维度 | 说明 |
|------|------|
| 预估月节省 | 基于资源单价和使用量推算，标明估算依据 |
| 投入工时 | 实施该优化所需的人天数 |
| 实施风险 | 低（配置变更）/ 中（代码修改）/ 高（架构调整） |
| ROI 比率 | 12 个月节省总额 / 投入成本（工时×人天单价） |
| 优先级 | 根据 ROI 等级自动分级（P0/P1/P2/不建议） |

Analyst 输出：
1. **优化清单**：所有优化项，按 ROI 降序排列
2. **分类汇总**：按类别（计算/存储/网络/数据库/缓存/算法/CI-CD/GPU）汇总节省
3. **共识清单**：双方一致的发现
4. **分歧清单**：矛盾之处及双方观点对比
5. **共识度评估**：共识度 = (共识发现数 + 独立发现数) / 总发现数(去重并集) x 100%

**Analyst 处理矛盾的原则**：analyst 不直接阅读代码或配置，当两份分析对同一资源/模式存在根本性矛盾时，必须标注为"待仲裁"并升级给 team lead，不得自行裁决。

### 步骤 9：检查熔断条件

如果共识度 < 50%（分歧占比超过一半）：
- **必须暂停**，team lead 向用户报告情况
- 可能原因：项目配置和代码层面有矛盾、分析范围过大导致关注点不同
- 建议：缩小 scope 或明确优化目标

共识度 >= 50%：继续下一阶段。

### 步骤 10：分歧仲裁

如果分歧清单为空 → 跳过仲裁，直接进入阶段三。

Team lead 对分歧清单中的每个分歧点：

1. 将分歧描述分别发给 analyzer-1 和 analyzer-2，要求各自提供论证：
   - 你的优化建议是什么？
   - 依据是哪些配置/代码/指标？
   - 为什么你认为对方的建议不适合？

2. 收到双方论证后：
   - **标准模式**：team lead 向用户展示分歧摘要和双方论证，AskUserQuestion 让用户裁决
   - **单轮确认模式**：team lead 综合双方论证和实际配置/代码证据自行裁决
   - **完全自主模式**：自动决策，不询问用户

3. 将仲裁结果发送给 analyst 更新分析

### 步骤 11：Analyst 更新分析

Analyst 根据仲裁结果更新合并分析，将所有"待仲裁"项替换为最终结论，重新计算汇总数据。输出**最终合并分析报告**。

---

## 阶段三：报告生成

### 步骤 12：启动 reporter 生成最终报告

Team lead 启动 reporter，将以下内容传递：
- Scanner 的资源清单报告
- Analyst 的最终合并分析报告
- 仲裁结果（如有）
- `--lang` 参数
- `--scope` 参数

Reporter 按指定语言基于这些结构化输入生成最终成本优化报告。文档格式：

```markdown
# [项目名] 成本优化分析报告

> 生成时间：YYYY-MM-DD | 分析范围：infra/code/full | 共识度：XX%

## 1. 摘要

| 指标 | 值 |
|------|---|
| 识别优化项 | XX 个 |
| 预计月节省 | $XX,XXX |
| 总投入工时 | XX 人天 |
| 综合 ROI | X.Xx |

### 节省分布

| 类别 | 优化项数 | 预计月节省 | 占比 |
|------|---------|-----------|------|
| 计算资源 | X | $X,XXX | XX% |
| 存储 | X | $X,XXX | XX% |
| 网络 | X | $X,XXX | XX% |
| GPU 利用率 | X | $X,XXX | XX% |
| 数据库 | X | $X,XXX | XX% |
| 缓存 | X | $X,XXX | XX% |
| 算法效率 | X | $X,XXX | XX% |
| CI/CD | X | $X,XXX | XX% |

## 2. 基础设施分析

### 2.1 计算资源
[当前状态 → 问题 → 建议 → 预估影响]

### 2.2 存储
[当前状态 → 问题 → 建议 → 预估影响]

### 2.3 网络
[当前状态 → 问题 → 建议 → 预估影响]

### 2.4 GPU 利用率
[当前状态 → 问题 → 建议 → 预估影响]

### 2.5 CI/CD
[当前状态 → 问题 → 建议 → 预估影响]

## 3. 代码/应用层分析

### 3.1 数据库优化
[当前模式 → 问题 → 建议 → 预估影响]

### 3.2 缓存策略
[当前模式 → 问题 → 建议 → 预估影响]

### 3.3 算法效率
[当前模式 → 问题 → 建议 → 预估影响]

### 3.4 资源泄漏与浪费
[当前模式 → 问题 → 建议 → 预估影响]

### 3.5 AI/ML 应用优化（如适用）
[当前模式 → 问题 → 建议 → 预估影响]

## 4. 优化建议（按 ROI 排序）

| # | 优化项 | 类别 | 预计月节省 | 投入工时 | ROI | 风险 | 优先级 |
|---|-------|------|-----------|---------|-----|------|--------|
| 1 | [描述] | [类别] | $X,XXX | X 人天 | X.Xx | 低/中/高 | P0 |
| 2 | [描述] | [类别] | $X,XXX | X 人天 | X.Xx | 低/中/高 | P1 |
| ... | ... | ... | ... | ... | ... | ... | ... |

## 5. 实施路线图

### Phase 1: 快速收益（P0, 1-2 周）
- [ ] [优化项 1]：[具体步骤]
- [ ] [优化项 2]：[具体步骤]
预计节省：$X,XXX/月

### Phase 2: 中期优化（P1, 1-2 月）
- [ ] [优化项 3]：[具体步骤]
- [ ] [优化项 4]：[具体步骤]
预计节省：$X,XXX/月

### Phase 3: 长期改进（P2, 季度）
- [ ] [优化项 5]：[具体步骤]
- [ ] [优化项 6]：[具体步骤]
预计节省：$X,XXX/月

## 附录 A: 资源清单

### 计算资源
| 资源 | 规格 | 数量 | 区域 | 月成本估算 |
|------|------|------|------|-----------|

### 存储资源
| 资源 | 类型 | 容量 | 月成本估算 |
|------|------|------|-----------|

### GPU 资源
| 资源 | GPU 型号 | 数量 | 调度策略 | 月成本估算 |
|------|---------|------|---------|-----------|

## 附录 B: 分析共识说明

### 共识结论
[两位分析师一致的核心发现列表]

### 分歧点及仲裁结果
| 分歧点 | 分析师 A 观点 | 分析师 B 观点 | 仲裁结果 | 理由 |
|--------|-------------|-------------|---------|------|
| [描述] | [观点] | [观点] | [结论] | [理由] |
```

**注意**：
- `scope=infra` 时省略"3. 代码/应用层分析"章节
- `scope=code` 时省略"2. 基础设施分析"章节
- 金额单位根据项目实际情况使用 $ 或 RMB
- 智算云项目需特别关注 GPU 相关章节的详细程度

### 步骤 13：用户确认

Team lead 向用户展示报告摘要：
- 识别优化项总数
- 预计月节省总额
- P0 优化项列表（快速收益）
- 综合 ROI
- 共识度和分歧处理结果

AskUserQuestion 确认：
- 接受报告
- 需要补充某些方面的分析
- 需要调整某些结论或优先级

**单轮确认模式**：必须经用户确认。

**完全自主模式**：自动决策，不询问用户，收尾时汇总。

---

## 阶段四：收尾

### 步骤 14：保存报告

将最终成本优化报告保存到项目的 `docs/cost-analysis/` 目录：
- 文件名：`cost-optimization-YYYY-MM-DD.md`
- 如果目录不存在，创建之

### 步骤 15：最终总结

Team lead 按 `--lang` 指定的语言向用户输出：
- 分析了什么（项目名称、范围 scope）
- 核心发现（Top 3 优化项及预估节省）
- 总计：识别优化项数、预计月节省、综合 ROI
- 实施建议：Phase 1 快速收益项
- 共识度和分歧处理情况
- 报告保存位置
- **（单轮确认模式/完全自主模式）自动决策汇总**：列出所有自动决策的节点、决策内容和理由

### 步骤 15.5：跨团队衔接建议（可选）

Team lead 根据项目情况向用户建议后续动作：
- **发现代码层面可优化**：建议运行 `/team-refactor` 实施代码层面的优化重构（算法优化、缓存策略等）
- **发现架构层面问题**：建议运行 `/team-review` 对项目做全面审查
- **发现 API 调用成本过高**：建议运行 `/team-api-design` 优化 API 设计（减少调用次数、批量化）
- **优化实施后需发布**：建议运行 `/team-release` 管理优化变更的发布流程
- **优化涉及重大基础设施变更**：建议运行 `/team-postmortem` 在变更后做风险评估和回顾
- **项目文档需更新基础设施信息**：建议运行 `/team-onboard` 更新基础设施相关的入职文档
- 用户可选择执行或跳过，不强制。

### 步骤 16：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 智算云专项优化指引

作为智算云公司，以下领域需要重点关注：

| 专项 | 关注要点 |
|------|---------|
| GPU 集群成本 | GPU 空闲率、多租户调度效率、GPU 共享/MIG 切分策略、显存碎片 |
| AI 训练任务 | 训练任务排队时间、抢占策略、Checkpoint 频率和存储成本、分布式训练通信开销 |
| 模型推理服务 | 推理实例自动伸缩、模型加载冷启动、批处理推理、模型量化/蒸馏节省 |
| 数据管道 | 训练数据预处理效率、数据缓存（避免重复读取）、数据格式优化（Parquet/TFRecord） |
| 多租户资源隔离 | 资源配额利用率、超卖比例、资源碎片率 |

---

## 核心原则

- **数据驱动**：所有优化建议必须基于 scanner 采集的实际配置和代码模式，不做主观臆测
- **ROI 导向**：每项优化必须量化投入和收益，按 ROI 排序而非按技术难度
- **独立分析**：两位 analyzer 必须完全独立工作，不互相看到对方结果，确保分析覆盖面
- **职责分离**：analyst 只做合并量化，reporter 只做报告生成，不交叉职责
- **可操作性**：优化建议必须具体到可执行步骤，不停留在"建议优化"的抽象层面
- **风险标注**：每项优化必须标注实施风险（配置变更/代码修改/架构调整），避免优化引入故障
- **并行高效**：scanner 和两位 analyzer 并行工作，最大化效率
- **有限分析**：根据 scope 参数控制分析范围，避免过度分析
- **熔断保护**：共识度 < 50% 必须暂停问用户，不可自动继续

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
| 无基础设施配置文件 | 自动切换为 `scope=code`，报告中说明 |
| 无明显代码入口 | 自动切换为 `scope=infra`，报告中说明 |
| 无法识别云厂商/平台 | Scanner 基于配置文件格式推断，无法推断时标注"平台未知"并按通用模式分析 |
| 项目过大无法完整分析 | Scanner 识别高成本模块（资源定义集中的目录），analyzer 聚焦高成本区域 |
| 成本数据缺失（无价格信息） | 使用主流云厂商公开价格作为参考，标注"基于参考价格估算" |
| 两位 analyzer 分析差异极大（共识度 < 50%） | 触发熔断，暂停问用户确认分析方向 |
| Analyzer 无法评估某项成本 | 在报告中标注"数据不足，无法评估"，不编造数据 |
| 项目使用私有云/混合云 | Scanner 识别部署拓扑，analyzer 按可用信息分析，标注局限性 |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前阶段恢复 |
| GPU 相关配置识别失败 | 检查 CUDA/cuDNN 配置、训练框架配置（PyTorch/TensorFlow）、SLURM 配置 |

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

