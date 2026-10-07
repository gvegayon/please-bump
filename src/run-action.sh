#!/usr/bin/env bash
# GitHub Actions integration glue for action.yml's main step: runs main.sh,
# writes the step summary, sets this composite action's outputs, and decides
# the step's own exit code from `fail-on-error`. A setup/config error (main.sh
# exiting before producing any result JSON at all) is always fatal, regardless
# of fail-on-error -- that is a misconfiguration, not "the PR did not bump".
set -uo pipefail

RUN_ACTION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$RUN_ACTION_SCRIPT_DIR/report.sh"

: "${PLEASE_BUMP_FAIL_ON_ERROR:=true}"
: "${PLEASE_BUMP_COMMENT_TITLE:=Version bump check}"
: "${GITHUB_OUTPUT:=/dev/null}"

# Release tag names and the PR's labels/body, for the release policy and
# waivers. Asked of the API live (not just read from the event payload) so a
# re-run sees releases cut and labels added since the event fired. Anything
# the API can't answer is left unset: main.sh then falls back to git tags,
# and to the payload copies of the labels/body below.
if [ -n "${GH_TOKEN:-}" ] && [ -n "${PLEASE_BUMP_REPOSITORY:-}" ] && command -v gh > /dev/null 2>&1; then
  if release_tags="$(gh api --paginate "repos/$PLEASE_BUMP_REPOSITORY/releases" --jq '.[] | select(.draft | not) | .tag_name' 2>/dev/null)"; then
    export PLEASE_BUMP_RELEASE_TAGS="$release_tags"
  else
    echo "please-bump: warning: could not list GitHub releases; falling back to git tags." >&2
  fi
  if [ -n "${PLEASE_BUMP_PR_NUMBER:-}" ]; then
    if pr_json="$(gh api "repos/$PLEASE_BUMP_REPOSITORY/pulls/$PLEASE_BUMP_PR_NUMBER" 2>/dev/null)"; then
      PLEASE_BUMP_PR_LABELS_JSON="$(jq -c '[.labels[]?.name]' <<< "$pr_json")"
      PLEASE_BUMP_PR_BODY="$(jq -r '.body // ""' <<< "$pr_json")"
    else
      echo "please-bump: warning: could not fetch the PR; using labels/body from the event payload." >&2
    fi
  fi
fi
PLEASE_BUMP_PR_LABELS="$(jq -r '.[]?' <<< "${PLEASE_BUMP_PR_LABELS_JSON:-[]}" 2>/dev/null || true)"
export PLEASE_BUMP_PR_LABELS
export PLEASE_BUMP_PR_BODY="${PLEASE_BUMP_PR_BODY:-}"

result_json="$(mktemp)"
stderr_log="$(mktemp)"

set +e
bash "$RUN_ACTION_SCRIPT_DIR/main.sh" > "$result_json" 2> "$stderr_log"
set -e

cat "$stderr_log" >&2

if ! jq -e . "$result_json" > /dev/null 2>&1; then
  echo "please-bump: could not produce a result (see the error above)." >&2
  echo "please-bump: this always fails the job, independent of fail-on-error." >&2
  rm -f "$result_json" "$stderr_log"
  exit 1
fi

json="$(cat "$result_json")"
report_md="$(pwd)/please-bump-report.md"
report_render "$json" "$PLEASE_BUMP_COMMENT_TITLE" > "$report_md"
report_write_summary "$json" "$PLEASE_BUMP_COMMENT_TITLE"

result="$(jq -r '.result' <<< "$json")"
versions="$(jq -c '[.groups[] | {key: .name, value: {base_version, head_version, bump, status, reason}}] | from_entries' <<< "$json")"
json_out="$(pwd)/please-bump-result.json"
cp "$result_json" "$json_out"

{
  echo "result=$result"
  echo "report=$report_md"
  echo "json=$json_out"
  echo "versions<<PLEASE_BUMP_VERSIONS_EOF"
  echo "$versions"
  echo "PLEASE_BUMP_VERSIONS_EOF"
} >> "$GITHUB_OUTPUT"

rm -f "$result_json" "$stderr_log"

if [ "$result" = "fail" ] && [ "$PLEASE_BUMP_FAIL_ON_ERROR" = "true" ]; then
  echo "please-bump: version bump check failed. See the step summary above for details." >&2
  exit 1
fi
exit 0
