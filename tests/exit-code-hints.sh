#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^explain_exit_code[(][)] [{]/,/^}/' "$CORE_DIR/api/exitcodes.func")"
eval "$(awk '/^_eh_hint_from_log[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOG="$TEST_DIR/log"
WARN="$TEST_DIR/warn"
passed=0 failed=0
_eh_warn() { echo "$1" >>"$WARN"; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

# Exit status 1 is the command's own verdict; errno 1 (EPERM) is something else.
expect "exit 1 is not explained as EPERM" 0 "$(explain_exit_code 1 | grep -c 'Operation not permitted')"
expect "the container fallback table agrees" 0 "$(grep -E '^ *1[)] echo' "$CORE_DIR/core/error_handler.func" | grep -c 'Operation not permitted')"

: >"$WARN"
printf '%s\n' 'Scope: all 36 workspace projects' ' ERR_PNPM_OUTDATED_LOCKFILE  Cannot install with "frozen-lockfile" because pnpm-lock.yaml is not up to date with <ROOT>/server/package.json' >"$LOG"
_eh_hint_from_log "$LOG"
expect "a stale pnpm lockfile is named" 1 "$(grep -c 'lockfile does not match' "$WARN")"
expect "the fallback is suggested" 1 "$(grep -c 'no-frozen-lockfile' "$WARN")"

: >"$WARN"
printf '%s\n' '[OK] Git DNS: github.com:(ok)' '[ERROR] in line 34: exit code 1' >"$LOG"
_eh_hint_from_log "$LOG"
expect "the network check line raises no hint" 0 "$(wc -l <"$WARN" | tr -d ' ')"

# The host classifies the combined log itself; a bare DNS used to match the network check line.
expect "pve host grep no longer matches the word DNS alone" 0 "$(grep -c 'resolve|DNS|' "$CORE_DIR/pve/backend.func")"
expect "incus host grep no longer matches the word DNS alone" 0 "$(grep -c 'resolve|DNS|' "$CORE_DIR/incus/backend.func")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
