---
name: team-api-design
description: 启动一个 API 设计团队（researcher/designer×2/reviewer/documenter），通过需求分析+双设计师独立设计+专家评审+文档生成，输出高质量 API 定义和标准化文档（OpenAPI/Protobuf/GraphQL Schema）。使用方式：/team-api-design [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--style=rest|grpc|graphql] [--lang=zh|en] API 需求描述
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--style=rest|grpc|graphql] [--lang=zh|en] API 需求描述
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
- `--style=rest|grpc|graphql`：API 风格（默认 `rest`）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后将标志从 API 需求描述中移除。

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 需求确认 + 设计分歧仲裁 + 评审结果确认 + 最终文档确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅最终文档确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下条件节点自动决策规则：
- **API 风格不确定** → team lead 根据项目特征自行判断，在最终文档中说明
- **两位 designer 分歧** → reviewer 标注分歧，team lead 综合论证后裁决，收尾时汇总
- **分歧超过 50%** → **不可跳过，必须暂停问用户**（熔断机制）
- **reviewer 否决设计** → **不可跳过，必须暂停问用户**（熔断机制）
- **现有 API 存在兼容性约束** → researcher 识别约束条件，designer 在设计中保持兼容
- **`--style` 参数处理**：如果用户指定了 `--style`，所有设计和文档按指定风格输出；未指定时 team lead 根据项目技术栈推断

完全自主模式下：所有节点均自动决策，不询问用户。仅熔断机制（分歧超过 50%、reviewer 否决设计）仍然生效，触发时必须暂停。

使用 TeamCreate 创建 team（名称格式 `team-api-design-{YYYYMMDD-HHmmss}`，如 `team-api-design-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

## 流程概览

```
阶段零  需求分析 → 解析 API 需求，确定 API 风格，识别现有 API 约束
         ↓
阶段一  现状调研 → researcher 分析现有 API 和代码结构 → 输出现状分析 + 设计约束
         ↓
阶段二  双路设计 → designer-1 独立设计 + designer-2 独立设计（互不交流）
         ↓
阶段三  设计评审 → team lead 合并设计方案 → reviewer 多维评审 → 用户确认
         ↓
阶段四  文档生成 → documenter 生成标准化 API 文档 + 示例代码
         ↓
