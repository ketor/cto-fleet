---
name: team-contract-test
description: 启动一个 API 契约测试团队（scanner/designer×2/generator/validator），通过 API 规范扫描+双路独立设计（提供者契约+消费者驱动契约）+测试生成+兼容性验证，输出契约测试套件和破坏性变更检测报告。使用方式：/team-contract-test [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--style=pact|openapi|grpc|auto] [--scope=provider|consumer|both] [--lang=zh|en] 项目路径或 API 契约测试需求
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--style=pact|openapi|grpc|auto] [--scope=provider|consumer|both] [--lang=zh|en] 项目路径或 API 契约测试需求
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
- `--style=pact|openapi|grpc|auto`：契约风格（可选，默认 `auto` 自动检测）
- `--scope=provider|consumer|both`：测试范围（可选，默认 `both`）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后将标志从测试需求描述中移除。

**契约风格自动检测**：当 `--style=auto`（默认）时，scanner 根据项目特征自动选择：
- 存在 OpenAPI/Swagger 规范文件（`openapi.yaml`、`swagger.json` 等）→ `openapi`
- 存在 `.proto` 文件或 gRPC 服务定义 → `grpc`
- 存在 Pact 配置或消费者测试 → `pact`
- 以上均无 → 基于 HTTP API 端点推断，默认 `openapi`

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 契约范围确认 + 最终测试套件确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅最终测试套件确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下自动决策规则：
- **API 端点分类不确定** → 对应 designer 自行判断，报告中说明
- **两位 designer 对同一端点的契约定义冲突（字段类型/必填性不一致）** → **不可跳过，必须暂停问用户**（熔断机制）
- **破坏性变更超过 10 个** → **不可跳过，必须暂停问用户**（熔断机制）
- **API 规范文件不存在或解析失败** → scanner 标注"该规范不可用"，基于代码推断
- **端点数量超出预期（> 200 个）** → generator 自行决定是否分批生成

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效（契约定义冲突、破坏性变更超过 10 个时仍必须暂停问用户）。

使用 TeamCreate 创建 team（名称格式 `team-contract-test-{YYYYMMDD-HHmmss}`，如 `team-contract-test-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

## 流程概览

```
阶段零  风格选择 + API 扫描 → 选定契约风格，识别 API 端点和服务依赖，确认测试目标
         ↓
阶段一  API 规范扫描 + 双路独立契约设计（并行）
         ├─ scanner：API 规范扫描（端点发现、Schema 提取、依赖关系映射、版本差异检测）
         ├─ designer-1：提供者契约设计（Provider-side contract，基于 API 实现定义契约）
         └─ designer-2：消费者驱动契约设计（Consumer-driven contract，基于消费者需求定义契约）
         ↓
阶段二  契约合并 → generator 合并两份契约设计，解决冲突，输出统一契约定义
         → 熔断检查（契约冲突 > 50% / 破坏性变更 > 10）
         ↓
阶段三  测试生成 → generator 基于统一契约生成测试套件 + 破坏性变更检测
         ↓
