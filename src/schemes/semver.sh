#!/usr/bin/env bash
# SemVer 2.0.0 comparison and classification. https://semver.org/
# Bash 3.2 compatible (no associative arrays, uses [[ =~ ]] which 3.2 supports).

_SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

semver_valid() {
  [[ "$1" =~ $_SEMVER_RE ]]
}

# Parses "$1" and sets globals _SV_MAJOR _SV_MINOR _SV_PATCH _SV_PRE _SV_BUILD.
# This "sets globals" pattern (instead of a return value) is used deliberately
# throughout src/schemes/*.sh so callers can cheaply pull multiple fields out
# of one parse without needing bash 4 associative arrays or nameref support.
_semver_parse() {
  local v core
  v="$1"
  case "$v" in
    *+*) _SV_BUILD="${v#*+}"; core="${v%%+*}" ;;
    *) _SV_BUILD=""; core="$v" ;;
  esac
  case "$core" in
    *-*) _SV_PRE="${core#*-}"; core="${core%%-*}" ;;
    *) _SV_PRE="" ;;
  esac
  _SV_MAJOR="${core%%.*}"
  local rest="${core#*.}"
  _SV_MINOR="${rest%%.*}"
  _SV_PATCH="${rest#*.}"
}

_semver_id_is_numeric() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Compares two dot-separated prerelease identifier lists per semver.org #11.
# Prints -1 | 0 | 1. Empty string means "no prerelease" (higher precedence).
_semver_compare_pre() {
  local a="$1" b="$2"
  if [ -z "$a" ] && [ -z "$b" ]; then echo 0; return; fi
  if [ -z "$a" ]; then echo 1; return; fi
  if [ -z "$b" ]; then echo -1; return; fi

  local a_parts b_parts
  IFS='.' read -r -a a_parts <<< "$a"
  IFS='.' read -r -a b_parts <<< "$b"

  local na=${#a_parts[@]} nb=${#b_parts[@]}
  local n=$na
  [ "$nb" -lt "$n" ] && n=$nb

  local i=0 x y
  while [ "$i" -lt "$n" ]; do
    x="${a_parts[$i]}"
    y="${b_parts[$i]}"
    if _semver_id_is_numeric "$x" && _semver_id_is_numeric "$y"; then
      if [ "$x" -lt "$y" ]; then echo -1; return; fi
      if [ "$x" -gt "$y" ]; then echo 1; return; fi
    elif _semver_id_is_numeric "$x"; then
      echo -1; return
    elif _semver_id_is_numeric "$y"; then
      echo 1; return
    else
      if [[ "$x" < "$y" ]]; then echo -1; return; fi
      if [[ "$x" > "$y" ]]; then echo 1; return; fi
    fi
    i=$((i + 1))
  done
  if [ "$na" -lt "$nb" ]; then echo -1; return; fi
  if [ "$na" -gt "$nb" ]; then echo 1; return; fi
  echo 0
}

# semver_compare A B -> -1 | 0 | 1 (build metadata ignored, per spec #10)
semver_compare() {
  local a_major a_minor a_patch a_pre b_major b_minor b_patch b_pre
  _semver_parse "$1"; a_major=$_SV_MAJOR; a_minor=$_SV_MINOR; a_patch=$_SV_PATCH; a_pre=$_SV_PRE
  _semver_parse "$2"; b_major=$_SV_MAJOR; b_minor=$_SV_MINOR; b_patch=$_SV_PATCH; b_pre=$_SV_PRE

  if [ "$a_major" -ne "$b_major" ]; then
    if [ "$a_major" -lt "$b_major" ]; then echo -1; else echo 1; fi
    return
  fi
  if [ "$a_minor" -ne "$b_minor" ]; then
    if [ "$a_minor" -lt "$b_minor" ]; then echo -1; else echo 1; fi
    return
  fi
  if [ "$a_patch" -ne "$b_patch" ]; then
    if [ "$a_patch" -lt "$b_patch" ]; then echo -1; else echo 1; fi
    return
  fi
  _semver_compare_pre "$a_pre" "$b_pre"
}

# semver_classify BASE HEAD -> major | minor | patch | prerelease | release
#                             | build-only | unchanged | downgrade
#                             | invalid-base | invalid-head
semver_classify() {
  local base="$1" head="$2" cmp
  if ! semver_valid "$base"; then echo "invalid-base"; return; fi
  if ! semver_valid "$head"; then echo "invalid-head"; return; fi

  cmp=$(semver_compare "$head" "$base")
  if [ "$cmp" -lt 0 ]; then echo "downgrade"; return; fi
  if [ "$cmp" -eq 0 ]; then
    if [ "$base" = "$head" ]; then echo "unchanged"; else echo "build-only"; fi
    return
  fi

  local b_major b_minor b_patch b_pre h_major h_minor h_patch h_pre
  _semver_parse "$base"; b_major=$_SV_MAJOR; b_minor=$_SV_MINOR; b_patch=$_SV_PATCH; b_pre=$_SV_PRE
  _semver_parse "$head"; h_major=$_SV_MAJOR; h_minor=$_SV_MINOR; h_patch=$_SV_PATCH; h_pre=$_SV_PRE

  if [ "$h_major" -ne "$b_major" ]; then echo "major"; return; fi
  if [ "$h_minor" -ne "$b_minor" ]; then echo "minor"; return; fi
  if [ "$h_patch" -ne "$b_patch" ]; then echo "patch"; return; fi
  # Same core: cmp>0 with equal core is only reachable when base had a
  # prerelease (a release, or a "higher" prerelease, beats it).
  if [ -z "$h_pre" ]; then echo "release"; return; fi
  echo "prerelease"
}

# semver_is_dev V -> exit 0 if V carries a prerelease part ("1.3.0-dev.1",
# "1.3.0-rc.1"), i.e. is not a final release.
semver_is_dev() {
  semver_valid "$1" || return 1
  _semver_parse "$1"
  [ -n "$_SV_PRE" ]
}
