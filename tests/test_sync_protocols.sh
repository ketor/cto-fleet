#!/usr/bin/env bash
# Unit tests for bin/sync-protocols
# Run: bash tests/test_sync_protocols.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNC_CMD="$SCRIPT_DIR/bin/sync-protocols"
PASS=0
FAIL=0
TOTAL=0

# ─── Helpers ─────────────────────────────────────────────────
setup() {
  TEST_DIR="$(mktemp -d)"
  export CTO_FLEET_DIR="$TEST_DIR/cto-fleet"
  mkdir -p "$CTO_FLEET_DIR/bin" "$CTO_FLEET_DIR/protocols"
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
    echo "    expected: $(echo "$expected" | head -3)"
    echo "    actual:   $(echo "$actual" | head -3)"
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

assert_not_contains() {
  TOTAL=$((TOTAL + 1))
  local desc="$1" pattern="$2" actual="$3"
  if echo "$actual" | grep -q "$pattern"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (pattern '$pattern' was found but should not be)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
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

# ─── Standard test fixtures ─────────────────────────────────
create_registry() {
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
# Protocol registry
PREAMBLE_SECTION   | protocols/preamble.md   | *          |          | after_frontmatter
HANDOFF_SECTION    | HANDOFF.md              | TeamCreate |          | after:TeamCreate
CONSENSUS_SECTION  | protocols/consensus.md  | TeamCreate | excluded | end_of_file
EOF
}

create_single_registry() {
  # Only preamble for simpler tests
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
PREAMBLE_SECTION | protocols/preamble.md | * | | after_frontmatter
EOF
}

create_preamble_source() {
  cat > "$CTO_FLEET_DIR/protocols/preamble.md" << 'EOF'
<!-- PREAMBLE_SECTION_START -->
## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE`: upgrade.
<!-- PREAMBLE_SECTION_END -->
EOF
}

create_handoff_source() {
  cat > "$CTO_FLEET_DIR/HANDOFF.md" << 'EOF'
# Handoff Spec

Some content above.

<!-- HANDOFF_SECTION_START -->
## File-Based Handoff

All agents must use file-based handoff.

1. Write to /tmp/{team-name}/
2. SendMessage with path only
<!-- HANDOFF_SECTION_END -->
EOF
}

create_consensus_source() {
  cat > "$CTO_FLEET_DIR/protocols/consensus.md" << 'EOF'
<!-- CONSENSUS_SECTION_START -->
### Consensus Calculation

Score >= 60%: auto-merge.
<!-- CONSENSUS_SECTION_END -->
EOF
}

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

If output shows `UPGRADE_AVAILABLE`: upgrade.
<!-- PREAMBLE_SECTION_END -->

Actual skill body.
EOF
}

create_skill_outdated_preamble() {
  local name="$1"
  mkdir -p "$CTO_FLEET_DIR/$name"
  cat > "$CTO_FLEET_DIR/$name/SKILL.md" << 'EOF'
---
name: test-skill
description: test
---

<!-- PREAMBLE_SECTION_START -->
## Preamble (run first)

Old preamble content.
<!-- PREAMBLE_SECTION_END -->

Actual skill body.
EOF
}

create_skill_missing_preamble() {
  local name="$1"
  mkdir -p "$CTO_FLEET_DIR/$name"
  cat > "$CTO_FLEET_DIR/$name/SKILL.md" << 'EOF'
---
name: no-preamble
description: test
---

This skill has no preamble.

## Some section

Content here.
EOF
}

create_skill_with_teamcreate() {
  local name="$1"
  mkdir -p "$CTO_FLEET_DIR/$name"
  cat > "$CTO_FLEET_DIR/$name/SKILL.md" << 'EOF'
---
name: team-skill
description: test
---

<!-- PREAMBLE_SECTION_START -->
## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE`: upgrade.
<!-- PREAMBLE_SECTION_END -->

Use TeamCreate to spawn agents.

Actual skill body.
EOF
}

create_skill_legacy_preamble() {
  local name="$1"
  mkdir -p "$CTO_FLEET_DIR/$name"
  cat > "$CTO_FLEET_DIR/$name/SKILL.md" << 'EOF'
---
name: legacy-skill
description: test
---

## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE`: upgrade.

---

Actual skill body.
EOF
}

# ─── Test 1: Registry parsing (comments skipped, fields parsed) ─
echo "Test 1: Registry parsing"
setup
  create_registry
  create_preamble_source
  create_handoff_source
  create_consensus_source
  create_skill_with_correct_preamble "team-test1"
  result="$("$SYNC_CMD" --verbose 2>&1 || true)"
  assert_contains "PREAMBLE_SECTION in output" "PREAMBLE_SECTION" "$result"
  assert_contains "HANDOFF_SECTION in output" "HANDOFF_SECTION" "$result"
  assert_contains "CONSENSUS_SECTION in output" "CONSENSUS_SECTION" "$result"
teardown

# ─── Test 2: Check detects matching section → exit 0 ─────────
echo "Test 2: Check detects matching section"
setup
  create_single_registry
  create_preamble_source
  create_skill_with_correct_preamble "team-ok"
  assert_exit_zero "matching section exits 0" "$SYNC_CMD" --skills=team-ok
teardown

# ─── Test 3: Check detects outdated section → exit 1 ─────────
echo "Test 3: Check detects outdated section"
setup
  create_single_registry
  create_preamble_source
  create_skill_outdated_preamble "team-outdated"
  result="$("$SYNC_CMD" --skills=team-outdated 2>&1 || true)"
  assert_contains "reports OUTDATED" "OUTDATED" "$result"
  assert_exit_nonzero "outdated exits non-zero" "$SYNC_CMD" --skills=team-outdated
teardown

# ─── Test 4: Check detects missing section → exit 1 ──────────
echo "Test 4: Check detects missing section"
setup
  create_single_registry
  create_preamble_source
  create_skill_missing_preamble "team-missing"
  result="$("$SYNC_CMD" --skills=team-missing 2>&1 || true)"
  assert_contains "reports MISSING" "MISSING" "$result"
  assert_exit_nonzero "missing exits non-zero" "$SYNC_CMD" --skills=team-missing
teardown

# ─── Test 5: Fix updates outdated section ─────────────────────
echo "Test 5: Fix updates outdated section"
setup
  create_single_registry
  create_preamble_source
  create_skill_outdated_preamble "team-fix"
  "$SYNC_CMD" --fix --skills=team-fix >/dev/null 2>&1 || true
  fixed="$(cat "$CTO_FLEET_DIR/team-fix/SKILL.md")"
  assert_contains "canonical content present" "cto-fleet-update-check" "$fixed"
  assert_not_contains "old content removed" "Old preamble content" "$fixed"
  assert_contains "skill body preserved" "Actual skill body" "$fixed"
teardown

# ─── Test 6: Fix inserts missing section at after_frontmatter ─
echo "Test 6: Fix inserts at after_frontmatter"
setup
  create_single_registry
  create_preamble_source
  create_skill_missing_preamble "team-insert-fm"
  "$SYNC_CMD" --fix --skills=team-insert-fm >/dev/null 2>&1 || true
  fixed="$(cat "$CTO_FLEET_DIR/team-insert-fm/SKILL.md")"
  assert_contains "preamble inserted" "PREAMBLE_SECTION_START" "$fixed"
  assert_contains "original content preserved" "Some section" "$fixed"
  # Verify preamble is after frontmatter
  TOTAL=$((TOTAL + 1))
  fm_line=$(grep -n '^<!-- PREAMBLE_SECTION_START -->' "$CTO_FLEET_DIR/team-insert-fm/SKILL.md" | head -1 | cut -d: -f1)
  second_dash=$(grep -n '^---$' "$CTO_FLEET_DIR/team-insert-fm/SKILL.md" | sed -n '2p' | cut -d: -f1)
  if [ "$fm_line" -gt "$second_dash" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: preamble inserted after frontmatter"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: preamble not after frontmatter (preamble=$fm_line, fm_end=$second_dash)"
  fi
teardown

# ─── Test 7: Fix inserts missing section at after:KEYWORD ─────
echo "Test 7: Fix inserts at after:KEYWORD"
setup
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
HANDOFF_SECTION | HANDOFF.md | TeamCreate | | after:TeamCreate
EOF
  create_handoff_source
  create_skill_with_teamcreate "team-insert-kw"
  "$SYNC_CMD" --fix --skills=team-insert-kw >/dev/null 2>&1 || true
  fixed="$(cat "$CTO_FLEET_DIR/team-insert-kw/SKILL.md")"
  assert_contains "handoff inserted" "HANDOFF_SECTION_START" "$fixed"
  # Verify it's after TeamCreate
  TOTAL=$((TOTAL + 1))
  tc_line=$(grep -n 'TeamCreate' "$CTO_FLEET_DIR/team-insert-kw/SKILL.md" | head -1 | cut -d: -f1)
  hs_line=$(grep -n 'HANDOFF_SECTION_START' "$CTO_FLEET_DIR/team-insert-kw/SKILL.md" | head -1 | cut -d: -f1)
  if [ "$hs_line" -gt "$tc_line" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: handoff inserted after TeamCreate"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: handoff not after TeamCreate (tc=$tc_line, hs=$hs_line)"
  fi
teardown

# ─── Test 8: Fix inserts missing section at end_of_file ───────
echo "Test 8: Fix inserts at end_of_file"
setup
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
CONSENSUS_SECTION | protocols/consensus.md | TeamCreate | | end_of_file
EOF
  create_consensus_source
  create_skill_with_teamcreate "team-insert-eof"
  "$SYNC_CMD" --fix --skills=team-insert-eof >/dev/null 2>&1 || true
  fixed="$(cat "$CTO_FLEET_DIR/team-insert-eof/SKILL.md")"
  assert_contains "consensus inserted" "CONSENSUS_SECTION_START" "$fixed"
  # Should be near end of file
  TOTAL=$((TOTAL + 1))
  total_lines=$(wc -l < "$CTO_FLEET_DIR/team-insert-eof/SKILL.md")
  cs_line=$(grep -n 'CONSENSUS_SECTION_END' "$CTO_FLEET_DIR/team-insert-eof/SKILL.md" | head -1 | cut -d: -f1)
  if [ "$cs_line" -ge "$((total_lines - 2))" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: consensus near end of file"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: consensus not near end (cs=$cs_line, total=$total_lines)"
  fi
teardown

# ─── Test 9: Dry-run does not modify files ────────────────────
echo "Test 9: Dry-run does not modify files"
setup
  create_single_registry
  create_preamble_source
  create_skill_outdated_preamble "team-dryrun"
  original="$(cat "$CTO_FLEET_DIR/team-dryrun/SKILL.md")"
  result="$("$SYNC_CMD" --dry-run --skills=team-dryrun 2>&1 || true)"
  after="$(cat "$CTO_FLEET_DIR/team-dryrun/SKILL.md")"
  assert_eq "file unchanged after dry-run" "$original" "$after"
  assert_contains "dry-run in output" "dry-run" "$result"
teardown

# ─── Test 10: Gate condition skips non-matching skills ────────
echo "Test 10: Gate condition skips"
setup
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
HANDOFF_SECTION | HANDOFF.md | TeamCreate | | after:TeamCreate
EOF
  create_handoff_source
  # Skill without TeamCreate
  create_skill_missing_preamble "team-no-gate"
  result="$("$SYNC_CMD" --verbose --skills=team-no-gate 2>&1 || true)"
  assert_contains "shows skipped" "skipped" "$result"
  # Should exit 0 since nothing needed checking
  assert_exit_zero "skipped skills exit 0" "$SYNC_CMD" --skills=team-no-gate
teardown

# ─── Test 11: Exclude condition skips matching skills ─────────
echo "Test 11: Exclude condition skips"
setup
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
CONSENSUS_SECTION | protocols/consensus.md | TeamCreate | excluded | end_of_file
EOF
  create_consensus_source
  mkdir -p "$CTO_FLEET_DIR/team-excluded"
  cat > "$CTO_FLEET_DIR/team-excluded/SKILL.md" << 'EOF'
---
name: team-excluded
description: test
---

Use TeamCreate.
This file contains the word excluded.
EOF
  result="$("$SYNC_CMD" --verbose --skills=team-excluded 2>&1 || true)"
  assert_contains "shows excluded" "excluded" "$result"
  assert_exit_zero "excluded skills exit 0" "$SYNC_CMD" --skills=team-excluded
teardown

# ─── Test 12: --sections filter limits processing ────────────
echo "Test 12: --sections filter"
setup
  create_registry
  create_preamble_source
  create_handoff_source
  create_consensus_source
  create_skill_outdated_preamble "team-filter"
  # Only check PREAMBLE_SECTION (should report outdated)
  result="$("$SYNC_CMD" --sections=PREAMBLE_SECTION --skills=team-filter 2>&1 || true)"
  assert_contains "PREAMBLE reported" "PREAMBLE_SECTION" "$result"
  assert_not_contains "HANDOFF not reported" "HANDOFF_SECTION:" "$result"
  # Also test shorthand (without _SECTION suffix)
  result2="$("$SYNC_CMD" --sections=PREAMBLE --skills=team-filter 2>&1 || true)"
  assert_contains "shorthand works" "PREAMBLE_SECTION" "$result2"
teardown

# ─── Test 13: --remove strips section from all skills ─────────
echo "Test 13: --remove strips section"
setup
  create_single_registry
  create_preamble_source
  create_skill_with_correct_preamble "team-rm1"
  create_skill_with_correct_preamble "team-rm2"
  "$SYNC_CMD" --remove=PREAMBLE_SECTION --fix >/dev/null 2>&1 || true
  rm1="$(cat "$CTO_FLEET_DIR/team-rm1/SKILL.md")"
  rm2="$(cat "$CTO_FLEET_DIR/team-rm2/SKILL.md")"
  assert_not_contains "rm1: markers removed" "PREAMBLE_SECTION_START" "$rm1"
  assert_not_contains "rm2: markers removed" "PREAMBLE_SECTION_START" "$rm2"
  assert_contains "rm1: body preserved" "Actual skill body" "$rm1"
teardown

# ─── Test 14: Multi-section fix processes correctly ───────────
echo "Test 14: Multi-section fix (4 sections)"
setup
  # Create a 4-section registry
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
PREAMBLE_SECTION   | protocols/preamble.md   | *          |          | after_frontmatter
HANDOFF_SECTION    | HANDOFF.md              | TeamCreate |          | after:TeamCreate
CONSENSUS_SECTION  | protocols/consensus.md  | TeamCreate |          | end_of_file
ERROR_SECTION      | protocols/error.md      | TeamCreate |          | end_of_file
EOF
  create_preamble_source
  create_handoff_source
  create_consensus_source
  cat > "$CTO_FLEET_DIR/protocols/error.md" << 'EOF'
<!-- ERROR_SECTION_START -->
### Error Handling

Handle errors gracefully.
<!-- ERROR_SECTION_END -->
EOF

  # Skill with only preamble (correct) + TeamCreate but missing 3 sections
  create_skill_with_teamcreate "team-multi"
  "$SYNC_CMD" --fix --skills=team-multi >/dev/null 2>&1 || true
  fixed="$(cat "$CTO_FLEET_DIR/team-multi/SKILL.md")"
  assert_contains "has preamble" "PREAMBLE_SECTION_START" "$fixed"
  assert_contains "has handoff" "HANDOFF_SECTION_START" "$fixed"
  assert_contains "has consensus" "CONSENSUS_SECTION_START" "$fixed"
  assert_contains "has error" "ERROR_SECTION_START" "$fixed"
  # Verify order: preamble before handoff before consensus
  TOTAL=$((TOTAL + 1))
  p_line=$(grep -n 'PREAMBLE_SECTION_START' "$CTO_FLEET_DIR/team-multi/SKILL.md" | head -1 | cut -d: -f1)
  h_line=$(grep -n 'HANDOFF_SECTION_START' "$CTO_FLEET_DIR/team-multi/SKILL.md" | head -1 | cut -d: -f1)
  c_line=$(grep -n 'CONSENSUS_SECTION_START' "$CTO_FLEET_DIR/team-multi/SKILL.md" | head -1 | cut -d: -f1)
  e_line=$(grep -n 'ERROR_SECTION_START' "$CTO_FLEET_DIR/team-multi/SKILL.md" | head -1 | cut -d: -f1)
  if [ "$p_line" -lt "$h_line" ] && [ "$h_line" -lt "$c_line" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: sections in correct order (p=$p_line h=$h_line c=$c_line e=$e_line)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: sections out of order (p=$p_line h=$h_line c=$c_line e=$e_line)"
  fi
teardown

# ─── Test 15: --migrate-preamble converts heading to markers ─
echo "Test 15: --migrate-preamble"
setup
  create_single_registry
  create_preamble_source
  create_skill_legacy_preamble "team-legacy"
  "$SYNC_CMD" --migrate-preamble --skills=team-legacy >/dev/null 2>&1 || true
  migrated="$(cat "$CTO_FLEET_DIR/team-legacy/SKILL.md")"
  assert_contains "has START marker" "PREAMBLE_SECTION_START" "$migrated"
  assert_contains "has END marker" "PREAMBLE_SECTION_END" "$migrated"
  assert_contains "body preserved" "Actual skill body" "$migrated"
  # The old --- separator should be gone (between preamble and body)
  # Check that the --- right after preamble is removed
  TOTAL=$((TOTAL + 1))
  end_marker_line=$(grep -n 'PREAMBLE_SECTION_END' "$CTO_FLEET_DIR/team-legacy/SKILL.md" | head -1 | cut -d: -f1)
  next_line=$(sed -n "$((end_marker_line + 1))p" "$CTO_FLEET_DIR/team-legacy/SKILL.md")
  if [ "$next_line" != "---" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: --- separator removed after migration"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: --- separator still present after migration"
  fi
teardown

# ─── Test 16: Legacy preamble detection in check mode ─────────
echo "Test 16: Legacy preamble detection"
setup
  create_single_registry
  create_preamble_source
  create_skill_legacy_preamble "team-legacy-check"
  result="$("$SYNC_CMD" --verbose --skills=team-legacy-check 2>&1 || true)"
  assert_contains "detects legacy" "legacy" "$result"
  assert_contains "suggests migration" "migrate-preamble" "$result"
teardown

# ─── Test 17: Unpaired markers → error ────────────────────────
echo "Test 17: Unpaired markers"
setup
  create_single_registry
  create_preamble_source
  mkdir -p "$CTO_FLEET_DIR/team-unpaired"
  cat > "$CTO_FLEET_DIR/team-unpaired/SKILL.md" << 'EOF'
---
name: unpaired
description: test
---

<!-- PREAMBLE_SECTION_START -->
## Preamble (run first)

Missing end marker.

Actual skill body.
EOF
  result="$("$SYNC_CMD" --skills=team-unpaired 2>&1 || true)"
  assert_contains "reports error for unpaired" "unpaired.*marker\|Error.*marker\|error" "$result"
teardown

# ─── Test 18: Empty registry → exit 0 ────────────────────────
echo "Test 18: Empty registry"
setup
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
# Only comments
# No actual entries
EOF
  create_skill_with_correct_preamble "team-empty-reg"
  # Empty registry means 0 sections → nothing to check → exit 0
  assert_exit_zero "empty registry exits 0" "$SYNC_CMD" --skills=team-empty-reg
teardown

# ─── Test 19: Missing source file → error ─────────────────────
echo "Test 19: Missing source file"
setup
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
MISSING_SECTION | protocols/nonexistent.md | * | | after_frontmatter
EOF
  create_skill_with_correct_preamble "team-miss-src"
  result="$("$SYNC_CMD" --skills=team-miss-src 2>&1 || true)"
  assert_contains "reports missing source" "not found\|Error" "$result"
  assert_exit_nonzero "missing source exits non-zero" "$SYNC_CMD" --skills=team-miss-src
teardown

# ─── Summary ─────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
