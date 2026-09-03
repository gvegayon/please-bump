#!/usr/bin/env bash
# Exercises run-action.sh's GitHub Actions glue: $GITHUB_OUTPUT,
# $GITHUB_STEP_SUMMARY, the report/json file outputs, and fail-on-error.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
RUN_ACTION_SH="$PLEASE_BUMP_ROOT/src/run-action.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
mkdir -p "$REPO/.github"
cd "$REPO"
git init -q .
git config user.email t@example.com
git config user.name t

cat > .github/please-bump.yaml <<'YAML'
version: 1
groups:
  pkg:
    files: [VERSION]
    parts:
      version: '^(.+)$'
    scheme: semver
YAML
echo "1.0.0" > VERSION
git add -A && git commit -q -m base
BASE_SHA="$(git rev-parse HEAD)"
# Touch VERSION (so the group counts as "changed") without actually
# bumping the version on the first line -> should fail as "not bumped".
{ echo "1.0.0"; echo "# trailing comment, no real bump"; } > VERSION
git add -A && git commit -q -m "touch VERSION without bumping it"
HEAD_SHA="$(git rev-parse HEAD)"

_out="$WORK/gh-output"
_summary="$WORK/gh-summary"
: > "$_out"; : > "$_summary"

PLEASE_BUMP_BASE_REF="$BASE_SHA" \
  PLEASE_BUMP_HEAD_REF="$HEAD_SHA" \
  PLEASE_BUMP_CONFIG=".github/please-bump.yaml" \
  PLEASE_BUMP_PRESETS_DIR="$PLEASE_BUMP_ROOT/presets" \
  PLEASE_BUMP_FAIL_ON_ERROR="true" \
  PLEASE_BUMP_COMMENT_TITLE="Version bump check" \
  GITHUB_OUTPUT="$_out" \
  GITHUB_STEP_SUMMARY="$_summary" \
  bash "$RUN_ACTION_SH"
status=$?

assert_eq "$status" "1" "fail-on-error=true exits non-zero when the check fails"
assert_contains "$(cat "$_out")" "result=fail" "GITHUB_OUTPUT records result=fail"
assert_contains "$(cat "$_out")" "report=" "GITHUB_OUTPUT records a report path"
assert_contains "$(cat "$_out")" "json=" "GITHUB_OUTPUT records a json path"
assert_contains "$(cat "$_out")" "versions<<PLEASE_BUMP_VERSIONS_EOF" "GITHUB_OUTPUT uses a heredoc for the multi-line versions output"
assert_contains "$(cat "$_summary")" "Version bump check ❌" "GITHUB_STEP_SUMMARY got the rendered report"

report_path="$(grep '^report=' "$_out" | cut -d= -f2-)"
json_path="$(grep '^json=' "$_out" | cut -d= -f2-)"
assert_eq "$(test -f "$report_path" && echo yes)" "yes" "the report file output actually exists"
assert_eq "$(test -f "$json_path" && echo yes)" "yes" "the json file output actually exists"
assert_eq "$(jq -r '.result' "$json_path")" "fail" "the json file output has the right result"

# --- fail-on-error=false: still reports fail, but exits 0 ---
: > "$_out"; : > "$_summary"
PLEASE_BUMP_BASE_REF="$BASE_SHA" \
  PLEASE_BUMP_HEAD_REF="$HEAD_SHA" \
  PLEASE_BUMP_CONFIG=".github/please-bump.yaml" \
  PLEASE_BUMP_PRESETS_DIR="$PLEASE_BUMP_ROOT/presets" \
  PLEASE_BUMP_FAIL_ON_ERROR="false" \
  GITHUB_OUTPUT="$_out" \
  GITHUB_STEP_SUMMARY="$_summary" \
  bash "$RUN_ACTION_SH"
status2=$?
assert_eq "$status2" "0" "fail-on-error=false exits zero even though the check failed"
assert_contains "$(cat "$_out")" "result=fail" "result output still accurately reports fail"

# --- a broken config is always fatal, regardless of fail-on-error ---
cat > .github/please-bump.yaml <<'YAML'
version: 1
groups:
  broken:
    files: [x]
    preset: does-not-exist
YAML
git add -A && git commit -q -m "break the config"
BROKEN_SHA="$(git rev-parse HEAD)"
: > "$_out"
PLEASE_BUMP_BASE_REF="$BASE_SHA" \
  PLEASE_BUMP_HEAD_REF="$BROKEN_SHA" \
  PLEASE_BUMP_CONFIG=".github/please-bump.yaml" \
  PLEASE_BUMP_PRESETS_DIR="$PLEASE_BUMP_ROOT/presets" \
  PLEASE_BUMP_FAIL_ON_ERROR="false" \
  GITHUB_OUTPUT="$_out" \
  bash "$RUN_ACTION_SH"
status3=$?
assert_ne "$status3" "0" "a broken config fails even with fail-on-error=false"

assert_summary
exit $?