阶段五  收尾 → 保存文档 + 清理团队
```

## 角色定义

| 角色 | 职责 |
|------|------|
| researcher | 分析现有 API（如有）、项目代码结构、行业 API 最佳实践。输出现状分析报告和设计约束清单。**只做调研分析，不做 API 设计。** **阶段一完成后关闭。** |
| designer-1 | 基于 researcher 的调研结果，独立设计完整 API 方案——端点/接口定义、请求响应格式、错误处理、认证方案。**独立设计阶段不与 designer-2 交流。** **存活至阶段三评审修改完成后关闭。** |
| designer-2 | 同 designer-1 的职责，独立执行相同设计任务。**独立设计阶段不与 designer-1 交流。** **存活至阶段三评审修改完成后关闭。** |
| reviewer | 从一致性、易用性、安全性、性能、可扩展性、文档完整性六个维度评审合并后的 API 设计。**只做评审，不做设计，不生成最终文档。** 严重问题必须标注为"否决"升级 team lead。**阶段三评审完成后关闭。** |
| documenter | 基于评审通过的 API 设计，生成标准化文档（OpenAPI/Protobuf/GraphQL Schema）和使用示例。**不做设计判断，不修改 API 定义。** **阶段四完成后关闭。** |

---

## 阶段零：需求分析

### 步骤 1：解析 API 需求

Team lead 解析用户输入的 API 需求描述，提取：
- 业务领域和核心资源/实体
- API 消费方（前端/移动端/第三方/内部服务）
- 功能需求列表（CRUD、业务操作、查询需求）
- 非功能需求（性能要求、并发量、安全级别）
- 版本要求（是否需要兼容已有 API）

### 步骤 2：确定 API 风格

Team lead 根据 `--style` 参数或项目特征确定 API 风格：

| 场景 | 推荐风格 |
|------|---------|
| 面向前端/第三方的公开 API | REST |
| 内部微服务间高性能通信 | gRPC |
| 数据关系复杂、前端按需取数据 | GraphQL |
| 用户指定 `--style` | 按指定风格 |

**标准模式**：向用户展示需求摘要 + 风格建议，AskUserQuestion 确认
**单轮确认模式**：team lead 自行决定，收尾汇总时说明
**完全自主模式**：自动决策，不询问用户

---

## 阶段一：现状调研

### 步骤 3：启动 researcher

Team lead 启动 researcher，指示其调研以下内容：

**现有 API 分析**（如有）——researcher 具体操作方法：
- 搜索 OpenAPI/Swagger 规范文件：`Glob("**/openapi*.{yaml,yml,json}", "**/swagger*.{yaml,yml,json}")`
- 搜索路由定义文件：`Grep("router|route|app\.(get|post|put|delete|patch)|@(Get|Post|Put|Delete|Patch|RequestMapping)", type="代码文件")` 定位所有端点
- 搜索 Protobuf 定义：`Glob("**/*.proto")` 分析 service/rpc 定义
- 搜索 GraphQL Schema：`Glob("**/*.graphql", "**/*.gql")` 或 `Grep("type Query|type Mutation|@Resolver")`
- 从路由文件中提取：现有端点清单、URL 命名风格、HTTP 方法使用
- 从请求/响应模型中提取：数据格式、字段命名风格（camelCase/snake_case）
- 搜索认证中间件：`Grep("auth|jwt|token|bearer|oauth|passport|guard", type="代码文件")`
- 搜索错误处理：`Grep("error|exception|HttpException|ApiError|status\(4[0-9]{2}\)|status\(5[0-9]{2}\)", type="代码文件")`
- 搜索分页模式：`Grep("page|limit|offset|cursor|pageSize|page_size", type="代码文件")`

**项目代码结构分析**——researcher 具体操作方法：
- 数据模型/实体定义：`Grep("@Entity|@Table|@Model|model |class.*Model|Schema\(|mongoose\.Schema", type="代码文件")` 或搜索 `models/`、`entities/`、`schemas/` 目录
- 数据库 Schema：`Glob("**/migrations/**", "**/migrate/**")` 查找迁移文件；`Grep("CREATE TABLE|ALTER TABLE", type="sql")` 查找 SQL 定义
- 中间件和拦截器：`Grep("middleware|interceptor|filter|guard|@Middleware|app\.use\(", type="代码文件")`
- 框架路由配置：`Glob("**/routes/**", "**/router/**", "**/controllers/**")` 定位路由和控制器目录

**行业最佳实践参考**：
- 同领域主流 API 设计模式
- 该技术栈的 API 设计惯例

### 步骤 4：收集调研报告

Researcher 输出**现状分析报告**，包含：
- 现有 API 清单和规范总结（如有）
- 数据模型和实体关系
- 设计约束清单（必须兼容的现有规范、框架限制等）
- 最佳实践建议

Team lead 确认收到报告后，关闭 researcher，进入阶段二。

---

## 阶段二：双路设计

### 步骤 5：启动 designer-1 和 designer-2

两者并行启动。Team lead 将 researcher 的调研报告分发给两位 designer，作为设计的基准输入。

**重要**：Team lead 必须确保两位 designer 不互相看到对方的设计方案。

每位 designer 独立输出完整的 API 设计方案，包含：

**REST 风格**：
1. **资源建模**：核心资源定义、URL 路径设计、资源关系
2. **端点清单**：HTTP 方法 + URL + 描述 + 请求体/响应体
3. **请求/响应格式**：字段定义、数据类型、必填/可选
4. **错误处理**：错误码定义、错误响应格式
5. **分页/排序/过滤**：查询参数设计
6. **认证授权**：认证方式、权限模型
7. **版本控制**：版本策略（URL/Header/Query）
8. **幂等性设计**：哪些操作需要幂等、实现方式

**gRPC 风格**：
1. **Service 定义**：服务划分、RPC 方法清单
2. **Message 定义**：请求/响应消息结构
3. **流式设计**：Unary/Server-stream/Client-stream/Bidirectional
4. **错误处理**：Status Code + 错误详情
5. **拦截器设计**：认证、日志、限流
6. **Proto 文件组织**：包结构、导入关系

**GraphQL 风格**：
1. **Type 定义**：Object Type、Input Type、Enum
2. **Query 设计**：查询字段、参数、嵌套关系
3. **Mutation 设计**：变更操作、输入输出
4. **Subscription 设计**（如需）：实时推送
5. **错误处理**：自定义错误类型
6. **认证授权**：Directive 或 Resolver 级别控制

### 步骤 6：收集设计方案

两位 designer 完成后各自向 team lead 发送设计方案。Team lead 确认收到全部 2 份方案后，进入阶段三。

---

## 阶段三：设计评审

### 步骤 7：Team lead 合并设计方案

Team lead 逐项对比两份设计方案，输出合并结果：

| 对比结果 | 处理方式 |
|---------|---------|
| **一致设计** | 直接采纳，标记为"共识" |
| **互补设计**（A 覆盖了 B 没考虑的场景，或反之） | 合并最优方案，标记为"互补" |
| **差异设计**（本质相同，细节不同） | 选择更优方案，标记为"共识" |
| **冲突设计**（对同一接口有不同设计） | 标注为"待仲裁"，记录双方方案 |

输出：
1. **共识清单**：双方一致的 API 设计
2. **互补清单**：一方独有的有价值设计
3. **冲突清单**：矛盾之处及双方方案对比
4. **共识度评估**：共识度 = (共识接口数 + 互补接口数) / 总接口数(去重并集) x 100%

### 步骤 8：检查熔断条件

如果共识度 < 50%（冲突占比超过一半）：
- **必须暂停**，team lead 向用户报告情况
- 可能原因：需求描述不够明确、设计约束理解不一致
- 建议：澄清需求或缩小设计范围

共识度 >= 50%：继续下一阶段。

### 步骤 9：启动 reviewer 评审

Team lead 启动 reviewer，将合并后的 API 设计方案和 researcher 的调研报告传递给 reviewer。

Reviewer 从以下六个维度进行评审，每个维度独立评分（1-5 分）：

| 维度 | 权重 | 评审要点 |
|------|------|---------|
| 一致性 | 20% | URL/命名风格统一、字段命名规范、数据格式一致 |
| 易用性 | 20% | 接口直观易理解、参数设计合理、返回结构清晰 |
| 安全性 | 15% | 认证授权完备、输入校验、敏感数据处理 |
| 性能 | 15% | 批量操作支持、字段过滤、N+1 问题规避 |
| 可扩展性 | 15% | 版本兼容、字段可扩展、向后兼容设计 |
| 文档完整性 | 15% | 接口描述完整、示例充分、边界情况覆盖 |

**API 设计检查项**（reviewer 必须逐项验证）：

1. **命名一致性**：URL 风格（kebab-case/snake_case）、字段命名（camelCase/snake_case）全局统一
2. **RESTful 语义正确性**：HTTP 方法与操作语义匹配、状态码使用正确
3. **错误响应格式统一**：所有接口使用相同的错误响应结构
4. **分页/过滤/排序设计**：列表接口支持标准化的分页、过滤和排序参数
5. **认证授权方案**：所有接口有明确的认证要求和权限定义
6. **版本控制策略**：版本号位置和升级策略明确
7. **幂等性设计**：写操作的幂等性保证方式明确
8. **性能考量**：批量操作接口、字段过滤（sparse fieldsets）、合理的默认分页大小

Reviewer 输出**评审报告**，包含：
- 各维度评分和加权总分
- 每个检查项的通过/不通过/建议优化
- 问题清单（按严重程度：否决/重要/建议）
- 优化建议

**评审结果判定**：

| 加权总分 | 判定 | 处理 |
|---------|------|------|
| >= 4.0 | 通过 | 直接进入文档生成 |
| 3.0 - 3.9 | 有条件通过 | designer 按评审意见修改后进入文档生成 |
| < 3.0 | 否决 | **触发熔断**，暂停问用户 |

### 步骤 10：处理评审结果

**通过（>= 4.0）**：直接进入阶段四。

**有条件通过（3.0 - 3.9）**：
- Team lead 将评审意见分发给 designer-1 和 designer-2
- Designer 按意见修改冲突/问题接口
- Team lead 合并修改结果，发给 reviewer 进行快速复核
- Reviewer 确认问题已解决后进入阶段四

**否决（< 3.0）**：
- **必须暂停**，team lead 向用户展示评审报告
- 说明否决原因和主要问题
- 建议：调整需求范围或修改设计约束

### 步骤 11：用户确认设计方案

**标准模式**：向用户展示合并后的 API 设计摘要 + 评审结果，AskUserQuestion 确认：
- 接受设计方案
- 需要修改某些接口
- 需要增补某些功能

**单轮确认模式**：team lead 根据评审结果自行推进，收尾时汇总决策
**完全自主模式**：自动决策，不询问用户

---

## 阶段四：文档生成

### 步骤 12：启动 documenter

Team lead 启动 documenter，将以下内容传递：
- Researcher 的现状分析报告
- 评审通过的最终 API 设计方案
- Reviewer 的评审报告
- `--style` 参数和 `--lang` 参数

Documenter 按指定风格和语言生成标准化 API 文档。

### 步骤 13：文档输出格式

**REST 风格 — OpenAPI 3.0 YAML + curl 示例**：

```yaml
openapi: 3.0.3
info:
  title: [API 名称]
  version: [版本号]
