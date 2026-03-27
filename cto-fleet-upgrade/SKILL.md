---
name: cto-fleet-upgrade
description: |
  Upgrade cto-fleet to the latest version. Pulls latest changes from git and
  re-runs setup to register any new skills. Use when asked to "upgrade cto-fleet",
  "update cto-fleet", "update team skills", or "pull latest team skills".
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

# /cto-fleet-upgrade

Upgrade cto-fleet to the latest version and show what's new.

## Inline upgrade flow

This section is referenced by skill preambles when they detect `UPGRADE_AVAILABLE`.

### Step 1: Ask the user (or auto-upgrade)

First, check if auto-upgrade is enabled:
```bash
_AUTO=""
[ "${CTO_FLEET_AUTO_UPGRADE:-}" = "1" ] && _AUTO="true"
[ -z "$_AUTO" ] && _AUTO=$(~/.claude/skills/cto-fleet/bin/cto-fleet-config get auto_upgrade 2>/dev/null || true)
echo "AUTO_UPGRADE=$_AUTO"
```

**If `AUTO_UPGRADE=true` or `AUTO_UPGRADE=1`:** Skip AskUserQuestion. Log "Auto-upgrading cto-fleet v{old} → v{new}..." and proceed directly to Step 2.

**Otherwise**, use AskUserQuestion:
- Question: "cto-fleet **v{new}** is available (you're on v{old}). Upgrade now?"
- Options: ["Yes, upgrade now", "Always keep me up to date", "Not now", "Never ask again"]

**If "Yes, upgrade now":** Proceed to Step 2.

**If "Always keep me up to date":**
```bash
~/.claude/skills/cto-fleet/bin/cto-fleet-config set auto_upgrade true
```
Tell user: "Auto-upgrade enabled. Future updates will install automatically." Then proceed to Step 2.

**If "Not now":** Write snooze state with escalating backoff (first snooze = 24h, second = 48h, third+ = 1 week), then continue with the current skill.
```bash
_SNOOZE_FILE=~/.cto-fleet/update-snoozed
_REMOTE_VER="{new}"
_CUR_LEVEL=0
if [ -f "$_SNOOZE_FILE" ]; then
  _SNOOZED_VER=$(awk '{print $1}' "$_SNOOZE_FILE")
  if [ "$_SNOOZED_VER" = "$_REMOTE_VER" ]; then
    _CUR_LEVEL=$(awk '{print $2}' "$_SNOOZE_FILE")
    case "$_CUR_LEVEL" in *[!0-9]*) _CUR_LEVEL=0 ;; esac
  fi
fi
_NEW_LEVEL=$((_CUR_LEVEL + 1))
[ "$_NEW_LEVEL" -gt 3 ] && _NEW_LEVEL=3
echo "$_REMOTE_VER $_NEW_LEVEL $(date +%s)" > "$_SNOOZE_FILE"
```
Note: `{new}` is the remote version from the `UPGRADE_AVAILABLE` output — substitute it from the update check result.

Tell user the snooze duration: "Next reminder in 24h" (or 48h or 1 week, depending on level). Tip: "Set `auto_upgrade: true` in `~/.cto-fleet/config.yaml` for automatic upgrades."

**If "Never ask again":**
```bash
~/.claude/skills/cto-fleet/bin/cto-fleet-config set update_check false
```
Tell user: "Update checks disabled. Run `~/.claude/skills/cto-fleet/bin/cto-fleet-config set update_check true` to re-enable."
Continue with the current skill.

### Step 2: Save old version

```bash
INSTALL_DIR="$HOME/.claude/skills/cto-fleet"
OLD_VERSION=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "unknown")
```

### Step 3: Upgrade

```bash
cd "$INSTALL_DIR"
OLD_HASH=$(git rev-parse HEAD)
STASH_OUTPUT=$(git stash 2>&1)
git fetch origin
git reset --hard origin/main
./setup
echo "如需回退: git reset --hard $OLD_HASH"
```
If `$STASH_OUTPUT` contains "Saved working directory", warn the user: "Note: local changes were stashed. Run `git stash pop` in the skill directory to restore them."

### Step 4: Write marker + clear cache

```bash
mkdir -p ~/.cto-fleet
echo "$OLD_VERSION" > ~/.cto-fleet/just-upgraded-from
rm -f ~/.cto-fleet/last-update-check
rm -f ~/.cto-fleet/update-snoozed
```

### Step 5: Show What's New

Read the git log between old and new version:
```bash
cd "$INSTALL_DIR"
NEW_VERSION=$(cat VERSION 2>/dev/null || echo "unknown")
git log --oneline "$OLD_VERSION"..HEAD 2>/dev/null || git log --oneline -10
```

Summarize as 3-5 bullets grouped by theme. Focus on user-facing changes (new skills, improved skills, bug fixes). Skip internal refactors.

Format:
```
cto-fleet v{new} — upgraded from v{old}!

What's new:
- [bullet 1]
- [bullet 2]
- ...
```

### Step 6: Continue

After showing What's New, continue with whatever skill the user originally invoked.

---

## Standalone usage

When invoked directly as `/cto-fleet-upgrade` (not from a preamble):

1. Force a fresh update check (bypass cache):
```bash
~/.claude/skills/cto-fleet/bin/cto-fleet-update-check --force 2>/dev/null || true
```

2. If `UPGRADE_AVAILABLE <old> <new>`: follow Steps 2-5 above.

3. If no output (already up to date): tell the user "You're already on the latest version."
