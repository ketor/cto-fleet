---
name: team-close
description: 关闭当前会话中所有活跃的 teammate 进程——向每个 teammate 发送 shutdown_request，等待确认后调用 TeamDelete 清理 team。Use when asked to "关闭所有agent""关掉teammates""清空agent面板""close agents""shutdown team""关闭team"。
argument-hint: [--force (跳过 shutdown_request，直接 kill tmux panes)]
---

## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE <old> <new>`: read `~/.claude/skills/cto-fleet/cto-fleet-upgrade/SKILL.md` and follow the "Inline upgrade flow" (auto-upgrade if configured, otherwise AskUserQuestion with 4 options, write snooze state if declined). If `JUST_UPGRADED <from> <to>`: tell user "Running cto-fleet v{to} (just updated!)" and continue.

---

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
- 关闭后如需清理磁盘上的残留目录，使用 `/team-cleanup`

---

## 需求

$ARGUMENTS