阶段四  兼容性验证 → validator 验证测试可运行性 + 报告生成 + 清理团队
```

## 角色定义

| 角色 | 职责 |
|------|------|
| scanner | 识别项目 API 架构（REST/gRPC/GraphQL），发现所有端点和服务依赖，提取现有 API 规范（OpenAPI/Proto/Pact），检测 API 版本差异，输出端点清单和规范数据。**仅在扫描阶段工作，完成后关闭。** |
| designer-1 | **提供者契约设计**：基于 API 实际实现（控制器、路由、Handler、序列化器），定义提供者侧契约——接口的输入/输出 Schema、状态码、错误格式、边界条件。关注"API 实际能做什么"。**不修改代码。独立设计，不与 designer-2 交流。** |
| designer-2 | **消费者驱动契约设计**：基于消费者代码（API 调用方、客户端 SDK、前端请求）和业务需求，定义消费者期望的契约——实际使用的字段子集、期望的响应格式、依赖的行为。关注"消费者实际需要什么"。**不修改代码。独立设计，不与 designer-1 交流。** |
| generator | 合并两份契约设计为统一契约定义，解决字段/类型/必填性冲突，生成契约测试代码（Provider 验证测试 + Consumer 桩测试 + 破坏性变更检测用例）。**完成后关闭。** |
| validator | 验证生成的测试套件可编译/可运行，检查测试覆盖率，执行兼容性验证（契约是否与现有代码一致），输出最终报告。**完成后关闭。** |

### 角色生命周期

| 角色 | 启动阶段 | 关闭时机 | 说明 |
|------|---------|---------|------|
| scanner | 阶段一（步骤 3） | 阶段一扫描完成后（步骤 3） | 扫描报告交付后即释放 |
| designer-1 | 阶段一（步骤 3，与 scanner 并行） | 阶段一设计完成后（步骤 5） | 契约设计交付后释放 |
| designer-2 | 阶段一（步骤 3，与 scanner 并行） | 阶段一设计完成后（步骤 5） | 契约设计交付后释放 |
| generator | 阶段二（步骤 6） | 阶段三测试生成后（步骤 9） | 测试套件输出后释放 |
| validator | 阶段四（步骤 10） | 阶段四验证完成后（步骤 12） | 报告确认后释放 |

---

## 契约风格与工具

| 风格 | 适用场景 | 核心工具/格式 | 测试类型 |
|------|---------|-------------|---------|
| **openapi** | REST API，有 OpenAPI/Swagger 规范 | OpenAPI 3.x Schema 验证、Schemathesis、Dredd | Schema 一致性测试、响应格式验证 |
| **pact** | 微服务间 HTTP/消息交互 | Pact 框架（Consumer DSL + Provider Verifier） | Consumer-driven 契约测试 |
| **grpc** | gRPC 服务 | Proto 文件对比、buf breaking、grpc-testing | Proto 兼容性检测、服务契约验证 |
| **auto** | 自动检测 | 根据项目特征自动选择上述之一 | 取决于检测结果 |

---

## 破坏性变更分类

每个变更按严重程度定级：

| 级别 | 含义 | 影响 |
|------|------|------|
| **BREAKING** | 破坏性变更，消费者必须修改 | 删除端点/字段、修改字段类型、修改必填性 |
| **DEPRECATION** | 废弃预警，当前兼容但将来移除 | 标记废弃的端点/字段/参数 |
| **COMPATIBLE** | 兼容性变更，消费者无需修改 | 新增可选字段、新增端点、扩展枚举值 |
| **UNKNOWN** | 无法确定兼容性 | 复杂结构变更、多态类型变更 |

---

## 阶段零：风格选择 + API 扫描

### 步骤 1：解析契约风格与测试范围

Team lead 分析项目和参数：

1. 解析 `--style` 参数，确定契约风格（`auto` 时延迟到 scanner 扫描后决定）
2. 解析 `--scope` 参数，确定测试范围（`provider`/`consumer`/`both`）
3. 阅读项目结构，识别 API 架构类型：
   - REST API 相关文件（路由定义、控制器、OpenAPI 规范）
   - gRPC 相关文件（`.proto` 文件、gRPC 服务注册）
   - GraphQL 相关文件（Schema 定义、Resolver）
   - 消费者代码（API 客户端、HTTP 请求封装、SDK）
   - 现有契约测试（Pact 文件、契约验证配置）
4. 识别服务间依赖关系（上下游服务、外部 API 调用）
5. 输出 API 概览和测试范围清单

### 步骤 2：用户确认测试范围

**标准模式**：向用户展示 API 概览和测试范围，AskUserQuestion 确认：
- 确认契约风格和测试范围
- 调整端点范围（增删特定端点或服务）
- 补充消费者信息或特殊契约要求

**单轮确认模式**：跳过确认，直接进入阶段一。
**完全自主模式**：自动决策，不询问用户，直接进入阶段一。

---

## 阶段一：API 规范扫描 + 双路契约设计

### 步骤 3：启动 scanner 和双 designer

三者并行启动。

**Scanner API 规范扫描**：
1. 扫描项目，发现所有 API 端点：
   - REST：解析路由定义、控制器注解、Express/Flask/Spring 路由
   - gRPC：解析 `.proto` 文件中的 Service/RPC 定义
   - GraphQL：解析 Schema 中的 Query/Mutation/Subscription
2. 提取现有 API 规范文件（OpenAPI YAML/JSON、Proto 文件、GraphQL SDL）
3. 检测 API 版本信息（URL 路径版本、Header 版本、规范文件版本标注）
4. 映射服务依赖关系（哪些服务调用哪些端点）
5. 如有多个版本的规范文件，对比差异，标注变更点
6. 输出**API 规范扫描报告**（含端点清单、Schema、依赖图、版本差异）
7. Scanner 完成后关闭

**双 designer 同时阅读项目**：
- 阅读项目结构（路由、控制器、模型、客户端代码）
- 理解 API 架构和数据流
- 梳理各自负责维度的契约要素
- 各自输出项目 API 概况给 team lead

### 步骤 4：分发 scanner 报告

Team lead 收到 scanner 报告后，将 API 规范数据分发给两位 designer，作为契约设计的基础参考。

Designer 在设计时必须参考 scanner 结果——例如 scanner 发现的端点清单和 Schema 是契约定义的基础数据。

### 步骤 5：独立并行契约设计

两位 designer 各自从不同视角设计契约，**互不交流**。

**Designer-1（提供者契约设计）** — Provider-side Contract：

逐端点输出"契约定义 + 验证规则 + 边界条件"：

| 维度 | 设计内容 | 具体检查项 |
|------|---------|-----------|
| **请求契约** | 输入参数定义 | URL 参数类型和必填性、请求体 Schema（字段名、类型、必填、默认值、枚举约束）、Header 要求（Content-Type、Authorization 格式）、Query 参数约束 |
| **响应契约** | 输出格式定义 | 成功响应 Schema（字段名、类型、嵌套结构）、错误响应格式（状态码、错误码、错误消息结构）、分页格式、空值处理策略 |
| **行为契约** | 接口行为约束 | 幂等性保证（POST/PUT/DELETE 行为）、状态码语义（200/201/204/400/401/403/404/409/500）、并发行为、速率限制响应 |
| **边界条件** | 极端输入处理 | 最大/最小值、空数组/空对象、超长字符串、特殊字符、空请求体、无效 Content-Type |

- 基于 API 实际实现（控制器代码、序列化器、校验逻辑）定义契约
- 记录每个端点：HTTP 方法 + 路径 + 请求 Schema + 响应 Schema + 状态码 + 行为约束

**Designer-2（消费者驱动契约设计）** — Consumer-driven Contract：

逐端点输出"消费者期望 + 使用模式 + 依赖字段"：

| 维度 | 设计内容 | 具体检查项 |
|------|---------|-----------|
| **使用字段** | 消费者实际使用的字段子集 | 消费者代码中实际读取的响应字段（排除未使用字段）、消费者传递的请求参数（排除服务端默认值字段）、字段类型期望（消费者代码中的类型断言/转换） |
| **交互模式** | 消费者实际调用模式 | 调用顺序依赖（如先 login 再 getProfile）、重试策略和超时期望、批量/分页使用模式、错误处理方式（消费者如何处理各类错误码） |
| **兼容性期望** | 消费者对向后兼容的依赖 | 必须存在的字段（消费者无 null 检查直接使用）、必须的响应格式（消费者做了格式假设）、依赖的枚举值范围、依赖的嵌套结构层级 |
| **消费者标识** | 消费者身份和上下文 | 消费者名称/服务名、消费者版本/环境、API 调用场景（用户请求 vs 后台任务 vs Webhook） |

- 基于消费者代码（API 客户端调用、前端请求、下游服务调用）定义期望
- 记录每个端点：消费者名称 + 使用字段 + 期望行为 + 兼容性约束

---

## 阶段二：契约合并

### 步骤 6：启动 generator

两位 designer 设计完成后，启动 generator。Team lead 将以下材料发送给 generator：
- Scanner API 规范扫描报告
- Designer-1 提供者契约设计
- Designer-2 消费者驱动契约设计
- 契约风格（`--style`）和测试范围（`--scope`）

### 步骤 7：合并契约定义

Generator 执行契约合并：

1. **逐端点对齐**：将 designer-1 和 designer-2 的契约定义按端点一一对齐
2. **字段校验**：检查字段名、类型、必填性是否一致
3. **冲突识别**：标注两份设计的差异点
4. **冲突分类**：
   - **可自动解决**：提供者定义更宽松（如提供者返回 10 个字段，消费者只用 5 个）→ 以消费者期望为最小契约
   - **需裁决**：字段类型冲突（提供者定义 `string`，消费者期望 `number`）→ 标注为争议项
5. **统一契约**：输出统一契约定义文件

**共识度计算公式**：
```
共识端点数 = 两位 designer 对同一端点定义完全一致的端点数量
总端点数 = 所有端点去重数量

