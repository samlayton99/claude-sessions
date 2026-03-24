#!/bin/bash
# Unit tests for sessions.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/sessions.sh"

PASS=0
FAIL=0
TESTS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_contains() {
  local label="$1" output="$2" expected="$3"
  TESTS=$((TESTS + 1))
  if echo "$output" | grep -qF -- "$expected"; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: $label"
  else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: $label"
    echo "    expected to contain: $expected"
    echo "    got: $output"
  fi
}

assert_not_contains() {
  local label="$1" output="$2" unexpected="$3"
  TESTS=$((TESTS + 1))
  if echo "$output" | grep -qF -- "$unexpected"; then
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: $label"
    echo "    expected NOT to contain: $unexpected"
  else
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: $label"
  fi
}

assert_exit_code() {
  local label="$1" actual="$2" expected="$3"
  TESTS=$((TESTS + 1))
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: $label"
  else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: $label"
    echo "    expected exit code $expected, got $actual"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  TESTS=$((TESTS + 1))
  if [ -f "$path" ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: $label"
  else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: $label"
    echo "    file not found: $path"
  fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  TESTS=$((TESTS + 1))
  if [ ! -f "$path" ]; then
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC}: $label"
  else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC}: $label"
    echo "    file should not exist: $path"
  fi
}

# --- Setup ---

FAKE_HOME=$(mktemp -d)
FAKE_CWD="/tmp/test-project"
FAKE_PROJ=$(echo "$FAKE_CWD" | sed 's|/|-|g')
PROJ_DIR="$FAKE_HOME/.claude/projects/$FAKE_PROJ"
SESSIONS_DIR="$FAKE_HOME/.claude/sessions"

mkdir -p "$PROJ_DIR"
mkdir -p "$SESSIONS_DIR"

# Helper: run the script with a faked HOME and PWD
run_sessions() {
  HOME="$FAKE_HOME" bash -c "cd '$FAKE_CWD' && '$SCRIPT' $*" 2>&1 || true
}

# Capture exit code too
run_sessions_rc() {
  local rc=0
  HOME="$FAKE_HOME" bash -c "cd '$FAKE_CWD' && '$SCRIPT' $*" 2>&1 || rc=$?
  echo "$rc"
}

# Helper: create a session file with optional title
create_session() {
  local sid="$1" title="${2:-}" first_msg="${3:-hello world}"
  local fpath="$PROJ_DIR/$sid.jsonl"
  if [ -n "$title" ]; then
    echo "{\"type\":\"custom-title\",\"customTitle\":\"$title\",\"sessionId\":\"$sid\"}" > "$fpath"
  fi
  echo "{\"type\":\"user\",\"message\":{\"content\":\"$first_msg\"}}" >> "$fpath"
  echo "{\"type\":\"user\",\"message\":{\"content\":\"second message\"}}" >> "$fpath"
}

cleanup() {
  rm -rf "$FAKE_HOME"
  mkdir -p "$PROJ_DIR"
  mkdir -p "$SESSIONS_DIR"
}

# We need the fake CWD to exist for cd
mkdir -p "$FAKE_CWD"

# ============================================================
echo "=== Test: list with no sessions ==="
# ============================================================
cleanup

output=$(run_sessions)
assert_contains "shows project path" "$output" "$FAKE_CWD"
assert_contains "shows no sessions" "$output" "No sessions found"
assert_contains "shows flags" "$output" "--find"

# ============================================================
echo ""
echo "=== Test: list sessions ==="
# ============================================================
cleanup
create_session "aaa-111" "my-auth-session" "implement auth flow"
create_session "bbb-222" "refactor-db" "refactor database layer"
create_session "ccc-333" "" "unnamed session msg"

output=$(run_sessions)
assert_contains "shows named session 1" "$output" "my-auth-session"
assert_contains "shows named session 2" "$output" "refactor-db"
assert_contains "shows unnamed marker" "$output" "(unnamed)"
assert_contains "shows first message" "$output" "implement auth flow"
assert_contains "shows total count" "$output" "3 session(s)"

# ============================================================
echo ""
echo "=== Test: find sessions ==="
# ============================================================

output=$(run_sessions '--find "auth"')
assert_contains "find matches auth session" "$output" "my-auth-session"
assert_not_contains "find excludes non-match" "$output" "refactor-db"
assert_contains "shows match count" "$output" "1 session(s)"

# ============================================================
echo ""
echo "=== Test: find with no match ==="
# ============================================================

output=$(run_sessions '--find "zzz-nonexistent"')
assert_contains "no match message" "$output" "No sessions found matching"

# ============================================================
echo ""
echo "=== Test: find requires query ==="
# ============================================================

rc=$(run_sessions_rc '--find')
# The output from run_sessions will show usage; rc captures exit code
output=$(run_sessions '--find')
assert_contains "shows usage" "$output" "Usage"

