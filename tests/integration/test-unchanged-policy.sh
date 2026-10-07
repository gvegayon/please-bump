#!/usr/bin/env bash
# End-to-end tests for unchanged-policy (release | dev | never), the release
# list sources (GitHub releases via $PLEASE_BUMP_RELEASE_TAGS, or git tags),
# and PR waivers (labels / body marker). Real throwaway git repos.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
MAIN_SH="$PLEASE_BUMP_ROOT/src/main.sh"
PRESETS_DIR="$PLEASE_BUMP_ROOT/presets"
. "$PLEASE_BUMP_ROOT/src/report.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
N=0

# _scenario <scheme> <base-version> <head-version> <extra-group-yaml> [top-level-yaml]
# Builds a fresh repo: VERSION at <base-version>, then a head commit that
# touches src/ and sets VERSION to <head-version>. Leaves $REPO, $BASE, $HEAD set.
_scenario() {
  local scheme="$1" bver="$2" hver="$3" extra="$4" top="${5:-}"
  N=$((N + 1))
  REPO="$WORK/repo$N"
  mkdir -p "$REPO/.github" "$REPO/src"
  cd "$REPO" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name t
  {
    echo "version: 1"
    [ -n "$top" ] && printf '%s\n' "$top"
    echo "groups:"
    echo "  pkg:"
    echo "    paths: [src/]"
    echo "    files: [VERSION]"
    echo "    parts:"
    echo "      version: '^(.+)\$'"
    echo "    scheme: $scheme"
    [ -n "$extra" ] && printf '%s\n' "$extra"
  } > .github/please-bump.yaml
  echo "$bver" > VERSION
  echo "a" > src/code
  git add -A && git commit -q -m base
  BASE="$(git rev-parse HEAD)"
  echo "$hver" > VERSION
  echo "b" > src/code
  git add -A && git commit -q -m head
  HEAD_SHA="$(git rev-parse HEAD)"
}

# _run [VAR=value ...] -> runs main.sh in $REPO with extra env, JSON to $WORK/out.json
_run() {
  ( cd "$REPO" \
    && env PLEASE_BUMP_BASE_REF="$BASE" \
       PLEASE_BUMP_HEAD_REF="$HEAD_SHA" \
       PLEASE_BUMP_CONFIG=".github/please-bump.yaml" \
       PLEASE_BUMP_PRESETS_DIR="$PRESETS_DIR" \
       "$@" \
       bash "$MAIN_SH" > "$WORK/out.json" 2> "$WORK/err.log" )
}

_f() { jq -r ".groups[0].$1 // \"\"" "$WORK/out.json"; }

# ---- release (default): no releases at all -> pass ----
_scenario semver 1.2.3 1.2.3 ""
_run PLEASE_BUMP_RELEASE_TAGS=""
assert_eq "$(_f status)" "pass" "release: unchanged with no release yet passes"
assert_eq "$(_f reason)" "no-release" "release: reason is no-release"
assert_eq "$(_f note)" "" "release: an answered (empty) release list adds no note"

# ---- release: unchanged and already released -> fail ----
_scenario semver 1.2.3 1.2.3 ""
_run PLEASE_BUMP_RELEASE_TAGS="v1.2.2
v1.2.3"
assert_eq "$(_f status)" "fail" "release: unchanged, already released, fails"
assert_eq "$(_f reason)" "released" "release: reason is released"
assert_contains "$(_f message)" "1.2.3 is already released (v1.2.3)" "release: message names the release tag"

# ---- release: R dev version, unreleased -> pass ----
_scenario r 1.2.3.9000 1.2.3.9000 ""
_run PLEASE_BUMP_RELEASE_TAGS="v1.2.3"
assert_eq "$(_f status)" "pass" "release: unchanged R dev version after a release passes"
assert_eq "$(_f reason)" "unreleased" "release: reason is unreleased"
assert_eq "$(_f latest_release)" "v1.2.3" "release: latest_release is reported"

# ---- release: bare tags (no leading v) match the default pattern ----
_scenario pep440 1.2.3 1.2.3 ""
_run PLEASE_BUMP_RELEASE_TAGS="1.2.3"
assert_eq "$(_f status)" "fail" "release: a bare '1.2.3' tag counts as a release by default"

# ---- release: bumped, but to an already-released version -> fail ----
_scenario semver 1.2.2 1.2.3 ""
_run PLEASE_BUMP_RELEASE_TAGS="v1.2.3"
assert_eq "$(_f status)" "fail" "release: bumping to an already-released version fails"
assert_eq "$(_f reason)" "released" "release: ...with reason released"

# ---- release: bumped, but still behind the latest release -> fail ----
_scenario r 1.2.2 1.2.2.9000 ""
_run PLEASE_BUMP_RELEASE_TAGS="v1.2.3"
assert_eq "$(_f status)" "fail" "release: a head behind the latest release fails"
assert_eq "$(_f reason)" "behind-release" "release: reason is behind-release"

# ---- release: a normal bump past the latest release -> pass ----
_scenario semver 1.2.3 1.3.0 ""
_run PLEASE_BUMP_RELEASE_TAGS="v1.2.3"
assert_eq "$(_f status)" "pass" "release: a real bump past the latest release passes"
assert_eq "$(_f bump)" "minor" "release: ...and keeps its bump label"
assert_eq "$(_f reason)" "" "release: ...with no reason"

