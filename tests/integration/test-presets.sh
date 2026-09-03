#!/usr/bin/env bash
# Confirms every built-in preset (a) is valid YAML resolvable by config.sh,
# and (b) actually extracts the right version from a realistic fixture file.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/assert.sh"
. "$PLEASE_BUMP_ROOT/src/config.sh"
. "$PLEASE_BUMP_ROOT/src/extract.sh"

PRESETS_DIR="$PLEASE_BUMP_ROOT/presets"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# _check <preset> <fixture-path> <fixture-content> <expected-version>
_check() {
  local preset="$1" path="$2" content="$3" expected="$4"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"

  cat > cfg.yaml <<YAML
version: 1
groups:
  g:
    files: ["$path"]
    preset: $preset
YAML
  local resolved parts assemble got
  resolved="$(config_resolve cfg.yaml "$PRESETS_DIR")"
  parts="$(jq -c '.groups.g.rules[0].parts' <<< "$resolved")"
  assemble="$(jq -r '.groups.g.rules[0].assemble' <<< "$resolved")"
  got="$(extract_version "$EXTRACT_WORKTREE" "$path" "$parts" "$assemble" "")"
  assert_eq "$got" "$expected" "$preset: extracts '$expected' from its fixture"
}

_check r-package "DESCRIPTION" \
'Package: progA
Version: 1.2.3
Title: Test' \
"1.2.3"

_check r-news "NEWS.md" \
'# 1.2.3

* Initial release.' \
"1.2.3"

_check python-pyproject "pyproject.toml" \
'[project]
name = "mypkg"
version = "0.4.1"' \
"0.4.1"

_check python-setupcfg "setup.cfg" \
'[metadata]
name = mypkg
version = 0.4.1' \
"0.4.1"

_check cmake-project "CMakeLists.txt" \
'cmake_minimum_required(VERSION 3.20)
project(engine VERSION 2.1.0 LANGUAGES CXX)' \
"2.1.0"

_check node-package "package.json" \
'{
  "name": "mypkg",
  "version": "1.4.0",
  "license": "MIT"
}' \
"1.4.0"

_check cargo "Cargo.toml" \
'[package]
name = "mycrate"
version = "0.9.2"
edition = "2021"' \
"0.9.2"

# cpp-semantic and python-dunder need an explicit `files:` override on the
# preset itself (they have none/glob-shaped defaults), so exercise them via
# a `rules:` entry the same way the README documents, rather than _check's
# top-level `preset:` shortcut.
mkdir -p engine
cat > engine/version.h <<'H'
#define ENGINE_VERSION_MAJOR 2
#define ENGINE_VERSION_MINOR 1
#define ENGINE_VERSION_PATCH 0
H
cat > cfg-cpp.yaml <<'YAML'
version: 1
groups:
  g:
    rules:
      - preset: cpp-semantic
        files: [engine/version.h]
YAML
resolved="$(config_resolve cfg-cpp.yaml "$PRESETS_DIR")"
parts="$(jq -c '.groups.g.rules[0].parts' <<< "$resolved")"
assemble="$(jq -r '.groups.g.rules[0].assemble' <<< "$resolved")"
got="$(extract_version "$EXTRACT_WORKTREE" "engine/version.h" "$parts" "$assemble" "")"
assert_eq "$got" "2.1.0" "cpp-semantic: assembles MAJOR/MINOR/PATCH #defines into one version"

mkdir -p src/mypkg
cat > src/mypkg/__init__.py <<'PY'
"""mypkg."""
__version__ = "0.4.1"
PY
cat > cfg-dunder.yaml <<'YAML'
version: 1
groups:
  g:
    rules:
      - preset: python-dunder
        files: [src/mypkg/__init__.py]
YAML
resolved="$(config_resolve cfg-dunder.yaml "$PRESETS_DIR")"
parts="$(jq -c '.groups.g.rules[0].parts' <<< "$resolved")"
assemble="$(jq -r '.groups.g.rules[0].assemble' <<< "$resolved")"
got="$(extract_version "$EXTRACT_WORKTREE" "src/mypkg/__init__.py" "$parts" "$assemble" "")"
assert_eq "$got" "0.4.1" "python-dunder: extracts __version__"

assert_summary
exit $?
