#!/usr/bin/env bash
# End-to-end tests: real throwaway git repos, real main.sh invocations.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
MAIN_SH="$PLEASE_BUMP_ROOT/src/main.sh"
PRESETS_DIR="$PLEASE_BUMP_ROOT/presets"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

_run() {
  # _run <repo-dir> <base-ref> <head-ref> -> writes JSON to $WORK/out.json, returns main.sh's exit code
  local repo="$1" base="$2" head="$3"
  ( cd "$repo" \
    && PLEASE_BUMP_BASE_REF="$base" \
       PLEASE_BUMP_HEAD_REF="$head" \
       PLEASE_BUMP_CONFIG=".github/please-bump.yaml" \
       PLEASE_BUMP_PRESETS_DIR="$PRESETS_DIR" \
       bash "$MAIN_SH" > "$WORK/out.json" )
  return $?
}

_status() { jq -r --arg g "$1" '.groups[] | select(.name == $g) | .status' "$WORK/out.json"; }
_bump()   { jq -r --arg g "$1" '.groups[] | select(.name == $g) | .bump'   "$WORK/out.json"; }
_msg()    { jq -r --arg g "$1" '.groups[] | select(.name == $g) | .message' "$WORK/out.json"; }
_base_v() { jq -r --arg g "$1" '.groups[] | select(.name == $g) | .base_version' "$WORK/out.json"; }
_head_v() { jq -r --arg g "$1" '.groups[] | select(.name == $g) | .head_version' "$WORK/out.json"; }

# ===================================================================
# Repo 1: multi-file groups, per-file schemes, monorepo paths, mixed
# rules (the C++ three-#define case), missing-file skip.
# ===================================================================
REPO1="$WORK/repo1"
mkdir -p "$REPO1/.github" "$REPO1/program-a" "$REPO1/program-b" "$REPO1/engine"
cd "$REPO1"
git init -q .
git config user.email t@example.com
git config user.name t

cat > .github/please-bump.yaml <<'YAML'
version: 1
groups:
  program-a:
    files: [program-a/DESCRIPTION, program-a/NEWS.md]
    regex: ['^Version:[[:space:]]*(.+)$', '^#[[:space:]]+progA[[:space:]]+(.+)$']
    scheme: r
    consistency: identical
  program-b:
    paths: ["program-b/"]
    files: [program-b/pyproject.toml]
    parts:
      version: '^version[[:space:]]*=[[:space:]]*"([^"]+)"'
    scheme: pep440
  engine:
    consistency: identical
    rules:
      - files: [engine/version.h]
        parts:
          major: 'ENGINE_VERSION_MAJOR[^0-9]*([0-9]+)'
          minor: 'ENGINE_VERSION_MINOR[^0-9]*([0-9]+)'
          patch: 'ENGINE_VERSION_PATCH[^0-9]*([0-9]+)'
        assemble: "{major}.{minor}.{patch}"
        scheme: numeric
        part-labels: [major, minor, patch]
  library:
    paths: ["library/"]
    files: [library/DESCRIPTION]
    parts:
      version: '^Version:[[:space:]]*(.+)$'
    scheme: r
YAML

cat > program-a/DESCRIPTION <<'D'
Package: progA
Version: 1.2.3
D
cat > program-a/NEWS.md <<'N'
# progA 1.2.3
N
cat > program-b/pyproject.toml <<'P'
[project]
version = "0.4.1"
P
cat > engine/version.h <<'H'
#define ENGINE_VERSION_MAJOR 2
#define ENGINE_VERSION_MINOR 1
#define ENGINE_VERSION_PATCH 0
H
mkdir -p library
cat > library/DESCRIPTION <<'D'
Package: library
Version: 3.0.0
D
git add -A && git commit -q -m base
R1_BASE="$(git rev-parse HEAD)"

sed -i.bak 's/Version: 1.2.3/Version: 1.2.4/' program-a/DESCRIPTION && rm program-a/DESCRIPTION.bak
sed -i.bak 's/# progA 1.2.3/# progA 1.2.4/' program-a/NEWS.md && rm program-a/NEWS.md.bak
sed -i.bak 's/ENGINE_VERSION_MINOR 1/ENGINE_VERSION_MINOR 2/' engine/version.h && rm engine/version.h.bak
echo "unrelated" > program-b/README-unrelated.md
git add -A && git commit -q -m "bump program-a and engine; touch program-b dir without bumping it"
R1_HEAD="$(git rev-parse HEAD)"

