#!/usr/bin/env bash
# Unit tests for cto-fleet-config
# Run: bash tests/test_config.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_CMD="$SCRIPT_DIR/bin/cto-fleet-config"
PASS=0
FAIL=0
TOTAL=0

# Setup temp dir for each test
setup() {
  TEST_DIR="$(mktemp -d)"
  export CTO_FLEET_STATE_DIR="$TEST_DIR"
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

assert_file_perm() {
  TOTAL=$((TOTAL + 1))
  local desc="$1" path="$2" expected_perm="$3"
  local actual_perm
  actual_perm="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null)"
  if [ "$actual_perm" = "$expected_perm" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc (expected $expected_perm, got $actual_perm)"
  fi
}

# ─── Test: Basic set and get ───────────────────────────────────
echo "Test: basic set and get"
setup
  "$CONFIG_CMD" set mykey myvalue
  result="$("$CONFIG_CMD" get mykey)"
  assert_eq "set then get returns value" "myvalue" "$result"
teardown

# ─── Test: Get nonexistent key returns exit 1 ─────────────────
echo "Test: get nonexistent key"
setup
  "$CONFIG_CMD" set dummy dummyval  # ensure config file exists
  result="$("$CONFIG_CMD" get nonexistent 2>/dev/null || true)"
  assert_eq "nonexistent key returns empty" "" "$result"
TOTAL=$((TOTAL + 1))
  if "$CONFIG_CMD" get nonexistent 2>/dev/null; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: nonexistent key should exit 1"
  else
    PASS=$((PASS + 1))
    echo "  PASS: nonexistent key exits non-zero"
  fi
teardown

# ─── Test: Overwrite existing key ──────────────────────────────
echo "Test: overwrite existing key"
setup
  "$CONFIG_CMD" set mykey old_value
  "$CONFIG_CMD" set mykey new_value
  result="$("$CONFIG_CMD" get mykey)"
  assert_eq "overwritten key returns new value" "new_value" "$result"
teardown

# ─── Test: Multiple keys ──────────────────────────────────────
echo "Test: multiple keys"
setup
  "$CONFIG_CMD" set key1 val1
  "$CONFIG_CMD" set key2 val2
  r1="$("$CONFIG_CMD" get key1)"
  r2="$("$CONFIG_CMD" get key2)"
  assert_eq "key1 correct" "val1" "$r1"
  assert_eq "key2 correct" "val2" "$r2"
teardown

# ─── Test: Special characters in value (sed injection prevention) ──
echo "Test: special characters in value"
setup
  "$CONFIG_CMD" set mykey "value/with/slashes"
  result="$("$CONFIG_CMD" get mykey)"
  assert_eq "slashes in value preserved" "value/with/slashes" "$result"
teardown

echo "Test: ampersand in value"
setup
  "$CONFIG_CMD" set mykey "val&ue"
  result="$("$CONFIG_CMD" get mykey)"
  assert_eq "ampersand in value preserved" "val&ue" "$result"
teardown

# ─── Test: Directory permissions ───────────────────────────────
echo "Test: directory permissions"
setup
  "$CONFIG_CMD" set testkey testval
  assert_file_perm "state dir is 700" "$TEST_DIR" "700"
  assert_file_perm "config file is 600" "$TEST_DIR/config.yaml" "600"
teardown

# ─── Test: Empty key rejected ─────────────────────────────────
echo "Test: empty key rejected"
TOTAL=$((TOTAL + 1))
setup
  if "$CONFIG_CMD" set "" "val" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: empty key should be rejected"
  else
    PASS=$((PASS + 1))
    echo "  PASS: empty key rejected"
  fi
teardown

# ─── Test: List command ───────────────────────────────────────
echo "Test: list command"
setup
  "$CONFIG_CMD" set a 1
  "$CONFIG_CMD" set b 2
  result="$("$CONFIG_CMD" list | wc -l | tr -d ' ')"
  assert_eq "list shows 2 entries" "2" "$result"
teardown

# ─── Test: Value with spaces round-trip ──────────────────────
echo "Test: value with spaces"
setup
  "$CONFIG_CMD" set mykey "hello world foo"
  result="$("$CONFIG_CMD" get mykey)"
  assert_eq "spaces in value preserved" "hello world foo" "$result"
teardown

# ─── Test: Value with YAML special characters ────────────────
echo "Test: YAML special chars in value (colon)"
setup
  "$CONFIG_CMD" set mykey "host:8080"
  result="$("$CONFIG_CMD" get mykey)"
  assert_eq "colon in value preserved" "host:8080" "$result"
teardown

echo "Test: YAML special chars in value (hash)"
setup
  "$CONFIG_CMD" set mykey "color #fff"
  result="$("$CONFIG_CMD" get mykey)"
  assert_eq "hash in value preserved" "color #fff" "$result"
teardown

echo "Test: YAML special chars in value (exclamation)"
setup
  "$CONFIG_CMD" set mykey "hello!"
  result="$("$CONFIG_CMD" get mykey)"
  assert_eq "exclamation in value preserved" "hello!" "$result"
teardown

# ─── Summary ──────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
