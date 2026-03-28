---
name: team-close
description: 关闭当前会话中所有活跃的 teammate 进程——向每个 teammate 发送 shutdown_request，等待确认后调用 TeamDelete 清理 team。Use when asked to "关闭所有agent""关掉teammates""清空agent面板""close agents""shutdown team""关闭team"。
argument-hint: [--force (跳过 shutdown_request，直接 kill tmux panes)]
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
- `--force`：跳过 shutdown_request 协议，直接用 tmux kill-pane 强制关闭所有 agent pane

---

## 执行流程

### 步骤 1：检查当前 team 状态

读取当前 team config，获取所有活跃 teammate 列表：

```bash
# 找当前 team name（从 session context 获取，或列出 ~/.claude/teams/ 中最新的）
cat ~/.claude/teams/*/config.json 2>/dev/null | python3 -c "
import json,sys
for line in sys.stdin:
    try:
        d = json.loads(line)
        if 'members' in d:
            for m in d['members']:
                print(m.get('name','?'), m.get('agentId','?'))
    except: pass
"
```

同时扫描 tmux 中的 agent pane：
```bash
tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} #{pane_title}" 2>/dev/null | grep -i "agent\|claude\|teammate" || true
```

### 步骤 2：向所有 teammate 发送 shutdown_request

对每个活跃的 teammate，使用 SendMessage 工具发送：
```json
{
  "type": "shutdown_request",
  "reason": "user requested team-close"
}
```

等待每个 teammate 回复 `shutdown_response`（approve: true）。

**如果 teammate 5 秒内无响应**：标记为"未响应"，继续处理其他 teammate。

### 步骤 3：调用 TeamDelete

所有 teammate 确认关闭（或超时）后，调用 **TeamDelete** 工具清理当前 team 的配置和任务目录。

### 步骤 4：强制清理未响应的 tmux pane

**如果有未响应的 teammate**，或传递了 `--force` 标志：

```bash
# 列出所有 claude agent 相关的 tmux pane 并 kill
tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}" 2>/dev/null \
  | grep -i "claude-code\|anthropic" \
  | awk '{print $1}' \
  | while read pane; do
      tmux kill-pane -t "$pane" 2>/dev/null && echo "killed: $pane"
    done
```

### 步骤 5：输出结果

```
✅ team-close 完成

已优雅关闭（shutdown_request）：
- architect-1
- architect-2
- coder-1

强制关闭（无响应）：
- tester（tmux pane killed）

TeamDelete 已清理 team: team-dev-20260327-180000
```

---

## 注意事项

- `--force` 模式跳过 shutdown_request，直接 kill pane，可能丢失 teammate 未提交的上下文
- 如果当前没有活跃的 team（不在任何 TeamCreate 上下文中），直接扫描并 kill tmux 中所有 claude agent pane

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

- 关闭后如需清理磁盘上的残留目录，使用 `/team-cleanup`

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

