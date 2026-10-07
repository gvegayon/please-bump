#!/usr/bin/env bash
# main_tag_regex / main_released_versions / main_waiver_reason from src/main.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/main.sh"

assert_eq "$(main_tag_regex 'v?{version}' g)" '^v?(.+)$' "default pattern: optional leading v"
assert_eq "$(main_tag_regex '{group}-v{version}' my.pkg)" '^my\.pkg-v(.+)$' "group is substituted and escaped"
assert_eq "$(main_tag_regex 'release/{version}' g)" '^release/(.+)$' "literal text is kept"
assert_eq "$(main_tag_regex 'v.{version}+x' g)" '^v\.(.+)\+x$' "regex metacharacters in literal text are escaped"

MAIN_RELEASE_TAGS="v1.2.3
1.2.4
nightly
v1.3.0-rc.1
pkg-v2.0.0"
assert_eq "$(main_released_versions g semver 'v?{version}' | cut -f1 | tr '\n' ' ')" "1.2.3 1.2.4 1.3.0-rc.1 " "only tags valid for the scheme count"
assert_eq "$(main_released_versions pkg semver '{group}-v{version}')" "$(printf '2.0.0\tpkg-v2.0.0')" "group-prefixed tags"

MAIN_WAIVER_LABELS="no-version-bump"
MAIN_WAIVER_MARKER="true"
assert_eq "$(PLEASE_BUMP_PR_LABELS='bug' main_waiver_reason g)" "" "an unrelated label does not waive"
assert_eq "$(PLEASE_BUMP_PR_LABELS='no-version-bump' main_waiver_reason g)" "label:no-version-bump" "the waiver label waives"
assert_eq "$(PLEASE_BUMP_PR_BODY='text [please-bump skip] more' main_waiver_reason g)" "marker" "a bare marker waives every group"
assert_eq "$(PLEASE_BUMP_PR_BODY='[please-bump skip: a, g ]' main_waiver_reason g)" "marker" "a marker listing the group waives it"
assert_eq "$(PLEASE_BUMP_PR_BODY='[please-bump skip: a]' main_waiver_reason g)" "" "a marker listing other groups does not"
assert_eq "$(PLEASE_BUMP_PR_BODY='please-bump skip' main_waiver_reason g)" "" "the marker needs its brackets"
MAIN_WAIVER_MARKER="false"
assert_eq "$(PLEASE_BUMP_PR_BODY='[please-bump skip]' main_waiver_reason g)" "" "marker: false disables the marker"

assert_summary
exit $?
