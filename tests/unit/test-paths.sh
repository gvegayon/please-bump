#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/paths.sh"

assert_eq "$(paths_file_included "program-a/DESCRIPTION" "program-a/" "" && echo yes || echo no)" "yes" \
  "directory prefix matches a file inside it"
assert_eq "$(paths_file_included "program-b/DESCRIPTION" "program-a/" "" && echo yes || echo no)" "no" \
  "directory prefix does not match a sibling directory"
assert_eq "$(paths_file_included "program-ab/DESCRIPTION" "program-a/" "" && echo yes || echo no)" "no" \
  "directory prefix does not false-match a differently-named sibling"

assert_eq "$(paths_file_included "program-a/vendor/lib.c" "program-a/"$'\n'"" "program-a/vendor/" && echo yes || echo no)" "no" \
  "exclusion under an included directory is excluded"
assert_eq "$(paths_file_included "program-a/src/lib.c" "program-a/" "program-a/vendor/" && echo yes || echo no)" "yes" \
  "sibling of an exclusion is still included"

assert_eq "$(paths_file_included "d/version.h" "d/version.h" "" && echo yes || echo no)" "yes" \
  "exact-path entry (no trailing slash) matches that file"
assert_eq "$(paths_file_included "d/version.c" "d/version.h" "" && echo yes || echo no)" "no" \
  "exact-path entry does not match a different file"
assert_eq "$(paths_file_included "d/version.h" "d/*.h" "" && echo yes || echo no)" "yes" \
  "glob entry matches"

changed=$'program-a/DESCRIPTION\nengine/README.md'
assert_eq "$(paths_group_touched "$changed" "program-a/" "")" "true" \
  "group is touched when a changed file falls under its paths"
assert_eq "$(paths_group_touched "$changed" "program-b/" "")" "false" \
  "group is not touched when no changed file falls under its paths"

assert_summary
exit $?