_run "$REPO1" "$R1_BASE" "$R1_HEAD"
r1_status=$?
assert_eq "$r1_status" "1" "repo1: overall run fails (program-b regressed)"
assert_eq "$(_status program-a)" "pass" "repo1: program-a (two consistent files, R scheme) passes"
assert_eq "$(_bump program-a)" "patch" "repo1: program-a classified as a patch bump"
assert_eq "$(_status engine)" "pass" "repo1: engine (C++ three-#define assembly) passes"
assert_eq "$(_bump engine)" "minor" "repo1: engine classified as a minor bump"
assert_eq "$(_status program-b)" "fail" "repo1: program-b (touched dir, unbumped version) fails"
assert_contains "$(_msg program-b)" "not bumped" "repo1: program-b message says not bumped"
assert_eq "$(_status library)" "skipped" "repo1: library (untouched paths) is skipped"
assert_eq "$(_base_v library)" "3.0.0" "repo1: skipped library still reports its current version as base_version"
assert_eq "$(_head_v library)" "3.0.0" "repo1: skipped library still reports its current version as head_version"

# ===================================================================
# Repo 2: consistency=identical mismatch, and a package with no
# NEWS.md at all (on-missing: skip, the default).
# ===================================================================
REPO2="$WORK/repo2"
mkdir -p "$REPO2/.github" "$REPO2/pkg" "$REPO2/pkg2"
cd "$REPO2"
git init -q .
git config user.email t@example.com
git config user.name t

cat > .github/please-bump.yaml <<'YAML'
version: 1
groups:
  pkg-with-news:
    files: [pkg/DESCRIPTION, pkg/NEWS.md]
    regex: ['^Version:[[:space:]]*(.+)$', '^#[[:space:]]+pkg[[:space:]]+(.+)$']
    scheme: r
    consistency: identical
  pkg-no-news:
    files: [pkg2/DESCRIPTION, pkg2/NEWS.md]
    regex: ['^Version:[[:space:]]*(.+)$', '^#[[:space:]]+pkg2[[:space:]]+(.+)$']
    scheme: r
    consistency: identical
YAML

cat > pkg/DESCRIPTION <<'D'
Version: 1.0.0
D
cat > pkg/NEWS.md <<'N'
# pkg 1.0.0
N
cat > pkg2/DESCRIPTION <<'D'
Version: 1.0.0
D
# pkg2 deliberately has no NEWS.md.
git add -A && git commit -q -m base
R2_BASE="$(git rev-parse HEAD)"

sed -i.bak 's/Version: 1.0.0/Version: 1.1.0/' pkg/DESCRIPTION && rm pkg/DESCRIPTION.bak
sed -i.bak 's/Version: 1.0.0/Version: 1.1.0/' pkg2/DESCRIPTION && rm pkg2/DESCRIPTION.bak
git add -A && git commit -q -m "bump DESCRIPTION only, in both packages"
R2_HEAD="$(git rev-parse HEAD)"

_run "$REPO2" "$R2_BASE" "$R2_HEAD"
assert_eq "$(_status pkg-no-news)" "pass" \
  "repo2: package with no NEWS.md passes on DESCRIPTION alone (on-missing: skip default)"
assert_eq "$(_status pkg-with-news)" "fail" \
  "repo2: package whose NEWS.md exists but was left stale fails"
assert_contains "$(_msg pkg-with-news)" "disagree" \
  "repo2: mismatch is reported as files disagreeing, not as a plain 'not bumped'"

# ===================================================================
# Repo 3: downgrade detection, and an empty group (paths touched but
# the configured version file never existed at all).
# ===================================================================
REPO3="$WORK/repo3"
mkdir -p "$REPO3/.github" "$REPO3/pkg" "$REPO3/ghost"
cd "$REPO3"
git init -q .
git config user.email t@example.com
git config user.name t

cat > .github/please-bump.yaml <<'YAML'
version: 1
groups:
  pkg:
    files: [pkg/VERSION]
    parts:
      version: '^(.+)$'
    scheme: semver
  ghost:
    paths: ["ghost/"]
    files: [ghost/VERSION]
    parts:
      version: '^(.+)$'
    scheme: semver
YAML
echo "1.2.0" > pkg/VERSION
echo "unrelated" > ghost/README.md
git add -A && git commit -q -m base
R3_BASE="$(git rev-parse HEAD)"

echo "1.1.0" > pkg/VERSION
echo "more notes" >> ghost/README.md
git add -A && git commit -q -m "downgrade pkg; touch ghost dir (no version file exists there)"
R3_HEAD="$(git rev-parse HEAD)"

_run "$REPO3" "$R3_BASE" "$R3_HEAD"
assert_eq "$(_status pkg)" "fail" "repo3: downgraded version fails"
assert_eq "$(_bump pkg)" "downgrade" "repo3: downgrade is classified as 'downgrade'"
assert_eq "$(_status ghost)" "fail" "repo3: touched group with no version file fails (on-empty-group: error default)"
assert_contains "$(_msg ghost)" "no version file found" "repo3: empty-group message is explicit"

assert_summary
exit $?
