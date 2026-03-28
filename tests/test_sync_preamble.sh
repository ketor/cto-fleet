#!/usr/bin/env bash
# Unit tests for bin/sync-preamble (backward compat via sync-protocols)
# Run: bash tests/test_sync_preamble.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNC_CMD="$SCRIPT_DIR/bin/sync-preamble"
PASS=0
FAIL=0
TOTAL=0

# ─── Helpers ─────────────────────────────────────────────────
setup() {
  TEST_DIR="$(mktemp -d)"
  export CTO_FLEET_DIR="$TEST_DIR/cto-fleet"
  mkdir -p "$CTO_FLEET_DIR/bin" "$CTO_FLEET_DIR/protocols"

  # Create protocol registry (only preamble for these tests)
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'REGEOF'
PREAMBLE_SECTION | protocols/preamble.md | * | | after_frontmatter
REGEOF

  # Create canonical preamble source with markers
  cat > "$CTO_FLEET_DIR/protocols/preamble.md" << 'PEOF'
<!-- PREAMBLE_SECTION_START -->
## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE <old> <new>`: read `~/.claude/skills/cto-fleet/cto-fleet-upgrade/SKILL.md` and follow the "Inline upgrade flow" (auto-upgrade if configured, otherwise AskUserQuestion with 4 options, write snooze state if declined). If `JUST_UPGRADED <from> <to>`: tell user "Running cto-fleet v{to} (just updated!)" and continue.
<!-- PREAMBLE_SECTION_END -->
PEOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
  fi
}

assert_contains() {
  TOTAL=$((TOTAL + 1))
  local desc="$1" pattern="$2" actual="$3"
  if echo "$actual" | grep -q "$pattern"; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (pattern '$pattern' not found)"
  fi
}

assert_exit_zero() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (expected exit 0, got $?)"
  fi
}

assert_exit_nonzero() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (expected non-zero exit, got 0)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  fi
}

# Skills now use HTML marker format (new canonical format)
create_skill_with_correct_preamble() {
  local name="$1"
  mkdir -p "$CTO_FLEET_DIR/$name"
  cat > "$CTO_FLEET_DIR/$name/SKILL.md" << 'EOF'
---
name: test-skill
description: test
---

<!-- PREAMBLE_SECTION_START -->
## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE <old> <new>`: read `~/.claude/skills/cto-fleet/cto-fleet-upgrade/SKILL.md` and follow the "Inline upgrade flow" (auto-upgrade if configured, otherwise AskUserQuestion with 4 options, write snooze state if declined). If `JUST_UPGRADED <from> <to>`: tell user "Running cto-fleet v{to} (just updated!)" and continue.
<!-- PREAMBLE_SECTION_END -->

Rest of skill content here.
EOF
}

create_skill_missing_preamble() {
  local name="$1"
  mkdir -p "$CTO_FLEET_DIR/$name"
  cat > "$CTO_FLEET_DIR/$name/SKILL.md" << 'EOF'
---
name: no-preamble
description: test skill with no preamble
---

This skill has no preamble section at all.

## Some other section

Content here.
EOF
}

create_skill_wrong_preamble() {
  local name="$1"
  mkdir -p "$CTO_FLEET_DIR/$name"
  cat > "$CTO_FLEET_DIR/$name/SKILL.md" << 'EOF'
---
name: wrong-preamble
description: test skill with outdated preamble
---

<!-- PREAMBLE_SECTION_START -->
## Preamble (run first)

```bash
echo "old preamble"
```

Old instructions that don't match.
<!-- PREAMBLE_SECTION_END -->

Actual skill body.
EOF
}

# ─── Test 1: --check detects consistent preamble → exit 0 ───
echo "Test: --check with consistent preamble"
setup
  create_skill_with_correct_preamble "team-dev"
  create_skill_with_correct_preamble "team-test-ok"
  result="$("$SYNC_CMD" --verbose 2>&1 || true)"
  assert_contains "reports OK for matching skill" "OK" "$result"
  assert_exit_zero "--check exits 0 when all match" "$SYNC_CMD"
teardown

