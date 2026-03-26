---
name: team-release
description: 启动一个发布管理团队（scanner/validator×2/writer/checker），按阶段协作完成变更扫描、双路验证、风险评估、Changelog 生成和发布前检查。使用方式：/team-release [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--type=major|minor|patch|hotfix] [--from=tag/commit] [--lang=zh|en] 发布描述或版本号
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--type=major|minor|patch|hotfix] [--from=tag/commit] [--lang=zh|en] 发布描述或版本号
---

**参数解析**：从 `$ARGUMENTS` 中检测以下标志：
- `--auto`：完全自主模式（不询问用户任何问题，全程自动决策）
- `--once`：单轮确认模式（将所有需要确认的问题合并为一轮提问，确认后全程自动执行）
- `--type=major|minor|patch|hotfix`：发布类型（默认根据变更内容自动推断）
- `--from=tag/commit`：变更起始点（默认为上一个 tag）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

解析后将标志从发布描述中移除。

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 确认发布范围 + 确认发布执行 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅确认发布执行 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下条件节点自动决策规则：
- **发布类型不确定** → team lead 根据变更内容自动推断，在发布确认时告知用户推断结果
- **validator-1/validator-2 发现问题** → team lead 综合两份验证报告裁决，在发布确认时附带问题摘要
- **风险评估为 Medium** → 继续流程，在发布确认时高亮风险项
- **风险评估为 High/Critical** → **不可跳过，必须暂停问用户**（熔断机制）
- **检查清单有项目未通过** → **不可跳过，必须暂停问用户**（熔断机制，单轮确认模式和完全自主模式均适用）

完全自主模式下：所有节点均自动决策，不询问用户。熔断机制仍然生效——触发熔断条件时是唯一会暂停询问用户的情况。

## 发布类型表

| Type | Version Change | 风险等级 | 额外检查 |
|------|---------------|---------|---------|
| **major** | X.0.0 | High | Breaking change 逐项审查，migration plan 必须提供 |
| **minor** | x.Y.0 | Medium | 功能完整性检查，对照 milestone/issue 验证 |
| **patch** | x.y.Z | Low | 修复项逐一验证，确认无副作用 |
| **hotfix** | x.y.Z+1 | Critical | 最小变更审查，快速通道，仅验证修复目标 |

**Hotfix 快速通道**：当 `--type=hotfix` 时，流程大幅精简：
- 阶段一：仅启动 scanner（不启动 validator-1/validator-2），scanner 仅扫描修复相关 commit
- 阶段二：跳过完整风险评估，仅检查变更规模和测试覆盖两个维度
- 阶段三：checker 执行精简清单（仅 #1 CI 全绿、#2 版本号、#3 Changelog、#6 回滚方案、#9 依赖安全）
- 阶段四：正常收尾

使用 TeamCreate 创建 team（名称格式 `team-release-{YYYYMMDD-HHmmss}`，如 `team-release-20260311-143022`，避免多次调用冲突），你作为 team lead 按以下流程协调。

## 流程概览

```
阶段零  发布范围确定 → 解析 --from / --type → 确定变更范围和版本号
         ↓
阶段一  变更扫描 + 双路验证（并行）→ scanner 扫描 git log + validator-1 功能验证
         + validator-2 质量安全验证
         ↓
阶段二  风险评估 + Changelog → 合并验证结果 → 五维风险评估 → writer 生成 Changelog
         ↓
阶段三  发布前检查 → checker 执行十项检查清单 → 用户确认发布
         ↓
阶段四  收尾 → 保存 Changelog + 发布摘要 + 清理
```

## 角色定义

| 角色 | 职责 |
|------|------|
| scanner | 扫描 git log 分析变更：commit 分类（feat/fix/perf/docs/refactor/breaking）、文件变更统计、breaking changes 检测。运行 CI 检查。**阶段一扫描完成后关闭（步骤 5）。** |
| validator-1 | 独立验证——功能完整性：对照 milestone/issue 检查所有功能是否已合入，测试是否通过，功能覆盖率评估。**不与 validator-2 交流。** **阶段二 Changelog 生成完成后关闭（步骤 10）。** |
| validator-2 | 独立验证——质量与安全：依赖安全审计（已知漏洞扫描）、代码质量指标变化（lint 警告、复杂度）、性能基准对比。**不与 validator-1 交流。** **阶段二 Changelog 生成完成后关闭（步骤 10）。** |
| writer | 根据 scanner 的变更分析和验证结果，生成 Changelog（按 Conventional Commits 分类）和 Release Notes。**阶段二完成后关闭。** |
| checker | 最终检查——执行发布前核对清单（十项），输出逐项通过/未通过报告，标注阻塞项。**阶段四收尾时关闭。** |