共识度 = 共识端点数 / 总端点数 × 100%

冲突率 = 存在字段类型/必填性冲突的端点数 / 两位 designer 都覆盖的端点数 × 100%

冲突率 > 50% → 触发熔断，必须暂停问用户
```

### 步骤 8：冲突校验与熔断检查

**契约冲突熔断**：
- 如果两位 designer 对同一端点的字段类型或必填性定义冲突，generator 标注为"争议项"
- 争议端点占比 > 50% → **不可跳过，必须暂停问用户**（熔断机制）

**破坏性变更熔断**：
- 与现有 API 规范对比，如检测到破坏性变更超过 10 个 → **不可跳过，必须暂停问用户**（熔断机制）
- 向用户展示破坏性变更列表，确认是否继续

**无熔断触发**时，generator 输出**统一契约定义**：

```
## 统一契约定义

### 端点统计
- 总端点数: X | 已定义契约: X | 跳过: X
- 提供者契约覆盖: X% | 消费者契约覆盖: X%

### 端点契约列表

#### [POST] /api/v1/users — 状态：一致/冲突已解决/存在争议
  ├─ 请求 Schema: { name: string(required), email: string(required), role?: string }
  ├─ 响应 Schema: { id: number, name: string, email: string, created_at: string }
  ├─ 状态码: 201(success), 400(validation), 409(duplicate)
  ├─ 消费者使用字段: { id, name, email }
  └─ 契约来源: designer-1(提供者) + designer-2(消费者) → 合并

