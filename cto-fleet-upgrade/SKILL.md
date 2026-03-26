---
name: cto-fleet-upgrade
description: Upgrade cto-fleet to the latest version. Pulls latest changes from git and re-runs setup to register any new skills. Use when asked to "upgrade cto-fleet", "update cto-fleet", "update team skills", or "pull latest team skills".
---

# cto-fleet-upgrade

Run these commands in sequence:

```bash
cd ~/.claude/skills/cto-fleet && git pull && ./setup
```

After running, report:
1. Whether any new commits were pulled (or already up to date)
2. How many skills were linked
3. If any new skills were added (compare the setup output to what was there before)
