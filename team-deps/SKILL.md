---
name: team-deps
description: 启动一个依赖健康检查团队（dep-scanner/analyzer×2/reporter），通过自动化扫描+双路独立分析（CVE严重性+版本陈旧度）+合并报告，输出依赖健康报告、漏洞清单和升级建议。使用方式：/team-deps [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--scope=direct|all] [--fix (自动生成安全升级PR)] [--lang=zh|en] 项目路径或依赖审计需求
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--scope=direct|all] [--fix (自动生成安全升级PR)] [--lang=zh|en] 项目路径或依赖审计需求
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
- `--scope=direct|all`：扫描范围（`direct` 仅直接依赖，`all` 含传递依赖，默认 `all`）
- `--fix`：自动生成安全升级命令/PR（仅针对 patch/minor 级别更新，不含 breaking change）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后将标志从审计需求描述中移除。

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 扫描范围确认 + 最终报告确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅最终报告确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下自动决策规则：
- **CVE 严重性判定不确定** → 对应 analyzer 自行判断，报告中说明
- **两位 analyzer 对同一依赖的风险定级差异过大（相差 2 级及以上）** → **不可跳过，必须暂停问用户**（熔断机制）
- **Critical CVE 超过 10 个** → **不可跳过，必须暂停问用户**（熔断机制）
- **审计工具运行失败** → dep-scanner 标注"该工具不可用"，不阻塞流程
- **发现大量传递依赖（>500）** → dep-scanner 自行决定是否全量纳入

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效（定级差异过大、Critical CVE 超过 10 个时仍必须暂停问用户）。

使用 TeamCreate 创建 team（名称格式 `team-deps-{YYYYMMDD-HHmmss}`，如 `team-deps-20260308-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

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
阶段零  包管理器检测 → 扫描项目中所有包管理器和锁文件，确认依赖生态
         ↓
阶段一  自动化扫描 + 双路独立分析（并行）
         ├─ dep-scanner：运行各生态审计工具，收集 CVE 和依赖元数据
         ├─ analyzer-1：CVE 严重性分析（CVSS 评分、可利用性、代码路径可达性）
         └─ analyzer-2：版本陈旧度分析（落后版本距离、Breaking Change 风险、维护者健康度）
         ↓
阶段二  合并 & 排序 → reporter 合并双路分析，生成优先级排序的统一报告
         → 熔断检查（Critical > 10 / 分析差异过大）
         ↓
阶段三  可选自动修复 → 生成安全升级命令/PR（仅 patch/minor 更新）
         ↓
阶段四  收尾 → 保存报告 + 清理团队
```

## 角色定义

| 角色 | 职责 |
|------|------|
| dep-scanner | 检测项目中所有包管理器和锁文件，运行各生态审计工具（npm audit、pip-audit、cargo-audit、govulncheck、bundle-audit、trivy 等），收集 CVE 数据和依赖元数据（版本、发布日期、许可证）。**仅在扫描阶段工作，完成后关闭。** |
| analyzer-1 | **CVE 严重性分析**：按 CVSS 评分排序、评估可利用性（是否有公开 PoC、是否远程可利用）、分析漏洞代码路径是否在项目中实际可达。输出结构化 CVE 风险清单。**独立分析，不与 analyzer-2 交流。** |
| analyzer-2 | **版本陈旧度分析**：计算每个依赖落后最新稳定版的距离（patch/minor/major 数）、评估 Breaking Change 风险、检查维护者健康度（最后提交时间、维护者数量、issue 响应速度）、识别许可证合规问题。输出结构化陈旧度风险清单。**独立分析，不与 analyzer-1 交流。** |
| reporter | 合并两份分析报告，去重、交叉关联（同一依赖的 CVE 风险 + 陈旧度风险）、生成优先级排序的统一依赖健康报告，含可操作的升级建议。**完成后关闭。** |

### 角色生命周期