### 破坏性变更检测
1. [BREAKING] /api/v1/users/{id} — 字段 `role` 类型从 string 改为 enum
2. [DEPRECATION] /api/v1/legacy/auth — 端点标记废弃
3. ...

### 争议项（如有）
1. 端点:字段 — designer-1 定义: X / designer-2 期望: Y — generator 最终裁决: Z — 理由
```

---

## 阶段三：测试生成

### 步骤 9：生成契约测试套件

Generator 基于统一契约定义生成测试代码：

**按 `--style` 生成对应格式**：

| 风格 | Provider 测试 | Consumer 测试 | 破坏性变更检测 |
|------|-------------|-------------|-------------|
| **openapi** | Schema 验证测试（响应符合 OpenAPI Schema） | 请求构造测试（按消费者期望发送请求） | OpenAPI diff（字段变更检测） |
| **pact** | Provider Verifier 测试（验证 Pact 文件） | Consumer DSL 测试（定义交互期望） | Pact 版本对比 |
| **grpc** | Proto 服务实现验证 | gRPC 客户端桩测试 | buf breaking（Proto 兼容性检测） |

**按 `--scope` 生成范围**：
- `provider`：仅生成 Provider 验证测试
- `consumer`：仅生成 Consumer 桩测试
- `both`（默认）：两者都生成

**测试套件结构**：
```
contracts/
├── definitions/           # 统一契约定义文件
│   ├── openapi-contract.yaml  # 或 pact/*.json 或 proto/*.proto
│   └── breaking-changes.md
├── provider/              # Provider 验证测试
│   ├── contract.provider.test.{ext}
│   └── fixtures/
├── consumer/              # Consumer 桩测试
│   ├── contract.consumer.test.{ext}
│   └── stubs/
└── reports/               # 测试报告
    └── contract-test-report.md
```

Generator 完成后关闭。

---

## 阶段四：兼容性验证

### 步骤 10：启动 validator

Team lead 将以下材料发送给 validator：
- 统一契约定义
- 生成的测试套件
- 破坏性变更列表
- 项目技术栈信息
- 输出语言（`--lang`）

### 步骤 11：验证与报告生成

Validator 执行兼容性验证：

1. **语法验证**：检查生成的测试代码是否可编译/可解析
2. **契约一致性**：验证测试代码是否正确反映统一契约定义
3. **覆盖率分析**：计算端点覆盖率、字段覆盖率、状态码覆盖率
4. **运行验证**（如环境允许）：尝试运行测试套件，收集通过/失败结果
5. **兼容性评估**：基于破坏性变更检测结果，评估当前 API 的向后兼容性

Validator 生成**契约测试报告**：

```
## API 契约测试报告

