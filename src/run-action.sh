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
versions="$(jq -c '[.groups[] | {key: .name, value: {base_version, head_version, bump, status}}] | from_entries' <<< "$json")"
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