| 角色 | 启动阶段 | 关闭时机 | 说明 |
|------|---------|---------|------|
| dep-scanner | 阶段一（步骤 3） | 阶段一扫描完成后（步骤 3） | 扫描数据交付后即释放 |
| analyzer-1 | 阶段一（步骤 4，与 analyzer-2 并行） | 阶段一分析完成后（步骤 5） | CVE 分析报告交付后释放 |
| analyzer-2 | 阶段一（步骤 4，与 analyzer-1 并行） | 阶段一分析完成后（步骤 5） | 陈旧度分析报告交付后释放 |
| reporter | 阶段二（步骤 6） | 阶段二报告生成后（步骤 9） | 统一报告输出后释放 |

---

## 依赖风险严重程度定级

每个依赖风险按严重程度定级：

| 级别 | 含义 | 是否必须处理 |
|------|------|-------------|
| **Critical** | 已知被利用的 RCE/提权 CVE、代码路径可达、无安全替代版本 | 必须立即升级 |
| **High** | CVSS ≥ 7.0 的 CVE、依赖已停止维护且无替代方案、许可证严重冲突 | 必须升级 |
| **Medium** | CVSS 4.0-6.9 的 CVE、落后 major 版本且有已知安全修复、维护者不活跃 | 建议升级 |
| **Low** | CVSS < 4.0 的 CVE、落后多个 minor 版本但无安全影响、维护者响应慢 | 可选升级 |
| **Info** | 最佳实践建议（如锁文件缺失、依赖源未锁定、可用的性能优化版本） | 可选 |

---

## 包管理器检测矩阵

| 包管理器 | 清单文件 | 锁文件 | 审计工具 | 输出 |
|---------|---------|--------|---------|------|
| npm/yarn/pnpm | package.json | package-lock.json / yarn.lock / pnpm-lock.yaml | npm audit / yarn audit / pnpm audit | CVE 列表 + 依赖树 |
| pip | requirements.txt / pyproject.toml / setup.py | requirements.txt (pinned) | pip-audit / safety | CVE 列表 + 版本信息 |
| cargo | Cargo.toml | Cargo.lock | cargo-audit | RustSec 公告 |
| go | go.mod | go.sum | govulncheck | Go 漏洞数据库匹配 |
| bundler | Gemfile | Gemfile.lock | bundle-audit / bundler-audit | Ruby CVE 列表 |
| maven | pom.xml | — | dependency-check (OWASP) / trivy | CVE 列表 |
| gradle | build.gradle / build.gradle.kts | — | dependency-check (OWASP) / trivy | CVE 列表 |
| composer | composer.json | composer.lock | composer audit / local-php-security-checker | CVE 列表 |
| nuget | *.csproj / packages.config | packages.lock.json | dotnet list package --vulnerable | CVE 列表 |
| swift | Package.swift | Package.resolved | — (手工分析) | 版本对比 |

**如果某工具未安装或无法运行**：dep-scanner 标注"该工具不可用"，不阻塞流程。

---

## 分析维度分配

双 analyzer 按各自负责的维度独立分析，reporter 按权重合并为依赖健康评分。

| 维度 | 权重 | 负责人 | 分析内容 |
|------|------|--------|---------|
| CVE 漏洞严重性 | 30% | analyzer-1 | CVSS 评分、漏洞类型（RCE/提权/信息泄露/DoS）、是否有公开 PoC、是否被在野利用 |
| 代码路径可达性 | 20% | analyzer-1 | 漏洞所在函数/模块是否被项目实际引用、调用链分析、运行时是否可触达 |
| 版本落后程度 | 15% | analyzer-2 | 落后 patch/minor/major 数量、最新版本发布日期、changelog 中的安全修复 |
| Breaking Change 风险 | 10% | analyzer-2 | 升级到安全版本是否引入 breaking change、API 变更范围、迁移工作量评估 |
| 维护者健康度 | 15% | analyzer-2 | 最后提交时间、维护者数量、issue 响应中位时间、是否标记为 deprecated/archived |
| 许可证合规性 | 10% | analyzer-2 | 许可证类型（MIT/Apache/GPL/AGPL）、许可证兼容性、传染性许可证风险 |

