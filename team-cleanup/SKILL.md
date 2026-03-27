---
name: team-cleanup
description: 清理 ~/.claude/teams/ 和 ~/.claude/tasks/ 中的残留 team 目录——扫描孤立目录，展示列表并按用户选择删除。Use when asked to "清理team目录""cleanup teams""删除残留team""team cleanup"。
argument-hint: [--all (清理全部，不询问)] [--pattern=team-*] [--dry-run (只展示不删除)]
---

## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE <old> <new>`: read `~/.claude/skills/cto-fleet/cto-fleet-upgrade/SKILL.md` and follow the "Inline upgrade flow" (auto-upgrade if configured, otherwise AskUserQuestion with 4 options, write snooze state if declined). If `JUST_UPGRADED <from> <to>`: tell user "Running cto-fleet v{to} (just updated!)" and continue.

---

**参数解析**：从 `$ARGUMENTS` 中检测以下标志：
- `--all`：跳过确认，清理全部残留 team
- `--pattern=<glob>`：只清理匹配该模式的 team（如 `--pattern=team-*` 只清理 cto-fleet 创建的 team）
- `--dry-run`：只展示清单，不实际删除

---

## 执行流程

### 步骤 1：扫描残留 team

运行以下命令收集信息：

```bash
# 列出所有 team 目录
ls -1 ~/.claude/teams/ 2>/dev/null | sort

# 对每个 team，尝试读取描述
for d in ~/.claude/teams/*/; do
  name=$(basename "$d")
  desc=$(CONFIG_PATH="$d/config.json" python3 -c "import json,os; d=json.load(open(os.environ['CONFIG_PATH'])); print(d.get('description','(无描述)'))" 2>/dev/null || echo "(无配置文件)")
  mtime=$(stat -c "%y" "$d" 2>/dev/null | cut -d. -f1 || stat -f "%Sm" "$d" 2>/dev/null)
  echo "$name | $mtime | $desc"
done
```

同时检查 tasks 目录中是否有对应条目：
```bash
ls -1 ~/.claude/tasks/ 2>/dev/null | sort
```

### 步骤 2：整理并展示清单

将扫描结果整理为表格，输出给用户：

```
发现 N 个残留 team：

序号 | Team 名称                    | 创建时间            | 描述
-----|------------------------------|---------------------|------------------
1    | dev-team-20260308-015919     | 2026-03-08 01:59    | (无配置文件)
2    | team-arch-20260308-232007    | 2026-03-08 23:20    | 架构分析: ...
3    | xftp-dev                     | 2026-03-14 16:00    | xftp 开发项目
...

tasks/ 中额外目录（无对应 team）：
- subconverter-ua-fix
```

### 步骤 3：确认清理范围

**如果传递了 `--all`**：跳过此步骤，清理全部。

**如果传递了 `--pattern`**：只展示匹配的条目，AskUserQuestion 确认。

**否则**，用 AskUserQuestion 让用户选择：

```
选项1：清理全部（N 个 team + 孤立 tasks）
选项2：只清理 cto-fleet 管理的（team-* 前缀，M 个）
选项3：只清理 7 天前的旧 team
选项4：手动指定（输入序号）
```

### 步骤 4：执行清理

**如果是 `--dry-run`**：只输出将要执行的命令，不实际运行。

对每个待清理的 team，执行：

```bash
# 删除 team 配置目录
rm -rf ~/.claude/teams/{team-name}

# 删除对应的 task 目录（如存在）
rm -rf ~/.claude/tasks/{team-name}
```

对孤立的 tasks 目录（无对应 team）也一并清理（如在范围内）。

### 步骤 5：输出结果

```
✅ 清理完成

已删除 team（N 个）：
- dev-team-20260308-015919
- team-arch-20260308-232007
- ...

已删除孤立 tasks（M 个）：
- subconverter-ua-fix

当前剩余 team：
- default（保留）
```

---

## 注意事项

- `default` 和当前 session 正在使用的 team 不删除（检查当前 team context）
- 删除前不做备份，操作不可逆
- `--dry-run` 模式下安全预览，不修改任何文件
- 如果某个 team 目录下有未提交的 worktree，`rm -rf` 前先提示用户

---

## 需求

$ARGUMENTS