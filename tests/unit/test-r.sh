#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/schemes/r.sh"

assert_eq "$(r_valid 1.2.3 && echo yes)" "yes" "1.2.3 is valid"
assert_eq "$(r_valid 1.2-3 && echo yes)" "yes" "1.2-3 is valid"
assert_eq "$(r_valid 1.2.3.9000 && echo yes)" "yes" "1.2.3.9000 (devel) is valid"
assert_eq "$(r_valid 1.2.3-rc1 && echo yes || echo no)" "no" "rc1 suffix is not valid R version"

assert_eq "$(r_compare 1.2-3 1.2.3)" "0" "dash and dot separators are equivalent"
assert_eq "$(r_compare 1.9.0 1.10.0)" "-1" "1.9.0 < 1.10.0 (numeric, not lexical)"

assert_eq "$(r_classify 1.2.3 2.0.0)" "major" "major bump"
assert_eq "$(r_classify 1.2.3 1.3.0)" "minor" "minor bump"
assert_eq "$(r_classify 1.2.3 1.2.4)" "patch" "patch bump"
assert_eq "$(r_classify 1.2.3 1.2.3.9000)" "devel" "devel-suffix bump"
assert_eq "$(r_classify 1.2.3.9000 1.2.3.9001)" "devel" "devel-suffix increment"
assert_eq "$(r_classify 1.2.3 1.2.3)" "unchanged" "no change"
assert_eq "$(r_classify 1.2-3 1.2.3)" "unchanged" "dash/dot equivalent forms are unchanged"
assert_eq "$(r_classify 1.2.3 1.2.2)" "downgrade" "downgrade detected"
assert_eq "$(r_classify 1.2.3 abc)" "invalid-head" "non-R-version head"

assert_summary
exit $?