---

## 阶段零：发布范围确定

### 步骤 1：解析发布参数

Team lead 解析参数，确定发布配置：

1. **起始点**：`--from` 指定的 tag/commit，未指定则自动检测最近的 tag（`git describe --tags --abbrev=0`）
2. **目标点**：当前 HEAD
3. **发布类型**：`--type` 指定的类型，未指定则暂定 `auto`（后续由 scanner 分析结果推断）
4. **版本号**：根据发布类型和当前版本计算目标版本号

### 步骤 2：版本号计算

根据当前版本和发布类型计算目标版本号：

| 当前版本 | --type=major | --type=minor | --type=patch | --type=hotfix |
|---------|-------------|-------------|-------------|--------------|
| v1.2.3 | v2.0.0 | v1.3.0 | v1.2.4 | v1.2.4 |
| v0.9.0 | v1.0.0 | v0.10.0 | v0.9.1 | v0.9.1 |

如果项目使用 pre-release 标签（如 `-rc.1`、`-beta.1`），team lead 在确认阶段提示用户是否需要添加。

### 步骤 3：确认发布范围

Team lead 输出发布范围摘要：
- 变更起始点 → 目标点（含 commit hash 前 8 位）
- 预估 commit 数量（`git rev-list --count`）
- 发布类型和目标版本号
- 涉及的主要作者（`git shortlog -sn`）
- 时间跨度（起始点到 HEAD 的时间范围）

确认方式：
- **标准模式**：用 AskUserQuestion 确认发布范围
- **单轮确认模式**：team lead 自行确认，在最终发布确认时一并展示
- **完全自主模式**：自动决策，不询问用户

---

## 阶段一：变更扫描 + 双路验证（并行）

### 步骤 4：启动 scanner、validator-1 和 validator-2

同时启动三个角色，**并行执行**：

**Scanner 任务**——具体操作方法：
- 获取完整 commit 列表：`git log --oneline <from>..<to>`
- **Conventional Commits 解析**：逐条解析 commit message 的前缀，分类规则：
  - `feat:` 或 `feat(scope):` → Features
  - `fix:` 或 `fix(scope):` → Bug Fixes
  - `perf:` → Performance
  - `docs:` → Documentation
  - `refactor:` → Refactoring
  - `test:` → Tests
  - `ci:` → CI
  - `chore:` → Chores
  - 无前缀或不规范 → Other（在报告中标注不规范 commit 数量）
- **Breaking Changes 检测**：
  - `git log --oneline <from>..<to> --grep="BREAKING CHANGE"` 搜索 commit body 中的 BREAKING CHANGE 标记
  - `git log --oneline <from>..<to>` 中搜索 `feat!:` 或 `fix!:` 等带 `!` 的前缀
  - `Grep("BREAKING CHANGE|BREAKING-CHANGE", path="CHANGELOG.md")` 检查已记录的 breaking changes
- **文件变更统计**：
  - `git diff --stat <from>..<to>` 获取总体变更统计
  - `git diff --numstat <from>..<to> | sort -k1 -rn | head -10` 按变更行数排序获取 Top 10 热区文件
  - `git diff --diff-filter=A --name-only <from>..<to>` 列出新增文件
  - `git diff --diff-filter=D --name-only <from>..<to>` 列出删除文件
- **CI 状态检查**：检查最近一次 CI pipeline 运行结果（`Glob("**/.github/workflows/*.yml")` 定位 CI 配置）
- 输出结构化变更报告，格式如下：
  ```
  变更报告:
    commit 总数: N
    分类统计: feat(X) / fix(Y) / perf(Z) / docs(W) / refactor(V) / test(U) / ci(T) / chore(S) / other(R)
    不规范 commit 数: N（占比 XX%）
    breaking changes: [列表，含 commit hash 和描述]
    文件变更热区: [按变更行数排序的前 10 个文件，含增/删行数]
    新增文件: [列表]
    删除文件: [列表]
    CI 状态: pass / fail / unknown
    主要贡献者: [git shortlog -sn <from>..<to> 结果]
  ```

**Validator-1 任务（功能完整性）**：
- 查找项目中的 milestone/issue 追踪（GitHub Issues、JIRA、TODO 等）
- 对照已关闭的 issue，检查对应 commit 是否在变更范围内
- 运行项目测试套件，确认全部通过
- 检查是否有标记为"已完成"但未合入的 PR
- 评估功能覆盖率，标注遗漏的功能点
- 输出功能完整性报告

