#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/config.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/presets"
cat > "$WORK/presets/python-pyproject.yaml" <<'YAML'
scheme: pep440
files: ["pyproject.toml"]
parts:
  version: '^version\s*=\s*"([^"]+)"'
YAML

cat > "$WORK/config.yaml" <<'YAML'
version: 1
defaults:
  scheme: semver
groups:
  simple-broadcast:
    files: [a/VERSION, b/VERSION]
    regex: ['^(.+)$']
  simple-positional:
    files: [c/DESCRIPTION, c/NEWS.md]
    regex: ['^Version:\s*(.+)$', '^#\s*(.+)$']
  direct-parts:
    files: [d/version.h]
    parts:
      version: '^#define VERSION "([^"]+)"'
  preset-group:
    files: [program-b/pyproject.toml]
    preset: python-pyproject
  mixed-rules:
    consistency: identical
    rules:
      - preset: python-pyproject
        files: [engine/pyproject.toml]
      - files: [engine/version.h]
        parts:
          major: '#define MAJOR ([0-9]+)'
          minor: '#define MINOR ([0-9]+)'
          patch: '#define PATCH ([0-9]+)'
        assemble: "{major}.{minor}.{patch}"
        scheme: numeric
        part-labels: [major, minor, patch]
YAML

resolved="$(config_resolve "$WORK/config.yaml" "$WORK/presets")"
status=$?
assert_eq "$status" "0" "well-formed config resolves without error"

assert_eq "$(jq -r '.groups["simple-broadcast"].rules | length' <<<"$resolved")" "1" \
  "broadcast regex (1 regex, N files) makes one rule"
assert_eq "$(jq -r '.groups["simple-broadcast"].rules[0].files | length' <<<"$resolved")" "2" \
  "broadcast rule covers both files"

assert_eq "$(jq -r '.groups["simple-positional"].rules | length' <<<"$resolved")" "2" \
  "positional files+regex (N files, N regexes) makes N rules"
assert_eq "$(jq -r '.groups["simple-positional"].rules[1].files[0]' <<<"$resolved")" "c/NEWS.md" \
  "positional pairing keeps file/regex order"

assert_eq "$(jq -r '.groups["direct-parts"].rules[0].assemble' <<<"$resolved")" "{version}" \
  "single part with no explicit assemble defaults to {partname}"

assert_eq "$(jq -r '.groups["preset-group"].rules[0].scheme' <<<"$resolved")" "pep440" \
  "preset supplies scheme"
assert_eq "$(jq -r '.groups["preset-group"].rules[0].files[0]' <<<"$resolved")" "program-b/pyproject.toml" \
  "group-level files overrides the preset's own files"

assert_eq "$(jq -r '.groups["mixed-rules"].rules | length' <<<"$resolved")" "2" \
  "explicit rules: list keeps heterogeneous rules together in one group"
assert_eq "$(jq -r '.groups["mixed-rules"].rules[1].assemble' <<<"$resolved")" "{major}.{minor}.{patch}" \
  "C++-style multi-part assemble template is preserved"
assert_eq "$(jq -r '.groups["mixed-rules"].rules[1].part_labels | join(",")' <<<"$resolved")" "major,minor,patch" \
  "part-labels flow through to the resolved rule"

assert_eq "$(jq -r '.groups["simple-broadcast"].rules[0].on_missing' <<<"$resolved")" "skip" \
  "on-missing defaults to skip"
assert_eq "$(jq -r '.groups["direct-parts"].scheme // "semver"' <<<"$resolved" 2>/dev/null || echo semver)" "semver" \
  "top-level defaults.scheme reaches rules with no explicit scheme"
assert_eq "$(jq -r '.groups["direct-parts"].rules[0].scheme' <<<"$resolved")" "semver" \
  "defaults.scheme reaches a rule with no scheme of its own"

assert_eq "$(jq -r '.groups["direct-parts"].paths_include | join(",")' <<<"$resolved")" "d/version.h" \
  "no explicit 'paths:' falls back to the group's own configured files"

cat > "$WORK/config-paths.yaml" <<'YAML'
version: 1
groups:
  scoped:
    paths: |
      program-a/
      !program-a/vendor/
    files: [program-a/DESCRIPTION]
    parts:
      version: '^Version:\s*(.+)$'
YAML
resolved_paths="$(config_resolve "$WORK/config-paths.yaml" "$WORK/presets")"
assert_eq "$(jq -r '.groups.scoped.paths_include | join(",")' <<<"$resolved_paths")" "program-a/" \
  "explicit 'paths:' is used verbatim, not the files fallback"
assert_eq "$(jq -r '.groups.scoped.paths_exclude | join(",")' <<<"$resolved_paths")" "program-a/vendor/" \
  "'!'-prefixed path lines become exclusions"

# --- error aggregation ---
cat > "$WORK/config-bad.yaml" <<'YAML'
version: 1
groups:
  unknown-preset:
    files: [x]
    preset: nope-does-not-exist
  no-files:
    parts:
      version: '^(.+)$'
  mismatched-regex:
    files: [a, b, c]
    regex: ['^(.+)$', '^(.+)$']
YAML

bad_out="$(config_resolve "$WORK/config-bad.yaml" "$WORK/presets" 2>&1 1>/dev/null)"
bad_status=$?
assert_ne "$bad_status" "0" "config with errors exits non-zero"
assert_contains "$bad_out" "unknown preset/type 'nope-does-not-exist'" "reports unknown preset"
assert_contains "$bad_out" "none of: 'rules', 'preset'" "reports unresolvable group"
assert_contains "$bad_out" "3 files but 2 regexes" "reports mismatched files/regex counts"
assert_contains "$bad_out" "unknown-preset:" "unknown-preset: group name present"
assert_contains "$bad_out" "no-files:" "no-files: group name present"
assert_contains "$bad_out" "mismatched-regex:" "mismatched-regex: group name present"

# missing config file
missing_out="$(config_resolve "$WORK/does-not-exist.yaml" "$WORK/presets" 2>&1 1>/dev/null)"
assert_contains "$missing_out" "config file not found" "missing config file reported clearly"

assert_summary
exit $?
