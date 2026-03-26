# cto-fleet Preamble

Add this block to the top of any SKILL.md (after the YAML frontmatter `---`) to enable
automatic update detection and prompting.

## Snippet

```markdown
## Preamble (run first)

\`\`\`bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
\`\`\`

If output shows `UPGRADE_AVAILABLE <old> <new>`: read `~/.claude/skills/cto-fleet/cto-fleet-upgrade/SKILL.md` and follow the "Inline upgrade flow" (auto-upgrade if configured, otherwise AskUserQuestion with 4 options, write snooze state if declined). If `JUST_UPGRADED <from> <to>`: tell user "Running cto-fleet v{to} (just updated!)" and continue.
```

## How it works

1. `bin/cto-fleet-update-check` fetches the VERSION file from GitHub (cached, 60min TTL)
2. Compares local VERSION with remote
3. Outputs `UPGRADE_AVAILABLE <old> <new>` if a new version exists
4. The skill's instructions tell Claude to follow the inline upgrade flow in `cto-fleet-upgrade/SKILL.md`
5. User gets 4 options: upgrade now, auto-upgrade, snooze, or disable

## State files

All stored in `~/.cto-fleet/`:
- `config.yaml` — user settings (auto_upgrade, update_check)
- `last-update-check` — cache (UP_TO_DATE or UPGRADE_AVAILABLE, with TTL)
- `just-upgraded-from` — marker written after upgrade, cleared on next skill run
- `update-snoozed` — snooze state (version, level, epoch)
