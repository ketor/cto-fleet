---
name: team-feature-flag
description: 启动一个 Feature Flag 管理团队（scanner/analyzer×2/cleaner/reporter），通过代码扫描+双路独立分析（flag 使用状态+生命周期健康度）+清理执行+报告生成，输出 flag 清单、清理 PR 和发布策略建议。使用方式：/team-feature-flag [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--action=audit|cleanup|strategy] [--provider=launchdarkly|unleash|custom|auto] [--lang=zh|en] 项目路径或 Feature Flag 管理需求
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--action=audit|cleanup|strategy] [--provider=launchdarkly|unleash|custom|auto] [--lang=zh|en] 项目路径或 Feature Flag 管理需求
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
- `--action=audit|cleanup|strategy`：执行动作（可选，默认 `audit` 审计模式）
  - `audit`：仅扫描和分析，输出 flag 清单和健康度报告
  - `cleanup`：在 audit 基础上生成清理代码（移除过期 flag）
  - `strategy`：在 audit 基础上输出发布策略建议（渐进式发布/灰度方案）
- `--provider=launchdarkly|unleash|custom|auto`：Feature Flag 提供商（默认 `auto` 自动检测）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后将标志从管理需求描述中移除。

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 扫描范围确认 + 清理方案确认 + 最终报告确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅最终报告确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下自动决策规则：
- **flag 提供商检测不确定** → scanner 列出所有可能的 provider，选择匹配度最高的
- **两位 analyzer 对同一 flag 的状态评估差异过大（如一方定为"可清理"、另一方定为"活跃"）** → **不可跳过，必须暂停问用户**（熔断机制）
- **需要清理的 flag 超过 20 个** → **不可跳过，必须暂停问用户**（熔断机制）
- **无法确定 flag 是否在生产环境生效** → analyzer 标注"状态未知，建议人工确认"，不阻塞流程
- **发现嵌套 flag（flag 依赖另一个 flag）** → analyzer 标注依赖关系，清理时优先处理被依赖的 flag

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效（状态评估差异过大、待清理 flag 超过 20 个时仍必须暂停问用户）。

使用 TeamCreate 创建 team（名称格式 `team-feature-flag-{YYYYMMDD-HHmmss}`，如 `team-feature-flag-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

## 流程概览

```
阶段零  环境识别 → 检测 provider，识别 flag SDK 和配置方式，确认扫描范围
         ↓
阶段一  代码扫描 + 双路独立分析（并行）
         ├─ scanner：全量代码扫描，提取所有 flag 引用和定义
         ├─ analyzer-1：使用状态分析（代码路径覆盖、运行时状态、引用计数）
         └─ analyzer-2：生命周期健康度分析（创建时间、最后修改、过期标记、命名规范）
         ↓
阶段二  合并分析 → cleaner 合并去重、状态校验、输出统一 flag 清单
         → 熔断检查（状态争议过多 / 待清理 > 20）
         → 生成清理代码（如 action=cleanup）
         ↓
阶段三  报告生成 → reporter 生成 flag 管理报告（含清单、策略建议、清理方案）
         ↓
