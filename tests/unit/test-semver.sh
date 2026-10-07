#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/schemes/semver.sh"

assert_eq "$(semver_valid 1.2.3 && echo yes)" "yes" "1.2.3 is valid"
assert_eq "$(semver_valid 1.2.3-rc.1+build.5 && echo yes)" "yes" "1.2.3-rc.1+build.5 is valid"
assert_eq "$(semver_valid 1.2 && echo yes || echo no)" "no" "1.2 is not valid semver"
assert_eq "$(semver_valid v1.2.3 && echo yes || echo no)" "no" "v1.2.3 is not valid semver"

assert_eq "$(semver_compare 1.0.0 2.0.0)" "-1" "1.0.0 < 2.0.0"
assert_eq "$(semver_compare 2.0.0 1.0.0)" "1" "2.0.0 > 1.0.0"
assert_eq "$(semver_compare 1.0.0 1.0.0)" "0" "1.0.0 == 1.0.0"
assert_eq "$(semver_compare 1.2.3+build1 1.2.3+build2)" "0" "build metadata ignored in compare"

# Official precedence example, semver.org spec item #11:
# 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta
#   < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
seq=(1.0.0-alpha 1.0.0-alpha.1 1.0.0-alpha.beta 1.0.0-beta 1.0.0-beta.2 1.0.0-beta.11 1.0.0-rc.1 1.0.0)
i=0
while [ "$i" -lt $((${#seq[@]} - 1)) ]; do
  a="${seq[$i]}"; b="${seq[$((i + 1))]}"
  assert_eq "$(semver_compare "$a" "$b")" "-1" "$a < $b (spec precedence example)"
  assert_eq "$(semver_compare "$b" "$a")" "1" "$b > $a (spec precedence example)"
  i=$((i + 1))
done

assert_eq "$(semver_classify 1.2.3 2.0.0)" "major" "1.2.3 -> 2.0.0 is major"
assert_eq "$(semver_classify 1.2.3 1.3.0)" "minor" "1.2.3 -> 1.3.0 is minor"
assert_eq "$(semver_classify 1.2.3 1.2.4)" "patch" "1.2.3 -> 1.2.4 is patch"
assert_eq "$(semver_classify 1.2.3 1.2.3)" "unchanged" "1.2.3 -> 1.2.3 is unchanged"
assert_eq "$(semver_classify 1.2.3+b1 1.2.3+b2)" "build-only" "build metadata only is build-only"
assert_eq "$(semver_classify 1.2.3 1.2.2)" "downgrade" "1.2.3 -> 1.2.2 is a downgrade"
assert_eq "$(semver_classify 1.2.3-rc.1 1.2.3-rc.2)" "prerelease" "rc.1 -> rc.2 is prerelease"
assert_eq "$(semver_classify 1.2.3-rc.1 1.2.3)" "release" "rc.1 -> final is release"
assert_eq "$(semver_classify 1.2.3-rc.1 1.2.2)" "downgrade" "rc.1 of 1.2.3 -> 1.2.2 is a downgrade"
assert_eq "$(semver_classify 1.2.3 abc)" "invalid-head" "non-semver head is invalid-head"
assert_eq "$(semver_classify abc 1.2.3)" "invalid-base" "non-semver base is invalid-base"

assert_eq "$(semver_is_dev 1.3.0-dev.1 && echo yes || echo no)" "yes" "1.3.0-dev.1 is a dev version"
assert_eq "$(semver_is_dev 1.3.0-rc.1 && echo yes || echo no)" "yes" "1.3.0-rc.1 is a dev version"
assert_eq "$(semver_is_dev 1.3.0+build.5 && echo yes || echo no)" "no" "build metadata alone is not a dev version"
assert_eq "$(semver_is_dev 1.3.0 && echo yes || echo no)" "no" "1.3.0 is not a dev version"

assert_summary
exit $?