**analyzer-1 总权重：50%**（CVE 漏洞严重性 30% + 代码路径可达性 20%）
**analyzer-2 总权重：50%**（版本落后程度 15% + Breaking Change 风险 10% + 维护者健康度 15% + 许可证合规性 10%）

**`--scope` 参数处理**：`direct` 仅分析直接依赖，`all` 包含传递依赖。未指定则默认 `all`。

---

## 阶段零：包管理器检测

### 步骤 1：扫描项目依赖生态

Team lead 分析项目结构：

1. 扫描项目目录，检测所有包管理器清单文件和锁文件
2. 识别多语言/多模块项目结构（monorepo、workspace）
3. 检测依赖源配置（npm registry、PyPI mirror、私有仓库）
4. 统计依赖数量概览（直接依赖数、传递依赖数）
5. 输出依赖生态清单

### 步骤 2：用户确认扫描范围

**标准模式**：向用户展示依赖生态清单，AskUserQuestion 确认：
- 确认扫描范围（direct/all）
- 是否排除某些依赖（如 devDependencies）
- 是否需要生成 SBOM

**单轮确认模式**：跳过确认，直接进入阶段一。
**完全自主模式**：自动决策，不询问用户，直接进入阶段一。

---

## 阶段一：自动化扫描 + 双路独立分析

### 步骤 3：启动 dep-scanner

**dep-scanner 自动化扫描**：
1. 按检测到的包管理器逐一运行对应审计工具
2. 收集每个依赖的元数据：

| 数据类别 | 收集内容 |
|---------|---------|
| 基本信息 | 包名、当前版本、最新版本、是否直接依赖 |
| CVE 数据 | CVE 编号、CVSS 评分、漏洞描述、受影响版本范围、修复版本 |
| 版本信息 | 当前版本发布日期、最新版本发布日期、落后 patch/minor/major 数 |
| 许可证 | 声明的许可证类型、是否兼容项目许可证 |
| 维护状态 | 仓库 URL、最后提交日期、开放 issue 数、是否 deprecated/archived |

3. 汇总输出**依赖扫描报告**发送给 team lead
4. dep-scanner 完成后关闭（不参与后续阶段）

### 步骤 4：分发扫描数据并启动双 analyzer

Team lead 收到 dep-scanner 报告后，将扫描数据分发给两位 analyzer，并行启动分析。

### 步骤 5：独立并行分析

两位 analyzer 各自分析负责的维度，**互不交流**。

**Analyzer-1（CVE 严重性分析）**：

| 分析项 | 具体内容 | 输出 |
|--------|---------|------|
| CVSS 评分排序 | 按 CVSS 3.x 评分从高到低排列所有 CVE | 优先级排序列表 |
| 可利用性评估 | 是否有公开 PoC/Exploit、攻击向量（网络/本地）、攻击复杂度 | 可利用性等级（Active/PoC/Theoretical） |
| 代码路径可达性 | 阅读项目代码，分析漏洞所在模块是否被实际引用 | 可达/不可达/不确定 |
| 在野利用情况 | 检查 CISA KEV 目录、ExploitDB、是否有在野利用报告 | 是否被积极利用 |
| 修复版本可用性 | 是否存在修复版本、修复版本与当前版本的距离 | 可升级/无修复版本/需替换 |

- 对每个有 CVE 的依赖输出：依赖名 + CVE 编号 + CVSS 评分 + 可利用性 + 代码路径可达性 + 风险定级 + 升级建议
- 参考 dep-scanner 的审计结果，验证 CVE 数据准确性

**Analyzer-2（版本陈旧度分析）**：

