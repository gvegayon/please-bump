#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/comment.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CALL_LOG="$WORK/gh-calls.log"

# --- scenario 1: no existing sticky comment -> POST ---
gh() {
  echo "$*" >> "$CALL_LOG"
  if [ "$1" = "api" ] && [ "$2" != "--method" ]; then
    echo "[]"   # comment listing: none exist yet
    return 0
  fi
  return 0
}
: > "$CALL_LOG"
echo "hello" > "$WORK/body.txt"
comment_post "acme/widgets" "42" "$WORK/body.txt"
assert_eq "$?" "0" "comment_post succeeds when gh succeeds"
assert_contains "$(cat "$CALL_LOG")" "--method POST" "no existing comment -> POST is used"
assert_contains "$(cat "$CALL_LOG")" "repos/acme/widgets/issues/42/comments" "POST targets the right issue-comments endpoint"

# --- scenario 2: existing sticky comment (id 999) -> PATCH ---
gh() {
  echo "$*" >> "$CALL_LOG"
  if [ "$1" = "api" ] && [ "$2" != "--method" ]; then
    printf '[{"id":999,"body":"%s\\nold report"}]\n' "$REPORT_MARKER"
    return 0
  fi
  return 0
}
: > "$CALL_LOG"
comment_post "acme/widgets" "42" "$WORK/body.txt"
assert_eq "$?" "0" "comment_post succeeds on the update path too"
assert_contains "$(cat "$CALL_LOG")" "--method PATCH" "existing sticky comment -> PATCH is used"
assert_contains "$(cat "$CALL_LOG")" "issues/comments/999" "PATCH targets the found comment id"

# --- scenario 3: gh fails (e.g. read-only fork-PR token) -> caller can see failure ---
gh() {
  if [ "$1" = "api" ] && [ "$2" != "--method" ]; then
    echo "[]"
    return 0
  fi
  return 1
}
comment_post "acme/widgets" "42" "$WORK/body.txt"
assert_ne "$?" "0" "comment_post reports failure instead of masking it"

assert_summary
exit $?
