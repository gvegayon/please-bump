#!/usr/bin/env bash
# Minimal, dependency-free assertion helpers for tests/run-tests.sh.
# Bash 3.2 compatible (no associative arrays, no `local -n`, no `[[ ]]` reliance
# beyond what 3.2 supports) so it runs identically on macOS and Ubuntu runners.

ASSERT_PASS=0
ASSERT_FAIL=0

_assert_fail() {
  ASSERT_FAIL=$((ASSERT_FAIL + 1))
  echo "  FAIL: $1"
  shift
  while [ "$#" -gt 0 ]; do
    echo "        $1"
    shift
  done
}

_assert_pass() {
  ASSERT_PASS=$((ASSERT_PASS + 1))
}

# assert_eq <actual> <expected> <description>
assert_eq() {
  if [ "$1" = "$2" ]; then
    _assert_pass
  else
    _assert_fail "$3" "expected: [$2]" "actual:   [$1]"
  fi
}

# assert_ne <actual> <not-expected> <description>
assert_ne() {
  if [ "$1" != "$2" ]; then
    _assert_pass
  else
    _assert_fail "$3" "expected NOT: [$2]" "actual:       [$1]"
  fi
}

# assert_contains <haystack> <needle> <description>
assert_contains() {
  case "$1" in
    *"$2"*) _assert_pass ;;
    *) _assert_fail "$3" "expected to contain: [$2]" "actual: [$1]" ;;
  esac
}

# assert_status <actual-exit-code> <expected-exit-code> <description>
assert_status() {
  assert_eq "$1" "$2" "$3"
}

assert_summary() {
  echo ""
  echo "  ---"
  echo "  $ASSERT_PASS passed, $ASSERT_FAIL failed"
  if [ "$ASSERT_FAIL" -gt 0 ]; then
    return 1
  fi
  return 0
}