| 分析项 | 具体内容 | 输出 |
|--------|---------|------|
| 版本落后距离 | 落后 patch/minor/major 版本数、时间跨度 | 落后程度评级 |
| Breaking Change 风险 | 升级到安全/最新版本的 changelog 分析、API 变更检查 | 升级风险等级（安全/需测试/高风险） |
| 维护者健康度 | 最后提交时间、维护者数量、issue 响应中位时间、发布频率 | 健康/亚健康/不活跃/已废弃 |
| 许可证合规 | 许可证类型识别、传染性许可证检查（GPL/AGPL）、许可证兼容性 | 合规/警告/冲突 |
| 替代方案 | 对已废弃/不维护的依赖推荐替代包 | 替代方案列表 |
| 供应链风险 | 是否有已知的供应链攻击历史、包名相似性（typosquatting）检查 | 风险等级 |

- 对每个依赖输出：依赖名 + 当前版本 + 最新版本 + 落后距离 + 维护者健康度 + 许可证状态 + 升级风险 + 建议
- 参考 dep-scanner 的元数据，补充分析

---

## 阶段二：合并 & 排序

### 步骤 6：启动 reporter

两位 analyzer 分析完成后，启动 reporter。Team lead 将以下材料发送给 reporter：
- dep-scanner 依赖扫描报告
- analyzer-1 CVE 严重性分析报告
- analyzer-2 版本陈旧度分析报告
- 项目依赖生态信息

### 步骤 7：合并与交叉关联

Reporter 执行合并分析：

1. **交叉关联**：将同一依赖的 CVE 风险（analyzer-1）和陈旧度风险（analyzer-2）合并为单条记录
2. **综合定级**：按 CVE 严重性 × 代码路径可达性 × 维护者健康度 综合评估每个依赖的总体风险
3. **优先级排序**：按综合风险从高到低排列
4. **升级建议生成**：为每个需要处理的依赖生成具体升级命令

**综合风险计算公式**：
```
综合风险 = CVE 严重性（analyzer-1 权重 50%）+ 陈旧度风险（analyzer-2 权重 50%）

对于同一依赖：
- analyzer-1 定级和 analyzer-2 定级取较高者为基准
- 如果两者都为 Critical → 综合风险 = Critical（P0）
- 如果一方 Critical 另一方 ≤ Medium → 综合风险 = Critical（但标注陈旧度/CVE 维度差异）
- 如果两者定级差异 ≥ 2 级 → 标注为"分析争议项"

争议率 = 争议项数 / 两位 analyzer 都分析的依赖数 × 100%
争议率 > 50% → 触发熔断，必须暂停问用户
```

### 步骤 8：熔断检查

**分析差异熔断**：
- 如果两位 analyzer 对同一依赖的风险定级差异 ≥ 2 级，reporter 标注为"争议项"
- 争议项占比 > 50% → **不可跳过，必须暂停问用户**（熔断机制）

**Critical CVE 熔断**：
- 统一报告中 Critical CVE 超过 10 个 → **不可跳过，必须暂停问用户**（熔断机制）
- 向用户展示 Critical CVE 列表，确认是否继续生成完整报告

**无熔断触发**时，reporter 输出**统一依赖健康报告**：

```
╔══════════════════════════════════════════════════╗
║           依赖健康报告                            ║
╠══════════════════════════════════════════════════╣
║ 依赖总数: XXX（直接: XX，传递: XX）
║
║ 🔴 Critical CVE: X 个
║ 🟠 High CVE: X 个
║ 🟡 Medium CVE: X 个
║
║ 过时依赖: XX 个（落后 >6 个月）
║ 无人维护: X 个（>1 年无提交）
║ 许可证问题: X 个
╚══════════════════════════════════════════════════╝

### 依赖风险清单（按优先级排序）

#### Critical 风险
| # | 依赖名 | 当前版本 | 修复版本 | CVE | CVSS | 可达性 | 维护状态 | 建议操作 |
|---|--------|---------|---------|-----|------|--------|---------|---------|
| 1 | ... | ... | ... | CVE-XXXX-XXXX | 9.8 | 可达 | 活跃 | 立即升级 |

#### High 风险
| # | 依赖名 | 当前版本 | 修复版本 | CVE | CVSS | 可达性 | 维护状态 | 建议操作 |
|---|--------|---------|---------|-----|------|--------|---------|---------|
| 1 | ... | ... | ... | ... | ... | ... | ... | ... |

#### Medium / Low / Info 风险
...

### 争议项（如有）
1. 依赖名 — analyzer-1 定级: X / analyzer-2 定级: Y — reporter 最终定级: Z — 理由
```