**Validator-2 任务（质量与安全）**：
- 依赖安全审计：检查 `package-lock.json` / `go.sum` / `Cargo.lock` / `requirements.txt` 等依赖文件的变更，查找已知漏洞
- 代码质量指标：运行 lint 检查，对比变更前后的警告数量变化
- 复杂度分析：检查新增代码的圈复杂度，标注高复杂度函数
- 性能基准对比：如项目有 benchmark，运行并对比变更前后的结果
- 输出质量安全报告

### 步骤 5：关闭 scanner

Scanner 完成变更扫描报告后，team lead 关闭 scanner（shutdown_request）。Scanner 的报告将传递给后续阶段使用。

### 步骤 6：收集验证报告

等待 validator-1 和 validator-2 都完成报告。Team lead 确保两份报告独立产出，不让两个 validator 看到对方的报告。

### 步骤 7：推断发布类型（如未指定）

如果 `--type` 为 `auto`，team lead 根据 scanner 报告推断：
- 存在 breaking changes → `major`
- 存在 feat 类型 commit → `minor`
- 仅有 fix/perf/docs 类型 → `patch`
- 推断后计算目标版本号

---

## 阶段二：风险评估 + Changelog

### 步骤 7.5：合并验证报告

Team lead 对比 validator-1 和 validator-2 的报告，输出合并结果：

| 对比结果 | 处理方式 |
|---------|---------|
| **一致发现**（双方都发现的问题） | 直接采纳，标记为"共识" |
| **互补发现**（各自领域的独有发现） | 合并，标注来源（功能/质量） |
| **分歧/矛盾**（对同一问题的不同判断） | 标注为"待仲裁"，team lead 裁决 |

输出：
1. **共识清单**：双方一致发现的问题
2. **互补清单**：各自独有的有价值发现
3. **分歧清单**：矛盾之处及双方判断对比
4. **共识度评估**：共识度 = (共识发现数 + 互补发现数) / 总发现数(去重并集) x 100%

### 步骤 8：五维风险评估

Team lead 综合 scanner 报告、validator-1 报告和 validator-2 报告，按以下五个维度评分（1-10 分）：

| 维度 | 权重 | 评分标准 |
|------|------|---------|
| 变更规模 | 20% | 文件变更数、代码行数变化。<50 行为 10 分，>1000 行为 3 分，>5000 行为 1 分 |
| Breaking Changes | 25% | 无 breaking change 为 10 分，有但有 migration guide 为 6 分，有但无 guide 为 2 分 |
| 依赖安全 | 15% | 无已知漏洞为 10 分，有低危为 7 分，有中危为 4 分，有高危为 1 分 |
| 测试覆盖 | 20% | 全部测试通过且覆盖新功能为 10 分，通过但覆盖不足为 6 分，有失败为 2 分 |
| 回滚复杂度 | 20% | 纯代码变更为 10 分，含配置变更为 7 分，含数据库 migration 为 4 分，含数据迁移为 2 分 |

**综合评分** = 各维度加权平均（保留一位小数）

Team lead 输出风险评估矩阵：
```
风险评估报告:
  变更规模:      [X/10] (权重 20%)  — [具体理由]
  Breaking Changes: [X/10] (权重 25%)  — [具体理由]
  依赖安全:      [X/10] (权重 15%)  — [具体理由]
  测试覆盖:      [X/10] (权重 20%)  — [具体理由]
  回滚复杂度:    [X/10] (权重 20%)  — [具体理由]
  ─────────────────────────────
  综合评分:      [X.X/10] → [风险等级]
```

| 风险等级 | 综合评分 | 处理方式 |
|---------|---------|---------|
| **Low** | >= 8 | 正常发布 |
| **Medium** | 6 ~ 8 | 标准模式：提示风险后确认；单轮确认模式/完全自主模式：继续并高亮风险 |
| **High** | 4 ~ 6 | **必须暂停**，向用户展示风险详情，AskUserQuestion 确认是否继续 |
| **Critical** | < 4 | **必须暂停**，强烈建议用户推迟发布，AskUserQuestion 确认 |

**发布类型与风险等级交叉验证**：
- `--type=patch` 但风险等级为 High/Critical → 建议用户考虑升级为 minor/major
- `--type=hotfix` 但变更涉及非修复代码 → 警告用户变更范围超出 hotfix 预期
- `--type=major` 但无 breaking changes → 提示用户确认是否确实需要 major 版本

