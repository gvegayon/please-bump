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
git tag v1.0.0
BASE_SHA="$(git rev-parse HEAD)"
# Touch VERSION (so the group counts as "changed") without actually
# bumping the version on the first line. 1.0.0 is already tagged, so the
# default unchanged-policy (release) fails it as "already released".
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

# --- releases and PR labels come from the GitHub API (stubbed `gh`) ---
# Back to the base..head pair from the top: VERSION touched, 1.0.0 unchanged.
STUB="$WORK/stub-bin"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'SH'
#!/usr/bin/env bash
[ -n "${GH_STUB_FAIL:-}" ] && exit 1
case "$*" in
  *releases*) printf '%s\n' "${GH_STUB_RELEASES:-}" ;;
  *pulls*) printf '{"labels":[{"name":"%s"}],"body":""}\n' "${GH_STUB_LABEL:-}" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$STUB/gh"

_run_api() {
  : > "$_out"
  env PATH="$STUB:$PATH" \
    GH_TOKEN="dummy" PLEASE_BUMP_REPOSITORY="o/r" PLEASE_BUMP_PR_NUMBER="7" \
    PLEASE_BUMP_BASE_REF="$BASE_SHA" \
    PLEASE_BUMP_HEAD_REF="$HEAD_SHA" \
    PLEASE_BUMP_CONFIG=".github/please-bump.yaml" \
    PLEASE_BUMP_PRESETS_DIR="$PLEASE_BUMP_ROOT/presets" \
    PLEASE_BUMP_FAIL_ON_ERROR="true" \
    GITHUB_OUTPUT="$_out" \
    "$@" \
    bash "$RUN_ACTION_SH" 2> "$WORK/api-err.log"
}
_versions() { sed -n '/^versions<</,/^PLEASE_BUMP_VERSIONS_EOF/p' "$_out" | sed '1d;$d'; }

git checkout -q "$HEAD_SHA" -- .github/please-bump.yaml

# The git tag v1.0.0 exists, but no GitHub *release* does: the API wins.
_run_api GH_STUB_RELEASES=""
assert_eq "$?" "0" "api: no GitHub releases -> unchanged passes (git tag ignored)"
assert_eq "$(_versions | jq -r '.pkg.reason')" "no-release" "api: versions output carries the reason"

_run_api GH_STUB_RELEASES="v1.0.0"
assert_eq "$?" "1" "api: a GitHub release of 1.0.0 -> unchanged fails"

_run_api GH_STUB_RELEASES="v1.0.0" GH_STUB_LABEL="no-version-bump" PLEASE_BUMP_PR_LABELS_JSON='[]'
assert_eq "$?" "0" "api: a label found on the live PR waives (payload had none)"
assert_eq "$(_versions | jq -r '.pkg.status')" "waived" "api: status is waived"

_run_api GH_STUB_FAIL=1 PLEASE_BUMP_PR_LABELS_JSON='["no-version-bump"]'
assert_eq "$?" "0" "api down: falls back to git tags and the payload's labels"
assert_contains "$(cat "$WORK/api-err.log")" "falling back to git tags" "api down: warns about the fallback"

assert_summary
exit $?