### 步骤 9：依赖健康评分

Reporter 根据统一报告计算各维度依赖健康评分：

评分规则：
- 基础分 10.0，按风险扣分
- Critical 风险：每个扣 1.5 分（该维度最多扣至 0 分）
- High 风险：每个扣 0.8 分
- Medium 风险：每个扣 0.3 分
- Low 风险：每个扣 0.1 分
- Info：不扣分

按权重计算总分，输出各维度和总体依赖健康评分。

Reporter 完成后关闭。

---

## 阶段三：可选自动修复

### 步骤 10：生成升级方案（`--fix` 模式）

**仅当指定 `--fix` 参数时执行此阶段**，否则跳过至阶段四。

Team lead 根据统一报告生成安全升级方案：

1. **Patch 级升级**（安全风险最低）：直接生成升级命令
2. **Minor 级升级**（需测试）：生成升级命令 + 测试建议
3. **Major 级升级**（可能有 Breaking Change）：仅生成建议，不自动执行

升级命令示例：

| 包管理器 | 升级命令 |
|---------|---------|
| npm | `npm update <pkg>` / `npm install <pkg>@<version>` |
| pip | `pip install --upgrade <pkg>==<version>` |
| cargo | `cargo update -p <pkg>` |
| go | `go get <pkg>@<version>` |
| bundler | `bundle update <pkg>` |
| maven | 修改 pom.xml 中的版本号 |
| composer | `composer update <pkg>` |

### 步骤 11：用户确认升级方案

**标准模式**：向用户展示升级方案，AskUserQuestion 确认：
- 确认执行全部升级
- 选择性执行部分升级
- 跳过升级

**单轮确认模式**：仅执行 patch 级升级，skip major 级升级。
**完全自主模式**：仅执行 patch 级升级，skip major 级升级。

---

## 阶段四：收尾

### 步骤 12：保存报告

Team lead 按 `--lang` 指定的语言保存最终报告：

1. 将完整依赖健康报告保存到项目目录（如 `deps-health-YYYYMMDD.md`）
2. 将结构化数据保存到 `~/.gstack/data/{slug}/deps-health.json`（供跨技能消费）
3. 可选：生成 SBOM 文件（CycloneDX/SPDX 格式）
4. 向用户输出报告保存路径和审计总结：

```
## 依赖健康检查完成

### 审计总结
- 扫描范围：[direct/all]
- 依赖健康评分：X.X / 10.0
- 依赖总数：XXX（直接: XX，传递: XX）
- 发现风险：Critical X / High X / Medium X / Low X / Info X
- 报告路径：[文件路径]
- 数据路径：~/.gstack/data/{slug}/deps-health.json

### 关键风险
1. [最高危依赖概述]
2. ...

### 建议下一步
1. 立即升级 Critical 风险依赖
2. 本周内升级 High 风险依赖
3. 制定过时依赖的升级计划
4. 替换无人维护的依赖
5. 解决许可证合规问题

### 自主决策汇总（单轮确认模式/完全自主模式）
| 决策节点 | 决策内容 | 理由 |
|---------|---------|------|
| [阶段/步骤] | [决策描述] | [理由] |

### 附录：分析共识说明
- analyzer-1 分析依赖数：[数量] 个（CVE 严重性 + 代码路径可达性）
- analyzer-2 分析依赖数：[数量] 个（版本陈旧度 + 维护者健康度 + 许可证合规）
- dep-scanner 扫描依赖数：[数量] 个
- 两位 analyzer 重叠分析依赖：[数量] 个（共识度 = XX%）
- 定级一致性：XX%
- 争议项：[数量] 个（争议率 = XX%）
  - [依赖名] — analyzer-1 定级: X / analyzer-2 定级: Y → reporter 最终定级: Z（理由）
- 仅 analyzer-1 标记风险：[列表]
- 仅 analyzer-2 标记风险：[列表]
```