### 步骤 9：启动 writer 生成 Changelog

风险评估完成后（如需用户确认则等待确认），启动 writer。

传入 scanner 变更报告和风险评估结果，writer 生成：

**Changelog**（按 Conventional Commits 分类）：
```
## [vX.Y.Z] - YYYY-MM-DD

### ⚠ Breaking Changes
- ...

### Features
- ...

### Bug Fixes
- ...

### Performance
- ...

### Documentation
- ...

### Other Changes
- ...
```

**Release Notes**（面向用户的发布说明）：
- 版本亮点（3-5 条核心变更）
- 升级注意事项（breaking changes 说明 + migration 步骤）
- 已知问题
- 致谢（贡献者列表）

Writer 按 `--lang` 参数决定 Changelog 和 Release Notes 的语言：
- `--lang=zh`：中文标题（`### 新功能`、`### 问题修复`、`### 破坏性变更`、`### 性能优化`、`### 文档更新`、`### 其他变更`）
- `--lang=en`：英文标题（`### Features`、`### Bug Fixes`、`### Breaking Changes`、`### Performance`、`### Documentation`、`### Other Changes`）

Writer 完成后，team lead 关闭 writer。

### 步骤 10：关闭 validator-1 和 validator-2

Changelog 生成完成后，关闭两个 validator（shutdown_request）。

---

## 阶段三：发布前检查

### 步骤 11：启动 checker 执行检查清单

启动 checker，执行发布前核对清单（十项）：

| # | 检查项 | 阻塞级别 | 检查方式 |
|---|-------|---------|---------|
| 1 | CI/CD pipeline 全绿 | 阻塞 | 检查最新 CI 运行状态 |
| 2 | 版本号符合 semver 规范 | 阻塞 | 验证版本号格式和递增逻辑 |
| 3 | Changelog 已生成 | 阻塞 | 确认 Changelog 文件存在且内容完整 |
| 4 | Breaking changes 有 migration guide | 阻塞（仅 major） | 检查是否提供了迁移文档 |
| 5 | 数据库 migration 已就绪 | 阻塞（如适用） | 检查 migration 脚本是否存在且可执行 |
| 6 | 回滚方案已确认 | 阻塞 | 确认有回滚步骤文档或自动回滚机制 |
| 7 | 监控告警已配置 | 警告 | 检查是否有相关的监控配置 |
| 8 | 文档已更新 | 警告 | 检查 README/API docs 是否反映新版本变更 |
| 9 | 依赖无已知高危漏洞 | 阻塞 | 引用 validator-2 的安全审计结果 |
| 10 | 性能基准无退化 | 警告 | 引用 validator-2 的性能对比结果 |

Checker 输出逐项通过/未通过报告，标注阻塞项和警告项。

### 步骤 12：检查结果处理

- **全部通过**：进入发布确认
- **有警告项未通过**：
  - **标准模式**：展示警告，AskUserQuestion 确认是否继续
  - **单轮确认模式**：继续流程，在发布确认时高亮警告项
  - **完全自主模式**：自动决策，不询问用户
- **有阻塞项未通过**：**必须暂停**，向用户展示阻塞项详情，AskUserQuestion 确认处理方式（修复后重新检查 / 强制跳过 / 取消发布）

### 步骤 13：发布确认

Team lead 向用户输出发布确认摘要：
- 版本号：当前版本 → 目标版本
- 发布类型和风险等级
- 变更统计（commits / files / insertions / deletions）
- Changelog 摘要（核心变更前 5 条）
- 风险评估结果（五维评分 + 综合评分）
- 检查清单结果（通过/未通过/警告）
- 单轮确认模式/完全自主模式下的所有自动决策汇总

用 AskUserQuestion 等待用户最终确认。此确认**不可跳过**，即使是单轮确认模式/完全自主模式也必须确认。

---

## 阶段四：收尾

### 步骤 14：保存发布产物

用户确认发布后，team lead 执行：

