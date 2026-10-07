#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/schemes/numeric.sh"

assert_eq "$(numeric_valid 1.2.3 && echo yes)" "yes" "1.2.3 is valid"
assert_eq "$(numeric_valid 2026.09.1 && echo yes)" "yes" "CalVer-shaped is valid"
assert_eq "$(numeric_valid 1.2.3-rc1 && echo yes || echo no)" "no" "suffix is not valid numeric"

assert_eq "$(numeric_compare 1.2 1.2.0)" "0" "1.2 == 1.2.0 (padding)"
assert_eq "$(numeric_compare 1.9 1.10)" "-1" "1.9 < 1.10 (numeric, not lexical)"
assert_eq "$(numeric_compare 2.0.0 1.9.9)" "1" "2.0.0 > 1.9.9"

assert_eq "$(numeric_classify 1.2.3 2.0.0 major,minor,patch)" "major" "labeled major"
assert_eq "$(numeric_classify 1.2.3 1.3.0 major,minor,patch)" "minor" "labeled minor"
assert_eq "$(numeric_classify 1.2.3 1.2.4 major,minor,patch)" "patch" "labeled patch"
assert_eq "$(numeric_classify 2026.09.1 2026.09.2 year,month,micro)" "micro" "CalVer micro bump"
assert_eq "$(numeric_classify 2026.09.1 2026.10.1 year,month,micro)" "month" "CalVer month bump"
assert_eq "$(numeric_classify 2026.09.1 2027.01.1 year,month,micro)" "year" "CalVer year bump"
assert_eq "$(numeric_classify 1.2.3 2.0.0)" "component-1" "unlabeled position falls back to component-N"
assert_eq "$(numeric_classify 1.2.3 1.2.3)" "unchanged" "no change"
assert_eq "$(numeric_classify 1.2.3 1.2.2 major,minor,patch)" "downgrade" "downgrade detected"
assert_eq "$(numeric_classify 1.2 1.2.3 major,minor,patch)" "patch" "shorter base pads with 0"

assert_eq "$(numeric_is_dev 2026.10.1 && echo yes || echo no)" "no" "numeric versions are never dev versions"

assert_summary
exit $?