### 步骤 12.5：用户确认报告

Team lead 向用户展示依赖健康报告摘要：
- 依赖健康评分
- 风险统计（各级别数量）
- Top 5 高危依赖概述

AskUserQuestion 确认：
- 确认报告，保存并结束
- 要求补充分析某些依赖
- 调整风险定级

**单轮确认模式**：最终报告必须经用户确认。
**完全自主模式**：自动决策，不询问用户。

### 步骤 13：跨团队衔接建议（可选）

Team lead 根据检查结果向用户建议后续动作：
- **发现 Critical/High CVE 需要升级**：建议运行 `/team-dev` 启动研发团队执行升级和回归测试
- **依赖架构存在系统性问题（过度依赖、循环依赖）**：建议运行 `/team-arch` 评估依赖架构优化
- **升级完成后需要验证**：建议运行 `/team-review` 对升级代码做全面审查
- **发现安全相关依赖问题**：建议运行 `/team-security` 做全面安全审计
- 用户可选择执行或跳过，不强制。

### 步骤 14：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 核心原则

- **生态全覆盖**：支持所有主流包管理器，不遗漏任何依赖源
- **双路独立**：两位 analyzer 从不同维度独立分析，互不交流，避免盲区和偏见
- **可达性优先**：CVE 严重性结合代码路径可达性评估，避免"纸面漏洞"导致误报
- **维护者即风险**：依赖的维护者健康度是长期安全的核心指标
- **最小升级原则**：优先推荐 patch 级升级，避免不必要的 breaking change
- **供应链意识**：关注供应链攻击风险（typosquatting、恶意包、被接管的包）
- **许可证合规**：识别传染性许可证风险，避免法律合规问题
- **可操作性**：升级建议必须包含具体命令，可直接执行，避免空泛建议

---

### 共识度计算

team lead 按五维度评估双路分析的共识度：

| 维度 | 权重 |
|------|------|
| 审计发现一致性（相同问题/结论） | 20% |
| 互补性（独有但不矛盾的审计发现） | 20% |
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
| 审计工具未安装/无法运行 | dep-scanner 标注"该工具不可用"，不阻塞流程，analyzer 基于已有数据分析 |
| 无锁文件（无法确定精确版本） | dep-scanner 标注"版本不精确"，基于清单文件的版本范围分析，报告中建议生成锁文件 |
| 私有仓库依赖（无法获取元数据） | dep-scanner 标注"私有依赖，元数据不可用"，analyzer 跳过该依赖的在线数据分析 |
| 传递依赖数量过大（>500） | dep-scanner 优先分析直接依赖 + 有已知 CVE 的传递依赖，标注未完全覆盖的范围 |
| 两位 analyzer 定级差异过大（争议项 > 50%） | 触发熔断，暂停问用户裁决争议项 |
| Critical CVE 超过 10 个 | 触发熔断，暂停向用户确认是否继续完整报告 |
| 发现疑似供应链攻击（恶意包/被接管的包） | 立即通知用户（无论任何模式），建议紧急处置 |
| 网络不可用（无法查询 CVE 数据库） | dep-scanner 基于本地缓存和工具内置数据库分析，标注"CVE 数据可能不完整" |
| Monorepo 多模块项目 | dep-scanner 按模块逐一扫描，报告中按模块分组展示 |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前步骤恢复 |

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