1. **保存 Changelog**：将 writer 生成的 Changelog 追加到项目的 `CHANGELOG.md`（如文件已存在则插入到最前面，如不存在则创建）
2. **保存 Release Notes**：输出 Release Notes 内容，供用户复制到发布平台
3. **生成发布摘要报告**（保存为 `docs/releases/release-summary-vX.Y.Z.md`），格式：
   ```markdown
   # 发布摘要：vX.Y.Z

   > 生成时间：YYYY-MM-DD HH:MM | 发布类型：major/minor/patch/hotfix | 共识度：XX%

   ## 变更统计
   | 指标 | 值 |
   |------|---|
   | Commit 总数 | N |
   | 分类 | feat(X) / fix(Y) / ... |
   | Breaking Changes | N 个 |
   | 文件变更 | N 个文件, +X/-Y 行 |

   ## 风险评估
   [五维评分矩阵]

   ## 检查清单结果
   [十项检查逐项结果]

   ## 附录 A: 验证共识说明
   ### 共识发现
   [validator-1 和 validator-2 一致发现的问题]
   ### 分歧点及仲裁结果
   | 分歧点 | 功能视角 | 质量视角 | 仲裁结果 | 理由 |
   |--------|---------|---------|---------|------|

   ## 附录 B: 自主决策汇总（仅 --auto 或 --once 模式）
   | 决策节点 | 决策内容 | 理由 |
   |---------|---------|------|
   ```
4. **建议 Git 操作**：提供后续 Git 命令供用户参考（不自动执行）：
   ```
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```

### 步骤 15：最终总结 + 清理

Team lead 按 `--lang` 指定的语言向用户输出：
- 发布版本和类型
- 核心变更摘要
- 风险评估结论
- 检查清单通过情况
- Changelog 保存位置
- 后续建议（打 tag、推送、部署等）
- **（单轮确认模式/完全自主模式）自动决策汇总**：列出所有自动决策的节点、决策内容和理由

关闭 checker 和所有存活的 teammate，用 TeamDelete 清理 team。

### 步骤 15.5：跨团队衔接建议（可选）

Team lead 根据发布情况向用户建议后续动作：
- **major 版本发布**：建议运行 `/team-arch` 更新架构文档，确保与新版本一致
- **包含安全修复**：建议运行 `/team-security` 对发布版本做安全扫描
- **大规模变更发布后**：建议运行 `/team-review` 对新增代码做全面审查
- **生产事故后的 hotfix**：建议运行 `/team-postmortem` 做事后复盘
- 用户可选择执行或跳过，不强制。

---

## 核心原则

- **双路独立验证**：validator-1 和 validator-2 独立工作，确保功能和质量两个维度的验证互不干扰
- **量化风险评估**：五维加权评分，避免主观判断，提供可比较的风险等级
- **熔断机制**：High/Critical 风险和阻塞项检查失败时，无论何种模式都必须暂停问用户
- **最终确认不可跳过**：发布确认是硬性节点，单轮确认模式/完全自主模式也不可跳过
- **Conventional Commits**：严格按 Conventional Commits 规范分类变更，确保 Changelog 标准化
- **最小权限原则**：scanner 完成即关闭，writer 完成即关闭，避免不必要的资源占用
- **可追溯性**：所有验证结果、风险评分、检查清单结果都记录在发布摘要中

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| 无法确定起始 tag | 提示用户使用 `--from` 手动指定，或列出最近的 tag 供选择 |
| Git log 为空（无变更） | 终止流程，提示用户当前版本与目标无差异 |
| CI 检查失败 | Scanner 标记 CI 状态为失败，checker 在检查清单中标记阻塞，暂停问用户 |
| 依赖漏洞扫描工具不可用 | Validator-2 标记该项为"无法检查"，checker 在清单中标记为警告 |
| 测试套件执行失败 | Validator-1 记录失败测试列表，风险评估中测试覆盖维度降分 |
| 性能基准工具不可用 | Validator-2 标记该项为"无法对比"，checker 在清单中标记为警告 |
| Changelog 文件写入失败 | 将 Changelog 内容直接输出给用户，提示手动保存 |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从当前阶段恢复。如果是 validator 崩溃，从头执行验证。 |
| 发布类型推断不确定 | 标准模式：AskUserQuestion 让用户选择；单轮确认模式/完全自主模式：选择较高的类型（偏保守） |
| Hotfix 快速通道 | 简化流程：scanner 仅检查修复相关 commit，跳过完整功能验证，checker 执行精简清单（#1 #2 #3 #6 #9） |
| 存在未合并的 feature 分支 | Validator-1 检查是否有标记为"已完成"但未合入的 PR/MR，在功能完整性报告中列出遗漏项，team lead 提醒用户确认是否纳入本次发布 |
| Git 仓库状态异常（脏工作区/未提交变更） | Team lead 在阶段零检测工作区状态（`git status`），提示用户先提交或 stash 未提交变更，避免变更扫描结果不准确 |

---

## 需求

$ARGUMENTS
