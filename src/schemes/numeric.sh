#!/usr/bin/env bash
# Generic component-wise numeric version scheme: N(.N)*. Used directly for
# CalVer-style versions, and as the release-segment comparator that r.sh and
# pep440.sh build on. Missing trailing components compare as 0 (so "1.2" and
# "1.2.0" are equal), matching how CalVer/R/PEP440 all treat short forms.

_NUMERIC_RE='^[0-9]+(\.[0-9]+)*$'

numeric_valid() {
  [[ "$1" =~ $_NUMERIC_RE ]]
}

# numeric_compare A B -> -1 | 0 | 1
numeric_compare() {
  local a="$1" b="$2"
  local a_parts b_parts
  IFS='.' read -r -a a_parts <<< "$a"
  IFS='.' read -r -a b_parts <<< "$b"

  local na=${#a_parts[@]} nb=${#b_parts[@]}
  local n=$na
  [ "$nb" -gt "$n" ] && n=$nb

  local i=0 x y
  while [ "$i" -lt "$n" ]; do
    x="${a_parts[$i]:-0}"
    y="${b_parts[$i]:-0}"
    if [ "$x" -lt "$y" ]; then echo -1; return; fi
    if [ "$x" -gt "$y" ]; then echo 1; return; fi
    i=$((i + 1))
  done
  echo 0
}

# numeric_classify BASE HEAD [comma-separated-labels] -> <label> | unchanged
#                                                        | downgrade
#                                                        | invalid-base | invalid-head
# `labels` names each dot position (e.g. "year,month,micro"); positions past
# the end of `labels` are reported as "component-N" (1-indexed).
numeric_classify() {
  local base="$1" head="$2" labels="${3:-}" cmp
  if ! numeric_valid "$base"; then echo "invalid-base"; return; fi
  if ! numeric_valid "$head"; then echo "invalid-head"; return; fi

  cmp=$(numeric_compare "$head" "$base")
  if [ "$cmp" -lt 0 ]; then echo "downgrade"; return; fi
  if [ "$cmp" -eq 0 ]; then echo "unchanged"; return; fi

  local b_parts h_parts label_parts
  IFS='.' read -r -a b_parts <<< "$base"
  IFS='.' read -r -a h_parts <<< "$head"
  IFS=',' read -r -a label_parts <<< "$labels"

  local n=${#b_parts[@]}
  [ "${#h_parts[@]}" -gt "$n" ] && n=${#h_parts[@]}

  local i=0 bx hx
  while [ "$i" -lt "$n" ]; do
    bx="${b_parts[$i]:-0}"
    hx="${h_parts[$i]:-0}"
    if [ "$bx" -ne "$hx" ]; then
      if [ -n "${label_parts[$i]:-}" ]; then
        echo "${label_parts[$i]}"
      else
        echo "component-$((i + 1))"
      fi
      return
    fi
    i=$((i + 1))
  done
  echo "version"
}

# numeric_is_dev V -> always false: a bare N(.N)* has no development marker.
numeric_is_dev() {
  return 1
}