paths:
  /resource:
    get:
      summary: [操作描述]
      parameters: [分页/过滤/排序参数]
      responses:
        '200': { description: 成功, content: { application/json: { schema: ..., example: ... } } }
        '400': { $ref: '#/components/responses/BadRequest' }
components:
  schemas:
    Error: { type: object, properties: { code: string, message: string, details: array } }
  securitySchemes:
    BearerAuth: { type: http, scheme: bearer }
```

附带 curl 示例（列表查询、创建、更新、删除各一个）。

**gRPC 风格 — .proto 文件 + 使用示例**：

```protobuf
syntax = "proto3";
package [包名];

service [服务名] {
  rpc Create[资源]([Request]) returns ([资源]);
  rpc Get[资源]([Request]) returns ([资源]);
  rpc List[资源]([ListRequest]) returns ([ListResponse]);
  rpc Update[资源]([Request]) returns ([资源]);
  rpc Delete[资源]([Request]) returns (google.protobuf.Empty);
}

message [资源] { string id = 1; string name = 2; google.protobuf.Timestamp created_at = 3; }
message [ListRequest] { int32 page_size = 1; string page_token = 2; string filter = 3; }
message [ListResponse] { repeated [资源] items = 1; string next_page_token = 2; int32 total_count = 3; }
```

附带 grpcurl 或客户端代码示例。

**GraphQL 风格 — Schema + 查询示例**：

```graphql
type Query {
  resource(id: ID!): Resource
  resources(filter: ResourceFilter, pagination: Pagination): ResourceConnection!
}
type Mutation {
  createResource(input: CreateResourceInput!): Resource!
  updateResource(id: ID!, input: UpdateResourceInput!): Resource!
  deleteResource(id: ID!): Boolean!
}
type Resource { id: ID!; name: String!; createdAt: DateTime! }
type ResourceConnection { edges: [ResourceEdge!]!; pageInfo: PageInfo!; totalCount: Int! }
```

附带 Query/Mutation 示例各一个。

Documenter 同时生成以下附录，附在文档末尾：

**附录 A: 设计共识说明**：
```markdown
## 附录 A: 设计共识说明