# ---- a released prerelease: release policy fails, dev policy passes ----
_scenario semver 1.3.0-rc.1 1.3.0-rc.1 ""
_run PLEASE_BUMP_RELEASE_TAGS="v1.3.0-rc.1"
assert_eq "$(_f status)" "fail" "release: an unchanged prerelease that was published fails"
_scenario semver 1.3.0-rc.1 1.3.0-rc.1 "    unchanged-policy: dev"
_run PLEASE_BUMP_RELEASE_TAGS="v1.3.0-rc.1"
assert_eq "$(_f status)" "pass" "dev: the same unchanged prerelease passes"
assert_eq "$(_f reason)" "dev" "dev: reason is dev"

# ---- dev: a final version unchanged -> fail ----
_scenario pep440 1.2.3 1.2.3 "    unchanged-policy: dev"
_run
assert_eq "$(_f status)" "fail" "dev: an unchanged final version fails"
assert_eq "$(_f reason)" "not-bumped" "dev: reason is not-bumped"

# ---- never: unchanged fails even with no releases ----
_scenario semver 1.2.3 1.2.3 "    unchanged-policy: never"
_run PLEASE_BUMP_RELEASE_TAGS=""
assert_eq "$(_f status)" "fail" "never: unchanged fails even with no release yet"
assert_eq "$(_f message)" "not bumped" "never: message says not bumped"

# ---- tags source: real git tags, monorepo tag-pattern ----
_scenario semver 1.2.3 1.2.3 "    tag-pattern: '{group}-v{version}'" "release-source: tags"
git tag pkg-v1.2.3 "$BASE"
git tag other-v9.9.9 "$BASE"
_run PLEASE_BUMP_RELEASE_TAGS="ignored-because-source-is-tags"
assert_eq "$(_f status)" "fail" "tags: a '{group}-v{version}' git tag counts as a release"
assert_eq "$(_f note)" "" "tags: no note when tags exist"

# ---- releases source falls back to git tags when the list is unavailable ----
_scenario semver 1.2.3 1.2.3 ""
git tag v1.2.3 "$BASE"
_run
assert_eq "$(_f status)" "fail" "fallback: git tags are used when the release list is unavailable"
assert_contains "$(_f note)" "used git tags instead" "fallback: the report notes the fallback"

# ---- no tags at all (e.g. shallow clone): pass, but with a visible note ----
_scenario semver 1.2.3 1.2.3 "" "release-source: tags"
_run
assert_eq "$(_f status)" "pass" "no tags: passes as no-release"
assert_contains "$(_f note)" "fetch-depth: 0" "no tags: the note suggests fetch-depth: 0"

# ---- waivers ----
_scenario semver 1.2.3 1.2.3 "    unchanged-policy: never"
_run PLEASE_BUMP_PR_LABELS="bug
no-version-bump"
assert_eq "$(_f status)" "waived" "waiver: the default label waives a not-bumped failure"
assert_eq "$(_f reason)" "label:no-version-bump" "waiver: reason names the label"
assert_eq "$(jq -r .result "$WORK/out.json")" "pass" "waiver: a waived group does not fail the run"

_run PLEASE_BUMP_PR_BODY="Small fix. [please-bump skip: other-group]"
assert_eq "$(_f status)" "fail" "waiver: a marker naming another group does not apply"

_run PLEASE_BUMP_PR_BODY="Small fix. [please-bump skip: other-group, pkg]"
assert_eq "$(_f status)" "waived" "waiver: a marker naming this group applies"

_run PLEASE_BUMP_PR_BODY="[Please-Bump Skip]"
assert_eq "$(_f status)" "waived" "waiver: a bare marker applies, case-insensitively"
assert_eq "$(_f reason)" "marker" "waiver: reason is marker"

_scenario semver 1.2.3 1.2.3 "    unchanged-policy: never" "waiver:
  labels: [skip-bump]
  marker: false"
_run PLEASE_BUMP_PR_LABELS="no-version-bump" PLEASE_BUMP_PR_BODY="[please-bump skip]"
assert_eq "$(_f status)" "fail" "waiver: custom labels replace the default; marker can be disabled"
_run PLEASE_BUMP_PR_LABELS="skip-bump"
assert_eq "$(_f status)" "waived" "waiver: a custom label waives"

_scenario semver 1.2.3 1.2.3 ""
_run PLEASE_BUMP_RELEASE_TAGS="v1.2.3" PLEASE_BUMP_PR_LABELS="no-version-bump"
assert_eq "$(_f status)" "waived" "waiver: also excuses an already-released failure"

_scenario semver 1.2.3 1.2.2 ""
_run PLEASE_BUMP_PR_LABELS="no-version-bump"
assert_eq "$(_f status)" "fail" "waiver: never excuses a downgrade"
assert_eq "$(_f bump)" "downgrade" "waiver: ...which is still reported as a downgrade"

# ---- report rendering for the new outcomes ----
_scenario r 1.2.3.9000 1.2.3.9000 ""
_run PLEASE_BUMP_RELEASE_TAGS="v1.2.3"
assert_contains "$(report_render "$(cat "$WORK/out.json")")" "unchanged (unreleased; latest release \`v1.2.3\`)" "report: unreleased row"
_scenario semver 1.2.3 1.2.3 "    unchanged-policy: never"
_run PLEASE_BUMP_PR_LABELS="no-version-bump"
md="$(report_render "$(cat "$WORK/out.json")")"
assert_contains "$md" "☑️ waived (label \`no-version-bump\`)" "report: waived row"
assert_contains "$md" "Version bump check ✅" "report: a waived-only run is a pass"
_scenario semver 1.2.3 1.2.3 ""
_run PLEASE_BUMP_RELEASE_TAGS="v1.2.3"
assert_contains "$(report_render "$(cat "$WORK/out.json")")" "❌ already released" "report: already-released row"

assert_summary
