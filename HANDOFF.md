# File-Based Handoff Specification

> Canonical specification for agent-to-agent file-based handoff in cto-fleet.
> Referenced by all `team-*` SKILL.md files. See RFC-2026-001 for full rationale.

## Purpose

Eliminate context overflow ("Request too large, max 20MB") by replacing inline message passing with file-referenced handoff. Agents write detailed output to files; SendMessage carries only the file path + a structured summary (≤500 characters).

---

## Core Mechanism

Every agent completing a unit of work performs **two steps**:

1. **Write** the full report to `/tmp/{team-name}/{filename}.md`
2. **SendMessage** with only: file path (1 line) + key summary (≤500 chars)

---

## Directory Structure

```
/tmp/{team-name}/
```

- `{team-name}` uses the same name passed to `TeamCreate` (e.g. `team-review-20260328-143022`)
- Team lead creates the directory immediately after `TeamCreate`:

```bash
mkdir -p /tmp/{team-name} && chmod 700 /tmp/{team-name}
```

- All agents share the same filesystem and user process — no permission issues.

---

## File Naming Convention

| Role Output | File Name Pattern | Example |
|---|---|---|
| Scanner report | `scanner-report.md` | `scanner-report.md` |
| Reviewer-N round R | `reviewer-{N}-round-{R}.md` | `reviewer-1-round-0.md` |
| Merged report round R | `merged-report-round-{R}.md` | `merged-report-round-0.md` |
| Root cause groups round R | `root-cause-groups-round-{R}.md` | `root-cause-groups-round-0.md` |
| Fixer round R | `fixer-round-{R}.md` | `fixer-round-1.md` |
| Tester round R | `tester-round-{R}.md` | `tester-round-1.md` |
| Architect-N design | `architect-{N}-design.md` | `architect-1-design.md` |
| Task breakdown | `task-breakdown.md` | `task-breakdown.md` |
| Coder-N task T | `coder-{N}-task-{T}.md` | `coder-1-task-3.md` |
| Review task T | `review-task-{T}.md` | `review-task-3.md` |
| Integration test round R | `integration-test-round-{R}.md` | `integration-test-round-1.md` |
| Final report | `final-report.md` | `final-report.md` |
| Fallback (unlisted roles) | `{role}-{context}.md` | `analyst-risk-assessment.md` |

> Only use a naming pattern when the role exists in the current skill. Unlisted roles use `{role}-{context}.md`.

---

## Summary Templates (≤500 characters each)

### Scanner

```
摘要：Lint违规{N}个 | 类型错误{N}个 | 高复杂度函数{N}个 |
      安全漏洞{N}个({Critical}个严重) | 覆盖率{N}% | 过时依赖{N}个
```

### Reviewer

```
摘要：总分{X.X}/10 | Critical:{N} Major:{N} Minor:{N} Info:{N} |
      {维度1}:{分数} {维度2}:{分数} ... | 关键发现：{1-2句}
```

### Fixer

```
摘要：修复{N}个根因组（{M}个发现）| 自检：lint{✅/❌} 测试{✅/❌} |
      无法修复：{N}个（原因简述）
```

### Tester

```
摘要：通过{N}/{M} | 覆盖率{X}%→{Y}%(Δ{Z}%) |
      盲区{N}处 | 回归：{有/无}
```

### Architect

```
摘要：方案名称 | 核心思想（1句）| 预估工期{N}天 |
      主要优势：{1-2点} | 主要风险：{1-2点}
```

### Coder

```
摘要：任务{T}完成 | 变更{N}文件{M}行 |
      自检：lint{✅/❌} 测试{✅/❌} | 关键变更：{1-2句}
```

---

## File Size Limits

| Constraint | Limit | Reason |
|---|---|---|
| Single report file | ≤ 2000 lines | Read tool default limit |
| Oversized reports | Split into `{name}.md` (summary) + `{name}-details.md` | TL only Reads summary part |
| SendMessage summary | ≤ 500 characters | Keep messages lightweight |

---

## Team Lead Read Strategy

Team lead does **not** proactively Read all files. Read only when needed:

| Scenario | TL Action | Read? |
|---|---|:---:|
| Received agent summary, needs to merge reports | Read the reviewer files | ⚡必须 Read |
| Received agent summary, needs to forward | Forward file path + summary only | No |
| Need to present report to user | Read the merged/final report file | ⚡必须 Read |
| Judge pass/fail from scores | Use summary scores only | No |
| Handle disagreement or anomaly | Read the specific disputed files | ⚡必须 Read |
| Task breakdown for assignment | Read task-breakdown.md | ⚡必须 Read |
| Integration test results for go/no-go | Read integration-test file | ⚡必须 Read |

**Key optimization**: When TL only needs to relay information, do NOT Read — just forward the path. The receiver Reads the file themselves.

---

## Agent Compliance Check

Team lead enforces handoff compliance on every incoming message:

> When you receive an agent message, check:
> - If the message exceeds **1000 characters** AND does not contain a file path with the `/tmp/team-` prefix, the agent likely forgot file-based handoff mode.
> - Respond: "请将完整内容写入 `/tmp/{team-name}/` 目录下的文件，然后重新发送文件路径 + ≤500 字符摘要"
> - Do NOT process oversized inline messages. Require the agent to re-send using handoff mode.

**Important**: Check specifically for the `/tmp/team-` prefix (not just `/tmp/`), to avoid false positives from unrelated temp file paths.

---

## Directory Cleanup

In the `TeamDelete` step, clean up the working directory:

```bash
rm -rf /tmp/{team-name}
```

---

## Preamble Section for SKILL.md

The following section is inserted into each `team-*` SKILL.md after the line containing `TeamCreate`. It is managed by `bin/sync-preamble` and delimited by HTML comments for automated sync.

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