### 元信息
- 生成时间：YYYY-MM-DD HH:mm:ss
- 团队名称：team-contract-test-{YYYYMMDD-HHmmss}
- 执行模式：标准模式 / 单轮确认模式 / 完全自主模式
- 输出语言：zh / en
- 契约风格：openapi / pact / grpc
- 测试范围：provider / consumer / both
- 测试参数：--style=[style 值] --scope=[scope 值]

### 1. API 概述
- 扫描日期：YYYY-MM-DD
- API 架构：REST / gRPC / GraphQL
- 技术栈：[语言/框架]
- 端点总数：X 个
- 服务依赖数：X 个

### 2. 契约覆盖总览
| 维度 | 覆盖率 | 详情 |
|------|--------|------|
| 端点覆盖率 | X% | X/Y 个端点已定义契约 |
| 字段覆盖率 | X% | X/Y 个字段已纳入验证 |
| 状态码覆盖率 | X% | X/Y 个状态码已测试 |
| Provider 测试数 | X 个 | [测试文件路径] |
| Consumer 测试数 | X 个 | [测试文件路径] |

### 3. 破坏性变更检测
| # | 级别 | 端点 | 变更描述 | 影响范围 | 建议 |
|---|------|------|---------|---------|------|
| 1 | BREAKING | /api/v1/users/{id} | 字段 role 类型变更 | consumer-A, consumer-B | 版本化或渐进迁移 |
| 2 | DEPRECATION | /api/v1/legacy/auth | 端点废弃 | consumer-C | 迁移到 /api/v2/auth |

### 4. 契约冲突解决记录
| # | 端点 | 冲突点 | designer-1 定义 | designer-2 期望 | 最终裁决 | 理由 |
|---|------|--------|----------------|----------------|---------|------|
| 1 | /api/users | role 字段必填性 | optional | required | required | 消费者强依赖 |

### 5. 测试套件清单
| 文件路径 | 类型 | 端点数 | 验证状态 |
|---------|------|--------|---------|
| contracts/provider/contract.provider.test.ts | Provider | X | 语法通过/运行通过 |
| contracts/consumer/contract.consumer.test.ts | Consumer | X | 语法通过/运行通过 |

### 6. 兼容性评估
- 向后兼容性评级：安全/警告/危险
- 破坏性变更数：X 个
- 废弃预警数：X 个
- 兼容性变更数：X 个
- 建议版本策略：[维持当前版本/升级次版本/升级主版本]

### 7. 改进建议
- 短期（1-2 天）：[紧急破坏性变更处理]
- 中期（1-2 周）：[契约测试 CI 集成]
- 长期（持续）：[契约驱动开发流程建设]
```

### 步骤 12：用户确认报告

Team lead 向用户展示契约测试报告摘要：
- 契约覆盖总览
- 破坏性变更统计
- 测试套件位置
- 兼容性评估

AskUserQuestion 确认：
- 确认报告，保存并结束
- 要求补充特定端点的契约测试
- 调整破坏性变更的处理策略

**单轮确认模式**：最终报告必须经用户确认。
**完全自主模式**：自动决策，不询问用户。

Validator 完成后关闭。

---

## 收尾：保存报告与清理

### 步骤 13：保存报告

Team lead 按 `--lang` 指定的语言保存最终报告：

1. 将完整契约测试报告保存到项目目录（如 `contract-test-report-YYYYMMDD.md`）
2. 保存契约数据到 `~/.gstack/data/{slug}/contract-test.json`（供跨 skill 消费）：

```json
{
  "style": "openapi",
  "scope": "both",
  "date": "YYYY-MM-DD",
  "endpoints": {
    "total": 25,
    "covered": 22,
    "coverage": 88
  },
  "breaking_changes": {
    "breaking": 2,
    "deprecation": 3,
    "compatible": 8,
    "unknown": 1
  },
  "tests": {
    "provider": 22,
    "consumer": 18,
    "total": 40
  },
  "compatibility": "warning",
  "conflicts_resolved": 3,
  "consensus_rate": 85
}
```

3. 向用户输出报告保存路径和测试总结：

```
## 契约测试完成