# ─── Test 2: --check detects missing preamble → exit non-zero ─
echo "Test: --check with missing preamble"
setup
  create_skill_with_correct_preamble "team-dev"
  create_skill_missing_preamble "team-no-pre"
  result="$("$SYNC_CMD" 2>&1 || true)"
  assert_contains "reports MISSING" "MISSING" "$result"
  assert_exit_nonzero "--check exits non-zero on missing" "$SYNC_CMD"
teardown

# ─── Test 3: --check detects mismatched preamble → exit non-zero ─
echo "Test: --check with mismatched preamble"
setup
  create_skill_with_correct_preamble "team-dev"
  create_skill_wrong_preamble "team-wrong"
  result="$("$SYNC_CMD" 2>&1 || true)"
  assert_contains "reports OUTDATED" "OUTDATED" "$result"
  assert_exit_nonzero "--check exits non-zero on mismatch" "$SYNC_CMD"
teardown

# ─── Test 4: --fix repairs missing preamble ──────────────────
echo "Test: --fix inserts preamble into missing file"
setup
  create_skill_with_correct_preamble "team-dev"
  create_skill_missing_preamble "team-fix-missing"
  "$SYNC_CMD" --fix >/dev/null 2>&1 || true
  # After fix, the file should contain the preamble marker
  TOTAL=$((TOTAL + 1))
  if grep -q 'PREAMBLE_SECTION_START' "$CTO_FLEET_DIR/team-fix-missing/SKILL.md"; then
    PASS=$((PASS + 1))
    echo "  PASS: preamble inserted into previously-missing file"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: preamble not found after --fix"
  fi
  # Verify the file also kept its original content
  assert_contains "original content preserved" "Some other section" "$(cat "$CTO_FLEET_DIR/team-fix-missing/SKILL.md")"
teardown

# ─── Test 5: --fix repairs mismatched preamble ───────────────
echo "Test: --fix updates outdated preamble"
setup
  create_skill_with_correct_preamble "team-dev"
  create_skill_wrong_preamble "team-fix-wrong"
  "$SYNC_CMD" --fix >/dev/null 2>&1 || true
  fixed_content="$(cat "$CTO_FLEET_DIR/team-fix-wrong/SKILL.md")"
  # Should contain the canonical preamble (update-check command)
  assert_contains "canonical preamble present" "cto-fleet-update-check" "$fixed_content"
  # Old preamble should be gone
  TOTAL=$((TOTAL + 1))
  if echo "$fixed_content" | grep -q 'echo "old preamble"'; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: old preamble content still present after fix"
  else
    PASS=$((PASS + 1))
    echo "  PASS: old preamble replaced"
  fi
  # Skill body preserved
  assert_contains "skill body preserved" "Actual skill body" "$fixed_content"
teardown

# ─── Test 6: --dry-run does not modify files ─────────────────
echo "Test: --dry-run does not modify files"
setup
  create_skill_with_correct_preamble "team-dev"
  create_skill_wrong_preamble "team-dryrun"
  original="$(cat "$CTO_FLEET_DIR/team-dryrun/SKILL.md")"
  result="$("$SYNC_CMD" --dry-run 2>&1 || true)"
  after="$(cat "$CTO_FLEET_DIR/team-dryrun/SKILL.md")"
  assert_eq "file unchanged after dry-run" "$original" "$after"
  assert_contains "dry-run mentioned in output" "dry-run" "$result"
teardown

# ─── Test 7: --skills filters to specific skills ─────────────
echo "Test: --skills filter"
setup
  create_skill_with_correct_preamble "team-dev"
  create_skill_with_correct_preamble "team-alpha"
  create_skill_wrong_preamble "team-beta"
  # Only check team-alpha (which is correct) — should pass
  assert_exit_zero "--skills=team-alpha passes (correct)" "$SYNC_CMD" --skills=team-alpha
  # Only check team-beta (which is wrong) — should fail
  assert_exit_nonzero "--skills=team-beta fails (outdated)" "$SYNC_CMD" --skills=team-beta
teardown

# ─── Summary ──────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
