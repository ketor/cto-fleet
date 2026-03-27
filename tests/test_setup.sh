#!/usr/bin/env bash
# Unit tests for setup script
# Run: bash tests/test_setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETUP_CMD="$SCRIPT_DIR/setup"
PASS=0
FAIL=0
TOTAL=0

# ─── Helpers ─────────────────────────────────────────────────
setup() {
  TEST_DIR="$(mktemp -d)"
  # Create a fake cto-fleet repo structure
  FAKE_REPO="$TEST_DIR/cto-fleet"
  mkdir -p "$FAKE_REPO"

  # Create some fake skills with SKILL.md
  for skill in team-dev team-review drawio; do
    mkdir -p "$FAKE_REPO/$skill"
    echo "---" > "$FAKE_REPO/$skill/SKILL.md"
    echo "name: $skill" >> "$FAKE_REPO/$skill/SKILL.md"
    echo "---" >> "$FAKE_REPO/$skill/SKILL.md"
  done

  # Create a directory without SKILL.md (should be skipped)
  mkdir -p "$FAKE_REPO/bin"
  mkdir -p "$FAKE_REPO/tests"

  # Copy the setup script into the fake repo
  cp "$SETUP_CMD" "$FAKE_REPO/setup"
  chmod +x "$FAKE_REPO/setup"
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

assert_symlink() {
  TOTAL=$((TOTAL + 1))
  local desc="$1" path="$2"
  if [ -L "$path" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc ($path is not a symlink)"
  fi
}

assert_not_exists() {
  TOTAL=$((TOTAL + 1))
  local desc="$1" path="$2"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc ($path exists but shouldn't)"
  fi
}

# ─── Test 1: Normal install creates correct symlinks ─────────
echo "Test: normal install creates symlinks"
setup
  # Override HOME so setup installs to our temp dir
  FAKE_SKILLS="$TEST_DIR/home/.claude/skills"
  mkdir -p "$FAKE_SKILLS"
  HOME="$TEST_DIR/home" "$FAKE_REPO/setup" >/dev/null 2>&1
  assert_symlink "team-dev symlink created" "$FAKE_SKILLS/team-dev"
  assert_symlink "team-review symlink created" "$FAKE_SKILLS/team-review"
  assert_symlink "drawio symlink created" "$FAKE_SKILLS/drawio"
  # bin and tests should NOT be linked (no SKILL.md)
  assert_not_exists "bin not linked" "$FAKE_SKILLS/bin"
  assert_not_exists "tests not linked" "$FAKE_SKILLS/tests"
teardown

# ─── Test 2: --local installs to project directory ───────────
echo "Test: --local mode installs to project directory"
setup
  PROJECT_DIR="$TEST_DIR/my-project"
  mkdir -p "$PROJECT_DIR"
  (cd "$PROJECT_DIR" && "$FAKE_REPO/setup" --local) >/dev/null 2>&1
  LOCAL_SKILLS="$PROJECT_DIR/.claude/skills"
  assert_symlink "team-dev in local skills" "$LOCAL_SKILLS/team-dev"
  assert_symlink "drawio in local skills" "$LOCAL_SKILLS/drawio"
teardown

# ─── Test 3: Existing symlink gets updated ───────────────────
echo "Test: existing symlink updated"
setup
  FAKE_SKILLS="$TEST_DIR/home/.claude/skills"
  mkdir -p "$FAKE_SKILLS"
  # Create a stale symlink pointing elsewhere
  ln -snf "/nonexistent/old-path" "$FAKE_SKILLS/team-dev"
  old_target="$(readlink "$FAKE_SKILLS/team-dev")"
  assert_eq "old symlink points elsewhere" "/nonexistent/old-path" "$old_target"
  # Run setup — should update
  HOME="$TEST_DIR/home" "$FAKE_REPO/setup" >/dev/null 2>&1
  new_target="$(readlink "$FAKE_SKILLS/team-dev")"
  TOTAL=$((TOTAL + 1))
  if [ "$new_target" != "/nonexistent/old-path" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: symlink updated to new target"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: symlink still points to old target"
  fi
teardown

# ─── Test 4: Real directory is not overwritten ────────────────
echo "Test: real directory skipped"
setup
  FAKE_SKILLS="$TEST_DIR/home/.claude/skills"
  mkdir -p "$FAKE_SKILLS"
  # Create a real directory (not a symlink)
  mkdir -p "$FAKE_SKILLS/team-dev"
  echo "important" > "$FAKE_SKILLS/team-dev/user-data.txt"
  result="$(HOME="$TEST_DIR/home" "$FAKE_REPO/setup" 2>&1)"
  # The real directory should still be a directory, not a symlink
  TOTAL=$((TOTAL + 1))
  if [ -d "$FAKE_SKILLS/team-dev" ] && [ ! -L "$FAKE_SKILLS/team-dev" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: real directory preserved (not overwritten)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: real directory was overwritten"
  fi
  # User data should still be there
  TOTAL=$((TOTAL + 1))
  if [ -f "$FAKE_SKILLS/team-dev/user-data.txt" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: user data file preserved"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: user data file lost"
  fi
  # Output should mention skip
  TOTAL=$((TOTAL + 1))
  if echo "$result" | grep -q "skip"; then
    PASS=$((PASS + 1))
    echo "  PASS: skip message in output"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: no skip message in output"
  fi
teardown

# ─── Summary ──────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