阶段四  收尾 → 保存报告 + 清理团队
```

## 角色定义

| 角色 | 职责 |
|------|------|
| scanner | 扫描全量代码，识别 flag provider/SDK，提取所有 flag 定义和引用点，输出原始 flag 数据集。**仅在扫描阶段工作，完成后关闭。** |
| analyzer-1 | **使用状态维度分析**：分析每个 flag 的代码路径覆盖、条件分支是否都可达、是否存在死代码、引用计数和分布。输出结构化分析报告。**独立分析，不与 analyzer-2 交流。** |
| analyzer-2 | **生命周期维度分析**：分析每个 flag 的创建时间、最后修改时间、关联 PR/commit、过期标记、命名规范、文档覆盖。输出结构化分析报告。**独立分析，不与 analyzer-1 交流。** |
| cleaner | 合并两份分析报告和 scanner 扫描数据，交叉校验、统一状态判定、生成清理代码（如 action=cleanup）或发布策略（如 action=strategy）。**完成后关闭。** |
| reporter | 基于统一 flag 清单生成管理报告（含健康度评分、清理方案、策略建议），按 `--lang` 语言输出。**完成后关闭。** |

### 角色生命周期

| 角色 | 启动阶段 | 关闭时机 | 说明 |
|------|---------|---------|------|
| scanner | 阶段一（步骤 3） | 阶段一扫描完成后（步骤 3） | 扫描数据交付后即释放 |
| analyzer-1 | 阶段一（步骤 4，收到数据后启动） | 阶段一分析完成后（步骤 5） | 分析报告交付后释放 |
| analyzer-2 | 阶段一（步骤 4，与 analyzer-1 并行） | 阶段一分析完成后（步骤 5） | 分析报告交付后释放 |
| cleaner | 阶段二（步骤 6） | 阶段二合并/清理完成后（步骤 9） | 统一清单和清理代码输出后释放 |
| reporter | 阶段三（步骤 10） | 阶段三报告生成后（步骤 12） | 报告确认后释放 |

---

## Flag 生命周期状态定义

每个 flag 按生命周期阶段分类：

| 状态 | 含义 | 建议操作 |
|------|------|---------|
| **Active** | flag 正在使用中，控制活跃的功能发布 | 保持，监控发布进度 |
| **Rolled-out** | flag 已全量发布（所有路径返回同一值），但代码中仍有判断逻辑 | 清理 flag 代码，保留功能代码 |
| **Stale** | flag 超过 30 天未修改，且无关联的活跃 PR/Issue | 确认是否应清理或继续保留 |
| **Expired** | flag 有明确的过期时间/标记，且已过期 | 优先清理 |
| **Orphaned** | flag 在代码中有引用，但在 provider 平台中不存在（或反之） | 确认并清理不一致 |
| **Nested** | flag 的判断逻辑嵌套在另一个 flag 内 | 评估是否可以合并或简化 |
| **Unknown** | 无法确定状态（数据不足） | 人工确认 |

---

## Flag Provider 检测模式

| Provider | 检测方式 | SDK/API 模式 |
|----------|---------|-------------|
| LaunchDarkly | `launchdarkly-*` 依赖 + `ld-*` 配置文件 | `ldClient.variation()` / `useLDClient()` |
| Unleash | `unleash-*` 依赖 + `unleash` 配置 | `unleash.isEnabled()` / `useFlag()` |
| Flagsmith | `flagsmith` 依赖 | `flagsmith.hasFeature()` / `getValue()` |
| Split.io | `@splitsoftware/*` 依赖 | `client.getTreatment()` |
| ConfigCat | `configcat-*` 依赖 | `client.getValueAsync()` |
| 自定义 | 环境变量 / 配置文件 / 数据库 | `process.env.FEATURE_*` / `config.features.*` |
| 自动检测 | 依次尝试以上模式 | 选择匹配度最高的 |

**自定义 flag 识别模式**（当无标准 provider 时）：
- 环境变量：`FEATURE_*`、`FF_*`、`ENABLE_*`、`FLAG_*`
- 配置文件：`features.json`、`flags.yaml`、`feature-flags.*`
- 代码模式：`isFeatureEnabled()`、`featureFlag()`、`useFeatureFlag()`

---

## 分析维度分配

双 analyzer 按各自负责的维度独立分析，cleaner 合并为统一 flag 状态评估。

| 维度 | 权重 | 负责人 | 分析内容 |
|------|------|--------|---------|
| 代码路径覆盖 | 20% | analyzer-1 | flag 的 true/false 分支是否都有代码覆盖、死代码检测 |
| 引用分布 | 15% | analyzer-1 | flag 被引用的文件数、组件数、层级（UI/API/Service） |
| 运行时状态推断 | 15% | analyzer-1 | 基于代码和配置推断 flag 当前返回值（全量/灰度/关闭） |
| 创建时间与活跃度 | 15% | analyzer-2 | flag 首次引入的 commit 时间、最近修改时间、关联 PR |
| 过期标记 | 10% | analyzer-2 | 代码注释中的过期标记（TODO/FIXME/DEPRECATED）、配置中的 expiry |
| 命名规范 | 10% | analyzer-2 | flag 命名是否遵循团队规范、是否包含日期/版本/负责人信息 |
| 文档覆盖 | 5% | analyzer-2 | flag 是否有 README/注释说明用途、目标用户、预期清理时间 |
| 依赖关系 | 10% | analyzer-2 | flag 间的嵌套/依赖关系、flag 与环境/用户分群的关联 |

**analyzer-1 总权重：50%**（代码路径覆盖 20% + 引用分布 15% + 运行时状态推断 15%）
**analyzer-2 总权重：50%**（创建时间与活跃度 15% + 过期标记 10% + 命名规范 10% + 文档覆盖 5% + 依赖关系 10%）

---

## 阶段零：环境识别

### 步骤 1：解析扫描范围

Team lead 分析项目和参数：

1. 解析 `--provider` 和 `--action` 参数
2. 阅读项目结构，识别技术栈和 flag 使用方式：
   - 前端框架和 flag SDK（React/Vue/Angular + provider SDK）
   - 后端框架和 flag SDK（Node/Python/Go/Java + provider SDK）
   - 配置管理方式（环境变量、配置文件、远程配置中心）
   - 部署环境（dev/staging/production）
3. 自动检测 flag provider（如 `--provider=auto`）
4. 输出扫描范围清单

### 步骤 2：用户确认扫描范围

**标准模式**：向用户展示扫描范围清单，AskUserQuestion 确认：
- 确认 flag provider 和扫描范围
- 补充自定义 flag 模式（如特殊命名规范）
- 调整 action 模式

**单轮确认模式**：跳过确认，直接进入阶段一。
**完全自主模式**：自动决策，不询问用户，直接进入阶段一。

---

## 阶段一：代码扫描 + 双路独立分析

### 步骤 3：启动 scanner 全量扫描

**Scanner 代码扫描**：
1. 根据检测到的 provider，确定 flag 引用模式（函数调用/配置键/环境变量）
2. 全量扫描代码库，提取所有 flag 相关数据：

| 扫描项 | 扫描方式 | 输出 |
|--------|---------|------|
| Flag 定义 | provider 配置文件/平台导出/代码中的默认值 | flag_name + default_value + description |
| Flag 引用 | 代码中的 SDK 调用/条件判断 | flag_name + file_path + line_number + context |
| Flag 配置 | 环境变量/.env 文件/配置中心 | flag_name + env + value |
| 测试引用 | 测试文件中的 flag mock/override | flag_name + test_file + mock_value |
| 注释标记 | TODO/FIXME/DEPRECATED + flag 名称 | flag_name + comment + date |

3. 构建 flag 索引：每个 flag 的所有引用点、定义点、配置点
4. 汇总输出**Flag 扫描数据集**发送给 team lead
5. Scanner 完成后关闭

### 步骤 4：分发扫描数据并启动双 analyzer

Team lead 收到 scanner 数据集后，将原始数据分发给两位 analyzer，**并行启动**。

### 步骤 5：独立并行分析

两位 analyzer 各自分析负责的维度，**互不交流**。

**Analyzer-1（使用状态维度）** — 分析每个 flag 的使用状态：

| 分析项 | 分析方法 | 输出 |
|--------|---------|------|
| **代码路径分析** | 检查 flag 的 true/false 分支是否都有实际代码逻辑 | 分支活跃度（both-active/one-active/dead） |
| **死代码检测** | flag 始终返回固定值时，另一分支是否为死代码 | 死代码文件/行号列表 |
| **引用计数** | 每个 flag 在代码中被引用的次数 | 引用计数 + 引用文件列表 |
| **引用层级** | flag 被引用在哪些层级（UI 组件/API 路由/Service 层/基础设施） | 层级分布 |
| **条件复杂度** | flag 判断逻辑的复杂度（简单 if/else、嵌套条件、组合条件） | 复杂度评分 |
| **运行时推断** | 基于配置/环境变量推断 flag 在各环境的返回值 | 环境→值映射 |
| **全量发布检测** | flag 在所有环境都返回同一值（已全量发布） | 是否已全量 |

- 对每个 flag 输出：flag 名称 + 使用状态 + 分支活跃度 + 引用统计 + 是否可清理
- 重点标注"已全量发布但未清理"的 flag

**Analyzer-2（生命周期维度）** — 分析每个 flag 的生命周期健康度：

| 分析项 | 分析方法 | 输出 |
|--------|---------|------|
| **创建时间** | 追溯 flag 首次出现的 git commit | 创建日期 + 关联 PR |
| **最后修改** | flag 相关代码最近一次修改的时间 | 最后活跃日期 |
| **存活时长** | 从创建到现在的天数 | 天数 + 是否超标（>90天警告） |
| **过期标记** | 代码注释/配置中的过期信息 | 过期时间/标记 |
| **命名规范** | flag 名称是否包含有意义前缀/日期/负责人 | 规范性评分 |
| **文档覆盖** | flag 是否有用途说明、清理计划、负责人 | 文档完整度 |
| **依赖关系** | flag 间的嵌套/依赖、与用户分群的关联 | 依赖图谱 |
| **关联活跃度** | flag 关联的 Issue/PR 是否仍活跃 | 关联状态 |

- 对每个 flag 输出：flag 名称 + 创建时间 + 存活时长 + 健康度评分 + 是否过期/陈旧
- 重点标注"超过 90 天未修改且无活跃关联"的 flag

---

## 阶段二：合并分析与清理

### 步骤 6：启动 cleaner

两位 analyzer 分析完成后，启动 cleaner。Team lead 将以下材料发送给 cleaner：
- Scanner Flag 扫描数据集
- Analyzer-1 使用状态分析报告
- Analyzer-2 生命周期分析报告
- 项目技术栈和 flag provider 信息

### 步骤 7：合并与状态判定

Cleaner 执行合并分析：

1. **合并**：将两份分析报告按 flag 名称合并
2. **交叉校验**：检查两位 analyzer 对同一 flag 的状态判断是否一致
3. **状态判定**：综合两个维度，为每个 flag 判定最终状态（Active/Rolled-out/Stale/Expired/Orphaned/Nested/Unknown）
4. **优先级排序**：按清理紧急度排序（Expired > Rolled-out > Stale > Orphaned > Nested）
5. **依赖分析**：识别 flag 间依赖关系，确保清理顺序正确

**共识度计算公式**：
```
两位 analyzer 分析有部分结论交叉（如 analyzer-1 判定"可清理" 与 analyzer-2 判定"过期" 通常一致）。
对于每个 flag 的状态判定：

共识 flag 数 = 两位 analyzer 判定结果一致的 flag 数
总 flag 数 = 去重后的 flag 总数

共识度 = 共识 flag 数 / 总 flag 数 × 100%

争议 flag = 两位 analyzer 判定结果矛盾的 flag（如一方"可清理"另一方"活跃"）
争议率 = 争议 flag 数 / 总 flag 数 × 100%

争议率 > 50% → 触发熔断，必须暂停问用户
```

### 步骤 8：差异校验与熔断检查

**状态判定差异校验**：
- 如果两位 analyzer 对同一 flag 的状态判定矛盾（如 analyzer-1 判定"可清理"/analyzer-2 判定"活跃"），cleaner 标注为"争议项"
- 争议项占比 > 50% → **不可跳过，必须暂停问用户**（熔断机制）

**大规模清理熔断**：
- 需要清理的 flag 超过 20 个 → **不可跳过，必须暂停问用户**（熔断机制）
- 向用户展示待清理 flag 列表，确认是否继续

**无熔断触发**时，cleaner 输出**统一 Flag 清单**：

```
## 统一 Feature Flag 清单

### Flag 统计
- Active: X 个 | Rolled-out: X 个 | Stale: X 个 | Expired: X 个 | Orphaned: X 个 | Nested: X 个 | Unknown: X 个
- 总计: X 个 flag
- 建议清理: X 个

### Flag 清单（按状态分组）

#### Expired（已过期，优先清理）
| # | Flag 名称 | 创建时间 | 过期时间 | 引用数 | 层级 | 操作建议 |
|---|----------|---------|---------|--------|------|---------|
| 1 | feature_xxx | 2025-01-01 | 2025-06-01 | 5 | UI+API | 清理代码 |

#### Rolled-out（已全量发布）
| # | Flag 名称 | 全量时间 | 引用数 | 层级 | 操作建议 |
|---|----------|---------|--------|------|---------|
| 1 | feature_yyy | 2025-03-01 | 12 | UI | 移除 flag 判断，保留功能代码 |

#### Stale / Orphaned / Nested
...

### 争议项（如有）
1. flag_name - analyzer-1 判定: 可清理 / analyzer-2 判定: 活跃 - cleaner 最终判定: X - 理由
```

### 步骤 8.5：生成清理代码（如 action=cleanup）

如果用户指定了 `--action=cleanup`，cleaner 为每个待清理 flag 生成清理代码：

**清理策略**：
| Flag 状态 | 清理方式 |
|----------|---------|
| Expired | 移除 flag 判断逻辑和 false 分支代码，保留 true 分支代码 |
| Rolled-out（全量 true） | 移除 flag 判断逻辑和 false 分支代码，保留 true 分支代码 |
| Rolled-out（全量 false） | 移除 flag 判断逻辑和 true 分支代码，保留 false 分支代码 |
| Stale | 生成清理代码但标注"建议人工确认" |
| Orphaned（代码有/平台无） | 移除代码中的 flag 引用 |
| Orphaned（代码无/平台有） | 标注"建议从 provider 平台移除" |

每个清理操作输出：
- 修改文件列表和 diff
- 清理前后代码对比
- 关联测试是否需要更新
- 回滚方式

### 步骤 8.6：生成发布策略（如 action=strategy）

如果用户指定了 `--action=strategy`，cleaner 为 Active 状态的 flag 生成发布策略建议：

| 策略类型 | 适用场景 | 配置建议 |
|---------|---------|---------|
| 百分比灰度 | 通用功能发布 | 1% → 5% → 25% → 50% → 100%，每阶段观察 24h |
| 用户分群 | 针对特定用户群体 | 内部用户 → Beta 用户 → 付费用户 → 全量 |
| 地域灰度 | 多地域部署 | 单个地域 → 多地域 → 全量 |
| 金丝雀 | 高风险变更 | 1% 流量 + 监控指标，异常自动回滚 |
| 即时发布 | 低风险/紧急发布 | 直接全量，配合监控告警 |

Cleaner 完成后关闭。

### 步骤 9：Flag 健康度评分

Team lead 根据统一 Flag 清单计算健康度评分：

评分规则：
- 基础分 10.0，按问题扣分
- Expired flag（未清理）：每个扣 1.0 分
- Rolled-out flag（未清理）：每个扣 0.8 分
- Stale flag（>90 天未活跃）：每个扣 0.5 分
- Orphaned flag：每个扣 0.5 分
- Nested flag（复杂度高）：每个扣 0.3 分
- 命名不规范：每个扣 0.1 分
- Unknown 状态：每个扣 0.2 分

输出总体 Flag 管理健康度评分。

---

## 阶段三：报告生成

### 步骤 10：启动 reporter

Team lead 将以下材料发送给 reporter：
- 统一 Flag 清单
- Flag 健康度评分
- 清理代码（如 action=cleanup）
- 发布策略（如 action=strategy）
- 项目技术栈和 flag provider 信息
- 输出语言（`--lang`）

### 步骤 11：生成 Flag 管理报告

Reporter 生成结构化 Feature Flag 管理报告：

```
## Feature Flag 管理报告

### 元信息
- 生成时间：YYYY-MM-DD HH:mm:ss
- 团队名称：team-feature-flag-{YYYYMMDD-HHmmss}
- 执行模式：标准模式 / 单轮确认模式 / 完全自主模式
- 输出语言：zh / en
- 分析参数：--action=[action 值] --provider=[provider 值]

### 1. 概述
- Flag Provider：[provider 名称]
- 总 Flag 数：X 个
- 健康度评分：X.X / 10.0
- 建议清理：X 个
- 技术栈：[框架/SDK]

### 2. Flag 状态分布
| 状态 | 数量 | 占比 | 建议操作 |
|------|------|------|---------|
| Active | X | XX% | 监控发布进度 |
| Rolled-out | X | XX% | 清理 flag 代码 |
| Stale | X | XX% | 确认是否应清理 |
| Expired | X | XX% | 优先清理 |
| Orphaned | X | XX% | 确认并清理 |
| Nested | X | XX% | 评估简化 |
| Unknown | X | XX% | 人工确认 |

### 3. Flag 详细清单
#### 待清理 Flag（按优先级排序）
| # | Flag 名称 | 状态 | 创建时间 | 存活天数 | 引用数 | 影响文件数 | 清理风险 |
|---|----------|------|---------|---------|--------|----------|---------|
| 1 | ... | Expired | ... | ... | ... | ... | 低/中/高 |

#### Active Flag
| # | Flag 名称 | 创建时间 | 引用数 | 发布阶段 | 负责人 | 预计清理时间 |
|---|----------|---------|--------|---------|--------|------------|
| 1 | ... | ... | ... | 灰度中 | ... | ... |

### 4. 清理方案（如 action=cleanup）
#### 清理操作 1：[flag 名称]
- 当前状态：[Expired/Rolled-out/Stale]
- 影响文件：[文件列表]
- 清理方式：[移除 flag 判断，保留 true/false 分支代码]
- 关联测试更新：[需要/不需要]
- 回滚方式：[git revert]

### 5. 发布策略建议（如 action=strategy）
#### Flag: [flag 名称]
- 当前阶段：[开发中/灰度中/即将全量]
- 建议策略：[百分比灰度/用户分群/金丝雀]
- 发布计划：[阶段描述]
- 监控指标：[关键指标]
- 回滚条件：[条件描述]

### 6. Flag 管理规范建议
- 命名规范：[建议的命名模式]
- 生命周期策略：[创建→灰度→全量→清理 时间线]
- 文档要求：[每个 flag 应包含的元信息]
- 清理机制：[定期清理流程建议]

### 7. 依赖关系图
- [flag 间的依赖关系可视化描述]
- 清理顺序建议：[基于依赖关系的安全清理顺序]
```

### 步骤 12：用户确认报告

Team lead 向用户展示 Flag 管理报告摘要：
- Flag 健康度评分
- 状态分布概览
- 待清理 Flag 列表摘要
- 关键发现和建议

AskUserQuestion 确认：
- 确认报告，保存并结束
- 要求深入分析某个 flag
- 调整清理优先级或发布策略

**单轮确认模式**：最终报告必须经用户确认。
**完全自主模式**：自动决策，不询问用户。

Reporter 完成后关闭。

---

## 阶段四：收尾

### 步骤 13：保存报告

Team lead 按 `--lang` 指定的语言保存最终报告：

1. 将完整 Flag 管理报告保存到项目目录（如 `feature-flag-report-YYYYMMDD.md`）
2. 向用户输出报告保存路径和管理总结：

```
## Feature Flag 管理完成

### 管理总结
- Flag Provider：[provider]
- 总 Flag 数：X 个
- 健康度评分：X.X / 10.0
- 建议清理：X 个（Expired X / Rolled-out X / Stale X）
- 报告路径：[文件路径]

### 关键发现
1. [最需要关注的 flag 问题]
2. ...

### 建议下一步
1. 清理 Expired 状态的 flag（X 个）
2. 清理 Rolled-out 状态的 flag（X 个）
3. 建立 flag 生命周期管理规范
4. 定期运行 /team-feature-flag 跟踪 flag 健康度

### 自主决策汇总（单轮确认模式/完全自主模式）
| 决策节点 | 决策内容 | 理由 |
|---------|---------|------|
| [阶段/步骤] | [决策描述] | [理由] |

### 附录：分析共识说明
- analyzer-1 分析维度：代码路径覆盖 + 引用分布 + 运行时状态推断
- analyzer-2 分析维度：创建时间 + 过期标记 + 命名规范 + 依赖关系
- scanner 识别 flag 数：[数量] 个
- 共识度 = XX%（两位 analyzer 判定一致的 flag 占比）
- 争议项：[数量] 个（争议率 = XX%）
  - [flag 名] — analyzer-1 判定: X / analyzer-2 判定: Y → cleaner 最终判定: Z（理由）
- 仅 analyzer-1 发现问题：[列表]
- 仅 analyzer-2 发现问题：[列表]
```

### 步骤 13.5：跨团队衔接建议（可选）

Team lead 根据分析结果向用户建议后续动作：
- **需要清理大量 flag 代码**：建议运行 `/team-refactor` 批量重构清理
- **清理涉及测试更新**：建议运行 `/team-review` 审查清理代码
- **需要建立 flag 管理规范**：建议运行 `/team-rfc` 制定技术规范
- **flag 与技术债务相关**：建议运行 `/team-techdebt` 全面评估技术债务
- 用户可选择执行或跳过，不强制。

### 步骤 14：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 核心原则

- **安全清理**：清理代码前必须充分分析影响范围，避免误删活跃功能
- **双路独立**：两位 analyzer 从不同维度独立分析，互不交流，避免盲区
- **生命周期管理**：关注 flag 的完整生命周期，从创建到清理形成闭环
- **依赖感知**：清理前必须分析 flag 间依赖关系，按正确顺序清理
- **可回滚**：所有清理操作必须可 git revert 回滚，不做不可逆操作
- **渐进清理**：大规模清理分批进行，每批验证后再清理下一批
- **规范先行**：建议建立 flag 命名规范和生命周期策略，防止问题积累
- **数据驱动**：基于代码分析和 git 历史判断 flag 状态，不做主观推测

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| Flag provider 无法自动检测 | Scanner 列出所有疑似 flag 模式，询问用户确认 |
| Provider 平台不可访问 | 仅基于代码分析，标注"无法验证平台状态" |
| 代码库过大（>100 万行） | Scanner 按模块分批扫描，优先扫描核心业务模块 |
| 两位 analyzer 状态判定矛盾（争议项 > 50%） | 触发熔断，暂停问用户裁决争议项 |
| 待清理 flag 超过 20 个 | 触发熔断，暂停向用户确认清理范围 |
| Flag 嵌套层级过深（>3 层） | Analyzer 标注为高风险，建议逐层清理 |
| 清理代码导致测试失败 | Cleaner 标注需要更新的测试文件 |
| 自定义 flag 模式不标准 | Scanner 输出所有疑似 flag，让 analyzer 人工判断 |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前步骤恢复 |
| Monorepo 中多个服务共享 flag | 按服务分组分析，标注跨服务 flag |

---

## 需求

$ARGUMENTS
