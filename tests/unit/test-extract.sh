#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/extract.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > DESCRIPTION <<'DESC'
Package: progA
Version: 1.2.3
Title: Test package
DESC

cat > version.h <<'HDR'
#define ENGINE_VERSION_MAJOR 1
#define ENGINE_VERSION_MINOR 4
#define ENGINE_VERSION_PATCH 0
HDR

# --- single-part extraction (worktree mode) ---
v="$(extract_version "$EXTRACT_WORKTREE" "DESCRIPTION" '{"version":"^Version:[[:space:]]*(.+)$"}' '{version}' '')"
assert_eq "$v" "1.2.3" "single-part extraction from DESCRIPTION"

# --- multi-part assemble (the C++ case) ---
parts='{"major":"ENGINE_VERSION_MAJOR[^0-9]*([0-9]+)","minor":"ENGINE_VERSION_MINOR[^0-9]*([0-9]+)","patch":"ENGINE_VERSION_PATCH[^0-9]*([0-9]+)"}'
v="$(extract_version "$EXTRACT_WORKTREE" "version.h" "$parts" '{major}.{minor}.{patch}' '')"
assert_eq "$v" "1.4.0" "three-part #define assembly (cpp-semantic shape)"

# --- missing file ---
extract_version "$EXTRACT_WORKTREE" "NOPE" '{"version":"^(.+)$"}' '{version}' ''
assert_eq "$?" "$EXTRACT_MISSING" "missing file returns EXTRACT_MISSING"

# --- file present, regex does not match ---
extract_version "$EXTRACT_WORKTREE" "DESCRIPTION" '{"version":"^NoSuchField:[[:space:]]*(.+)$"}' '{version}' ''
assert_eq "$?" "$EXTRACT_NO_MATCH" "non-matching regex returns EXTRACT_NO_MATCH"

# --- partial multi-part match (one part missing) ---
bad_parts='{"major":"ENGINE_VERSION_MAJOR[^0-9]*([0-9]+)","minor":"NO_SUCH_MINOR[^0-9]*([0-9]+)"}'
extract_version "$EXTRACT_WORKTREE" "version.h" "$bad_parts" '{major}.{minor}' ''
assert_eq "$?" "$EXTRACT_NO_MATCH" "one missing part out of several returns EXTRACT_NO_MATCH"

# --- command escape hatch ---
v="$(extract_version "$EXTRACT_WORKTREE" "DESCRIPTION" '{}' '' 'echo 9.9.9')"
assert_eq "$v" "9.9.9" "command rule uses command stdout as the version"

extract_version "$EXTRACT_WORKTREE" "DESCRIPTION" '{}' '' 'exit 1'
assert_eq "$?" "$EXTRACT_COMMAND_FAILED" "failing command returns EXTRACT_COMMAND_FAILED"

# --- git-ref mode ---
git init -q .
git config user.email test@example.com
git config user.name test
git add DESCRIPTION version.h
git commit -q -m base
base_sha="$(git rev-parse HEAD)"

sed -i.bak 's/Version: 1.2.3/Version: 1.3.0/' DESCRIPTION && rm -f DESCRIPTION.bak
git add DESCRIPTION
git commit -q -m bump

v="$(extract_version "$base_sha" "DESCRIPTION" '{"version":"^Version:[[:space:]]*(.+)$"}' '{version}' '')"
assert_eq "$v" "1.2.3" "extraction at a historical git ref reads that ref's content, not the worktree"
v="$(extract_version "HEAD" "DESCRIPTION" '{"version":"^Version:[[:space:]]*(.+)$"}' '{version}' '')"
assert_eq "$v" "1.3.0" "extraction at HEAD reads the current commit"

cat > NEWFILE <<'NF'
Version: 5.0.0
NF
git add NEWFILE
git commit -q -m "add newfile"
extract_version "$base_sha" "NEWFILE" '{"version":"^Version:[[:space:]]*(.+)$"}' '{version}' ''
assert_eq "$?" "$EXTRACT_MISSING" "file absent at base ref (added later) is EXTRACT_MISSING"
v="$(extract_version "HEAD" "NEWFILE" '{"version":"^Version:[[:space:]]*(.+)$"}' '{version}' '')"
assert_eq "$v" "5.0.0" "same new file is readable at HEAD"

assert_summary
exit $?