> 共识度：XX% | 共识接口数：X | 互补接口数：X | 冲突接口数：X

### 共识设计
[两位设计师一致的 API 设计列表]

### 互补设计
| 来源 | 接口/设计 | 采纳理由 |
|------|----------|---------|
| designer-1 独有 | [描述] | [理由] |
| designer-2 独有 | [描述] | [理由] |

### 分歧点及仲裁结果
| 分歧点 | designer-1 方案 | designer-2 方案 | 最终采纳 | 理由 |
|--------|---------------|---------------|---------|------|
| [描述] | [方案] | [方案] | [结论] | [理由] |
```

**附录 B: 自主决策汇总**（仅 `--auto` 或 `--once` 模式时生成）：
```markdown
## 附录 B: 自主决策汇总

| 决策节点 | 决策内容 | 理由 | 备选方案 |
|---------|---------|------|---------|
| API 风格选择 | [选择了 REST/gRPC/GraphQL] | [理由] | [其他可选风格] |
| 设计分歧仲裁 | [裁决内容] | [理由] | [被否决的方案] |
| ... | ... | ... | ... |
```

Documenter 输出完整文档后发送给 team lead。

### 步骤 14：用户确认文档

Team lead 向用户展示文档摘要：
- API 风格和版本
- 接口数量和核心资源
- 评审总分和各维度得分
- 文档包含内容（Schema 文件 + 示例）

AskUserQuestion 确认：
- 接受文档
- 需要补充某些接口
- 需要调整某些定义

**单轮确认模式**：必须经用户确认。
**完全自主模式**：自动决策，不询问用户，收尾时汇总。

---

## 阶段五：收尾

### 步骤 15：保存文档

将最终 API 文档保存到项目的 `docs/api/` 目录：
- REST：`openapi-spec-YYYY-MM-DD.yaml` + `api-examples-YYYY-MM-DD.md`
- gRPC：`[service].proto` + `grpc-examples-YYYY-MM-DD.md`
- GraphQL：`schema-YYYY-MM-DD.graphql` + `graphql-examples-YYYY-MM-DD.md`
- API 设计说明：`api-design-notes-YYYY-MM-DD.md`
- 如果目录不存在，创建之

### 步骤 16：最终总结

Team lead 按 `--lang` 指定的语言向用户输出：
- 设计了什么（API 名称、风格、接口数量）
- 核心资源和主要端点/接口
- 评审结果（总分、各维度得分）
- 共识度和设计分歧处理情况
- 文档保存位置和文件清单
- **（单轮确认模式/完全自主模式）自动决策汇总**：列出所有自动决策的节点、决策内容和理由

### 步骤 16.5：跨团队衔接建议（可选）

Team lead 根据 API 设计结果向用户建议后续动作：
- **API 设计完成后需实现**：建议运行 `/team-refactor` 按 API 定义重构现有代码
- **API 需安全审查**：建议运行 `/team-review` 对 API 设计和实现做全面审查
- **API 需文档更新到知识库**：建议运行 `/team-onboard` 更新项目入职文档
- **API 涉及成本敏感接口**：建议运行 `/team-cost` 评估 API 调用成本影响
- 用户可选择执行或跳过，不强制。

### 步骤 17：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 核心原则

- **调研先行**：researcher 先分析现有 API 和代码结构，为 designer 提供设计约束和数据锚点
- **独立设计**：两位 designer 必须完全独立工作，不互相看到对方方案，确保设计多样性
- **职责分离**：reviewer 只做评审，documenter 只做文档生成，不交叉职责
- **多维评审**：reviewer 从一致性、易用性、安全性、性能、可扩展性、文档完整性六个维度全面评审
- **标准输出**：文档严格遵循 OpenAPI 3.0 / Protobuf / GraphQL Schema 标准格式
- **兼容优先**：存在现有 API 时，设计必须考虑向后兼容和平滑迁移
- **安全内建**：认证授权、输入校验、敏感数据处理在设计阶段就纳入考量
- **幂等可靠**：写操作必须明确幂等性保证方式，确保 API 的可靠性

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| 需求描述过于模糊 | Team lead 向用户追问核心资源、消费方、功能清单 |
| 项目无现有 API | Researcher 跳过现有 API 分析，聚焦代码结构和数据模型 |
| 项目无代码（纯需求设计） | Researcher 聚焦行业最佳实践和需求分析，跳过代码调研 |
| 两位 designer 设计分歧极大（共识度 < 50%） | 触发熔断，暂停问用户确认设计方向 |
| Reviewer 否决设计（总分 < 3.0） | 触发熔断，暂停问用户确认是否调整需求或约束 |
| 现有 API 存在严重设计缺陷 | Researcher 在约束清单中标注，designer 设计兼容迁移方案 |
| API 接口数量过多（> 50 个端点） | Designer 按资源分组设计，documenter 分文件输出 |
| 风格切换（如从 REST 改 gRPC） | Team lead 重新分配设计任务，从阶段二重新开始 |
| Documenter 无法确定文档细节 | 在文档中标注"待补充"，team lead 在总结中说明 |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前阶段恢复 |

---

## 需求

$ARGUMENTS
