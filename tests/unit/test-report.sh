#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/report.sh"

json='{
  "base_ref": "main",
  "head_ref": "HEAD",
  "result": "fail",
  "groups": [
    {"name": "program-a", "status": "pass", "base_version": "1.2.0", "head_version": "1.3.0", "bump": "minor", "message": "", "files": []},
    {"name": "program-b", "status": "fail", "base_version": "0.4.1", "head_version": "0.4.1", "bump": "unchanged", "message": "program-b/__init__.py: not bumped", "files": []},
    {"name": "engine", "status": "skipped", "base_version": null, "head_version": null, "bump": null, "message": "no changes under this group'"'"'s paths", "files": []},
    {"name": "tools", "status": "fail", "base_version": null, "head_version": null, "bump": null, "message": "no version file found", "files": [{"file": "tools/pyproject.toml", "outcome": "skipped"}]}
  ]
}'

out="$(report_render "$json")"

assert_contains "$out" "$REPORT_MARKER" "report starts with the sticky-comment marker"
assert_contains "$out" "### Version bump check ❌" "overall failure shows the ❌ heading"
assert_contains "$out" "| program-a | 1.2.0 | 1.3.0 | ✅ **minor** update |" "passing group row"
assert_contains "$out" "| program-b | 0.4.1 | 0.4.1 | ❌ not bumped |" "failing (unchanged) group row"
assert_contains "$out" "| engine | — | — | ⏭️ skipped |" "skipped group row"
assert_contains "$out" "| tools | — | — | ❌ no version file found |" "empty group row"
assert_contains "$out" "program-b/__init__.py: not bumped" "failure detail message is included"
assert_contains "$out" "not found, skipped: tools/pyproject.toml" "skipped-file note is included"
assert_contains "$out" "Checked 4 group(s) against \`main\`" "footer names the base ref and group count"

pass_json='{"base_ref":"main","head_ref":"HEAD","result":"pass","groups":[
  {"name":"a","status":"pass","base_version":"1.0.0","head_version":"1.1.0","bump":"minor","message":"","files":[]}
]}'
pass_out="$(report_render "$pass_json" "Custom Title")"
assert_contains "$pass_out" "### Custom Title ✅" "custom title and pass icon both honored"

assert_summary
exit $?
