#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/schemes/pep440.sh"

assert_eq "$(pep440_valid 1.2.3 && echo yes)" "yes" "1.2.3 is valid"
assert_eq "$(pep440_valid 1.2.3rc1 && echo yes)" "yes" "1.2.3rc1 is valid"
assert_eq "$(pep440_valid 1.2.3.post1 && echo yes)" "yes" "1.2.3.post1 is valid"
assert_eq "$(pep440_valid 1.2.3.dev1 && echo yes)" "yes" "1.2.3.dev1 is valid"
assert_eq "$(pep440_valid 1!1.0 && echo yes)" "yes" "epoch form is valid"
assert_eq "$(pep440_valid 1.2.3+local.1 && echo yes)" "yes" "local segment is valid"
assert_eq "$(pep440_valid 1.2.3-alpha && echo yes || echo no)" "no" "unsupported alias spelling rejected"

# PEP 440 ordering example (subset of the spec's own table):
# 1.0.dev1 < 1.0a1 < 1.0a1.post1.dev1 (skipped, unsupported combo) ...
# using the simpler documented chain:
# 1.0.dev0 < 1.0a1 < 1.0b1 < 1.0rc1 < 1.0 < 1.0.post1
seq=(1.0.dev0 1.0a1 1.0b1 1.0rc1 1.0 1.0.post1)
i=0
while [ "$i" -lt $((${#seq[@]} - 1)) ]; do
  a="${seq[$i]}"; b="${seq[$((i + 1))]}"
  assert_eq "$(pep440_compare "$a" "$b")" "-1" "$a < $b (PEP 440 ordering)"
  assert_eq "$(pep440_compare "$b" "$a")" "1" "$b > $a (PEP 440 ordering)"
  i=$((i + 1))
done

assert_eq "$(pep440_compare 1.2.3+local1 1.2.3+local2)" "0" "local segment ignored in compare"
assert_eq "$(pep440_compare 1.0 1.0.0)" "0" "trailing zero release segment is equivalent"

assert_eq "$(pep440_classify 1.2.0 1.3.0)" "minor" "clean release bump is minor"
assert_eq "$(pep440_classify 1.2.0 2.0.0)" "major" "clean release bump is major"
assert_eq "$(pep440_classify 1.2.0 1.2.1)" "patch" "clean release bump is patch"
assert_eq "$(pep440_classify 1.2.0 1.3.0rc1)" "prerelease" "jump into a prerelease is 'prerelease'"
assert_eq "$(pep440_classify 1.2.0rc1 1.2.0rc2)" "prerelease" "rc1 -> rc2 is prerelease"
assert_eq "$(pep440_classify 1.2.0rc1 1.2.0)" "release" "rc1 -> final is release"
assert_eq "$(pep440_classify 1.2.0 1.2.0.post1)" "post" "post-release bump"
assert_eq "$(pep440_classify 1.2.0 1.3.0.dev1)" "dev" "dev-only bump of a new release"
assert_eq "$(pep440_classify 1!1.0 2!1.0)" "epoch" "epoch bump"
assert_eq "$(pep440_classify 1.2.3 1.2.3)" "unchanged" "no change"
assert_eq "$(pep440_classify 1.2.3+local1 1.2.3+local2)" "build-only" "local-segment-only change"
assert_eq "$(pep440_classify 1.2.3 1.2.2)" "downgrade" "downgrade detected"
assert_eq "$(pep440_classify 1.2.3 1.2.3alpha1)" "invalid-head" "unsupported alias spelling is invalid"

assert_eq "$(pep440_is_dev 1.3.0.dev0 && echo yes || echo no)" "yes" "1.3.0.dev0 is a dev version"
assert_eq "$(pep440_is_dev 1.3.0rc1 && echo yes || echo no)" "yes" "1.3.0rc1 is a dev version"
assert_eq "$(pep440_is_dev 1.3.0.post1 && echo yes || echo no)" "no" "1.3.0.post1 is not a dev version"
assert_eq "$(pep440_is_dev 1.3.0 && echo yes || echo no)" "no" "1.3.0 is not a dev version"

assert_summary
exit $?