# ============================================================
echo ""
echo "=== Test: delete by name (dry run) ==="
# ============================================================

output=$(run_sessions '--delete "my-auth-session"')
assert_contains "shows session to delete" "$output" "my-auth-session"
assert_contains "awaits confirmation" "$output" "AWAITING_CONFIRMATION"

# Verify file still exists after dry run
assert_file_exists "session file survives dry run" "$PROJ_DIR/aaa-111.jsonl"

# ============================================================
echo ""
echo "=== Test: delete by name (confirmed) ==="
# ============================================================

output=$(run_sessions '--delete "my-auth-session" --yes')
assert_contains "reports deletion" "$output" "Deleted"
assert_file_not_exists "session file removed" "$PROJ_DIR/aaa-111.jsonl"

# ============================================================
echo ""
echo "=== Test: delete nonexistent session ==="
# ============================================================

output=$(run_sessions '--delete "no-such-session"')
assert_contains "reports not found" "$output" "No session found"

# ============================================================
echo ""
echo "=== Test: delete unnamed sessions (dry run) ==="
# ============================================================

# ccc-333 is unnamed
output=$(run_sessions '--delete')
assert_contains "shows unnamed session" "$output" "ccc-333"
assert_contains "awaits confirmation" "$output" "AWAITING_CONFIRMATION"
assert_file_exists "unnamed file survives dry run" "$PROJ_DIR/ccc-333.jsonl"

# ============================================================
echo ""
echo "=== Test: delete unnamed sessions (confirmed) ==="
# ============================================================

output=$(run_sessions '--delete --yes')
assert_contains "reports deletion" "$output" "Deleted"
assert_file_not_exists "unnamed file removed" "$PROJ_DIR/ccc-333.jsonl"
# named session should still exist
assert_file_exists "named session preserved" "$PROJ_DIR/bbb-222.jsonl"

# ============================================================
echo ""
echo "=== Test: delete unnamed when none exist ==="
# ============================================================

output=$(run_sessions '--delete')
assert_contains "no unnamed message" "$output" "No unnamed sessions"

# ============================================================
echo ""
echo "=== Test: new session ==="
# ============================================================

output=$(run_sessions '--new "my-new-session"')
assert_contains "reports creation" "$output" "Created session"
assert_contains "mentions resume" "$output" "/resume"

# Check that exactly one new jsonl was created with the title
new_files=$(grep -rl "my-new-session" "$PROJ_DIR"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
TESTS=$((TESTS + 1))
if [ "$new_files" -eq 1 ]; then
  PASS=$((PASS + 1))
  echo -e "  ${GREEN}PASS${NC}: new session file created with title"
else
  FAIL=$((FAIL + 1))
  echo -e "  ${RED}FAIL${NC}: expected 1 file with title, found $new_files"
fi

# ============================================================
echo ""
echo "=== Test: new session duplicate name ==="
# ============================================================

output=$(run_sessions '--new "my-new-session"')
assert_contains "rejects duplicate" "$output" "already exists"

# ============================================================
echo ""
echo "=== Test: new session requires name ==="
# ============================================================

output=$(run_sessions '--new')
assert_contains "shows usage" "$output" "Usage"

# ============================================================
echo ""
echo "=== Test: unknown argument ==="
# ============================================================

output=$(run_sessions '--bogus')
assert_contains "rejects unknown flag" "$output" "Unknown argument"

# ============================================================
echo ""
echo "=== Test: no project directory ==="
# ============================================================

output=$(HOME="$FAKE_HOME" bash -c "cd /tmp && '$SCRIPT'" 2>&1 || true)
assert_contains "reports no sessions" "$output" "No sessions found"

# ============================================================
echo ""
echo "=== Test: agent files are ignored ==="
# ============================================================
cleanup
create_session "agent-xyz" "should-be-hidden" "agent msg"
create_session "normal-session" "visible" "normal msg"

output=$(run_sessions)
assert_not_contains "agent file excluded from list" "$output" "should-be-hidden"
assert_contains "normal session shown" "$output" "visible"

# ============================================================
echo ""
echo "=== Test: empty session file is ignored ==="
# ============================================================
cleanup
touch "$PROJ_DIR/empty-session.jsonl"
create_session "real-session" "real" "msg"

output=$(run_sessions)
assert_not_contains "empty file excluded" "$output" "empty-session"
assert_contains "real session shown" "$output" "real"

# ============================================================
echo ""
echo "=== Test: long first message is truncated ==="
# ============================================================
cleanup
long_msg=$(python3 -c "print('x' * 120)")
create_session "long-msg-session" "long-test" "$long_msg"

output=$(run_sessions)
assert_contains "message truncated with ellipsis" "$output" "..."

# --- Cleanup ---
rm -rf "$FAKE_HOME" "$FAKE_CWD"

# --- Summary ---
echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed, $TESTS total"
echo "==============================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
