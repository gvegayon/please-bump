#!/usr/bin/env bash
# R package version scheme: dot- or dash-separated non-negative integers,
# e.g. "1.2.3" or "1.2-3" (R treats '-' and '.' as equivalent separators
# when comparing package versions — see R's `package_version`/`compareVersion`).
# Also covers the devel convention of a trailing ".9000"+ component
# (e.g. "1.2.3.9000"), which is reported as a "devel" bump rather than a
# fourth numbered component.

_R_SCHEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_R_SCHEME_DIR/numeric.sh"

_R_RE='^[0-9]+([.-][0-9]+)*$'

r_valid() {
  [[ "$1" =~ $_R_RE ]]
}

_r_normalize() {
  echo "$1" | tr '-' '.'
}

# r_compare A B -> -1 | 0 | 1
r_compare() {
  numeric_compare "$(_r_normalize "$1")" "$(_r_normalize "$2")"
}

# r_classify BASE HEAD -> major | minor | patch | devel
#                        | unchanged | downgrade | invalid-base | invalid-head
# Note: "-" and "." are equivalent separators in R, so "1.2-3" -> "1.2.3" is
# "unchanged", not a bump — there is no metadata-only concept in R versions.
r_classify() {
  local base="$1" head="$2" cmp
  if ! r_valid "$base"; then echo "invalid-base"; return; fi
  if ! r_valid "$head"; then echo "invalid-head"; return; fi

  cmp=$(r_compare "$head" "$base")
  if [ "$cmp" -lt 0 ]; then echo "downgrade"; return; fi
  if [ "$cmp" -eq 0 ]; then echo "unchanged"; return; fi

  local nbase nhead b_parts h_parts
  nbase="$(_r_normalize "$base")"
  nhead="$(_r_normalize "$head")"
  IFS='.' read -r -a b_parts <<< "$nbase"
  IFS='.' read -r -a h_parts <<< "$nhead"

  local n=${#b_parts[@]}
  [ "${#h_parts[@]}" -gt "$n" ] && n=${#h_parts[@]}

  local i=0 bx hx
  while [ "$i" -lt "$n" ]; do
    bx="${b_parts[$i]:-0}"
    hx="${h_parts[$i]:-0}"
    if [ "$bx" -ne "$hx" ]; then
      case "$i" in
        0) echo "major" ;;
        1) echo "minor" ;;
        2) echo "patch" ;;
        *) echo "devel" ;;
      esac
      return
    fi
    i=$((i + 1))
  done
  echo "version"
}

# r_is_dev V -> exit 0 if V follows R's devel convention: a fourth component
# of 9000 or more (e.g. "1.2.3.9000", "1.2-3.9001").
r_is_dev() {
  r_valid "$1" || return 1
  local parts
  IFS='.' read -r -a parts <<< "$(_r_normalize "$1")"
  [ "${#parts[@]}" -ge 4 ] && [ "${parts[3]}" -ge 9000 ]
}