### 测试总结
- 契约风格：[openapi/pact/grpc]
- 测试范围：[provider/consumer/both]
- 端点覆盖率：X%（X/Y 个端点）
- 生成测试数：Provider X 个 + Consumer X 个 = 总计 X 个
- 破坏性变更：BREAKING X 个 / DEPRECATION X 个
- 兼容性评级：[安全/警告/危险]
- 报告路径：[文件路径]
- 测试套件路径：contracts/
- 契约数据：~/.gstack/data/{slug}/contract-test.json

### 关键发现
1. [最严重破坏性变更概述]
2. ...

### 建议下一步
1. 修复 BREAKING 级别变更或制定版本迁移计划
2. 将契约测试集成到 CI/CD 管道
3. 通知受影响的消费者团队
4. 定期运行 /team-contract-test 检测新增变更

### 自主决策汇总（单轮确认模式/完全自主模式）
| 决策节点 | 决策内容 | 理由 |
|---------|---------|------|
| [阶段/步骤] | [决策描述] | [理由] |

### 附录：契约共识说明
- designer-1 定义端点数：[数量] 个（提供者契约）
- designer-2 定义端点数：[数量] 个（消费者契约）
- scanner 发现端点数：[数量] 个
- 共识端点数：[数量] 个（共识度 = XX%）
- 冲突端点数：[数量] 个（冲突率 = XX%）
- 争议项：[数量] 个
  - [端点:字段] — designer-1 定义: X / designer-2 期望: Y → generator 裁决: Z（理由）
- 仅 designer-1 覆盖：[端点列表]
- 仅 designer-2 覆盖：[端点列表]
- scanner 发现但未纳入契约：[端点列表]
```

### 步骤 13.5：跨团队衔接建议（可选）

Team lead 根据测试结果向用户建议后续动作：
- **发现破坏性变更需要修复**：建议运行 `/team-dev` 启动研发团队实施修复
- **API 设计存在架构缺陷**：建议运行 `/team-api-design` 评估 API 重设计
- **契约测试需要集成 CI**：建议运行 `/team-release` 配置契约测试管道
- **发现安全相关的 API 问题（认证/授权缺陷）**：建议运行 `/team-security` 进行安全审计
- 用户可选择执行或跳过，不强制。

### 步骤 14：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 核心原则

- **双视角设计**：提供者和消费者视角独立设计契约，确保 API 既符合实现又满足需求
- **消费者驱动**：以消费者实际使用为最小契约基线，避免过度契约化
- **破坏性变更零容忍**：所有破坏性变更必须明确标注、评估影响、制定迁移方案
- **可执行性**：生成的测试必须可编译、可运行，不生成伪代码
- **渐进式**：从核心端点开始，逐步扩展覆盖范围，不强求一次全覆盖
- **版本感知**：契约定义关联 API 版本，支持多版本共存场景
- **证据驱动**：每个契约定义必须有代码级证据支撑，不做假设

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| 无 API 规范文件 | Scanner 基于代码推断端点和 Schema，标注"规范由代码推断，非正式定义" |
| API 端点过多（> 200） | Scanner 分批处理，designer 聚焦核心端点，标注未覆盖端点 |
| 消费者代码不可见（外部服务） | Designer-2 基于文档/规范推断消费者期望，标注"消费者行为为推断" |
| 两位 designer 契约冲突率 > 50% | 触发熔断，暂停问用户裁决争议端点 |
| 破坏性变更超过 10 个 | 触发熔断，暂停向用户确认处理策略 |
| gRPC Proto 文件无法解析 | Scanner 标注"Proto 解析失败"，尝试基于 gRPC 反射获取信息 |
| 测试框架未安装/版本不兼容 | Generator 生成独立可运行的测试文件，附安装指引 |
| 项目无 Git 历史（无法做版本对比） | 仅生成当前版本契约，跳过破坏性变更检测，标注"无历史版本对比" |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前步骤恢复 |
| 端点认证要求无法满足 | Validator 标注"该端点未验证运行时行为"，仅做静态契约验证 |

---

## 需求

$ARGUMENTS
