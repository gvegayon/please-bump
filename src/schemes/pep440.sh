#!/usr/bin/env bash
# PEP 440 version comparison and classification — documented subset:
# epoch, release segments, canonical pre-release spellings (aN / bN / rcN
# only — not the "alpha"/"beta"/"c"/"preview" aliases PEP 440 also permits),
# .postN, and .devN. A local version segment (+something, like semver build
# metadata) is ignored for ordering; a version differing only in the local
# segment is reported as "build-only" rather than a real bump.
# https://peps.python.org/pep-0440/#version-scheme

_PEP440_SCHEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_PEP440_SCHEME_DIR/numeric.sh"

_PEP440_CORE_RE='^(([0-9]+)!)?([0-9]+(\.[0-9]+)*)(a[0-9]+|b[0-9]+|rc[0-9]+)?(\.post[0-9]+)?(\.dev[0-9]+)?$'

pep440_valid() {
  local v="${1%%+*}"
  [[ "$v" =~ $_PEP440_CORE_RE ]]
}

# Parses "$1" (local/+segment stripped) and sets globals:
#   _PV_EPOCH _PV_RELEASE _PV_PRE_TYPE _PV_PRE_NUM _PV_POST_NUM _PV_DEV_NUM
# _PV_PRE_TYPE is "" | "a" | "b" | "rc"; the *_NUM fields are "" when absent.
_pep440_parse() {
  local v="${1%%+*}" pre post dev
  if [[ ! "$v" =~ $_PEP440_CORE_RE ]]; then
    _PV_EPOCH=0; _PV_RELEASE=""; _PV_PRE_TYPE=""; _PV_PRE_NUM=""; _PV_POST_NUM=""; _PV_DEV_NUM=""
    return 1
  fi
  _PV_EPOCH="${BASH_REMATCH[2]:-0}"
  _PV_RELEASE="${BASH_REMATCH[3]}"
  pre="${BASH_REMATCH[5]}"
  post="${BASH_REMATCH[6]}"
  dev="${BASH_REMATCH[7]}"

  case "$pre" in
    a*) _PV_PRE_TYPE="a"; _PV_PRE_NUM="${pre#a}" ;;
    b*) _PV_PRE_TYPE="b"; _PV_PRE_NUM="${pre#b}" ;;
    rc*) _PV_PRE_TYPE="rc"; _PV_PRE_NUM="${pre#rc}" ;;
    *) _PV_PRE_TYPE=""; _PV_PRE_NUM="" ;;
  esac

  if [ -n "$post" ]; then _PV_POST_NUM="${post#.post}"; else _PV_POST_NUM=""; fi
  if [ -n "$dev" ]; then _PV_DEV_NUM="${dev#.dev}"; else _PV_DEV_NUM=""; fi
  return 0
}

# Phase rank among versions that share epoch + release segment, ignoring
# dev status: pre-releases order a < b < rc < final < post.
_pep440_phase_rank() {
  case "$1" in
    a) echo 1 ;;
    b) echo 2 ;;
    rc) echo 3 ;;
    *) echo 4 ;;  # final (rank 4 unless a post is set — caller handles that)
  esac
}

# pep440_compare A B -> -1 | 0 | 1
pep440_compare() {
  local a_epoch a_rel a_pt a_pn a_post a_dev
  local b_epoch b_rel b_pt b_pn b_post b_dev
  _pep440_parse "$1"; a_epoch=$_PV_EPOCH; a_rel=$_PV_RELEASE; a_pt=$_PV_PRE_TYPE; a_pn=$_PV_PRE_NUM; a_post=$_PV_POST_NUM; a_dev=$_PV_DEV_NUM
  _pep440_parse "$2"; b_epoch=$_PV_EPOCH; b_rel=$_PV_RELEASE; b_pt=$_PV_PRE_TYPE; b_pn=$_PV_PRE_NUM; b_post=$_PV_POST_NUM; b_dev=$_PV_DEV_NUM

  if [ "$a_epoch" -ne "$b_epoch" ]; then
    if [ "$a_epoch" -lt "$b_epoch" ]; then echo -1; else echo 1; fi
    return
  fi

  local rel_cmp
  rel_cmp=$(numeric_compare "$a_rel" "$b_rel")
  if [ "$rel_cmp" -ne 0 ]; then echo "$rel_cmp"; return; fi

  # Same release segment. A "dev-only" version (dev set, no pre, no post)
  # sits before the pre-release ladder; a post sits after final.
  local a_dev_only=0 b_dev_only=0
  [ -n "$a_dev" ] && [ -z "$a_pt" ] && [ -z "$a_post" ] && a_dev_only=1
  [ -n "$b_dev" ] && [ -z "$b_pt" ] && [ -z "$b_post" ] && b_dev_only=1

  local a_rank b_rank
  if [ "$a_dev_only" -eq 1 ]; then a_rank=0
  elif [ -n "$a_post" ]; then a_rank=5
  else a_rank=$(_pep440_phase_rank "$a_pt"); fi

  if [ "$b_dev_only" -eq 1 ]; then b_rank=0
  elif [ -n "$b_post" ]; then b_rank=5
  else b_rank=$(_pep440_phase_rank "$b_pt"); fi

  if [ "$a_rank" -ne "$b_rank" ]; then
    if [ "$a_rank" -lt "$b_rank" ]; then echo -1; else echo 1; fi
    return
  fi

  # Same rank: compare the sub-key relevant to that rank.
  if [ "$a_rank" -ge 1 ] && [ "$a_rank" -le 3 ]; then
    if [ "${a_pn:-0}" -ne "${b_pn:-0}" ]; then
      if [ "${a_pn:-0}" -lt "${b_pn:-0}" ]; then echo -1; else echo 1; fi
      return
    fi
  elif [ "$a_rank" -eq 5 ]; then
    if [ "${a_post:-0}" -ne "${b_post:-0}" ]; then
      if [ "${a_post:-0}" -lt "${b_post:-0}" ]; then echo -1; else echo 1; fi
      return
    fi
  fi

  # Final tie-break: within the same phase, a dev release sorts before the
  # non-dev release of that phase; if both are dev, compare dev numbers.
  if [ -n "$a_dev" ] && [ -z "$b_dev" ]; then echo -1; return; fi
  if [ -z "$a_dev" ] && [ -n "$b_dev" ]; then echo 1; return; fi
  if [ -n "$a_dev" ] && [ -n "$b_dev" ] && [ "$a_dev" -ne "$b_dev" ]; then
    if [ "$a_dev" -lt "$b_dev" ]; then echo -1; else echo 1; fi
    return
  fi
  echo 0
}

# pep440_classify BASE HEAD -> epoch | dev | prerelease | post | release
#                             | major | minor | patch | component-N
#                             | build-only | unchanged | downgrade
#                             | invalid-base | invalid-head
pep440_classify() {
  local base="$1" head="$2" cmp
  if ! pep440_valid "$base"; then echo "invalid-base"; return; fi
  if ! pep440_valid "$head"; then echo "invalid-head"; return; fi

  cmp=$(pep440_compare "$head" "$base")
  if [ "$cmp" -lt 0 ]; then echo "downgrade"; return; fi
  if [ "$cmp" -eq 0 ]; then
    if [ "$base" = "$head" ]; then echo "unchanged"; else echo "build-only"; fi
    return
  fi

  local b_epoch b_rel h_epoch h_rel h_pt h_post h_dev
  _pep440_parse "$base"; b_epoch=$_PV_EPOCH; b_rel=$_PV_RELEASE
  _pep440_parse "$head"; h_epoch=$_PV_EPOCH; h_rel=$_PV_RELEASE; h_pt=$_PV_PRE_TYPE; h_post=$_PV_POST_NUM; h_dev=$_PV_DEV_NUM

  if [ "$h_epoch" -ne "$b_epoch" ]; then echo "epoch"; return; fi

  # The head's own phase dominates the label — a jump to "1.3.0rc1" is
  # reported as a prerelease bump even though the release segment also
  # moved, because the head is not yet a stable release.
  if [ -n "$h_dev" ] && [ -z "$h_pt" ] && [ -z "$h_post" ]; then echo "dev"; return; fi
  if [ -n "$h_pt" ]; then echo "prerelease"; return; fi
  if [ -n "$h_post" ]; then echo "post"; return; fi

  local rel_cmp
  rel_cmp=$(numeric_compare "$b_rel" "$h_rel")
  if [ "$rel_cmp" -eq 0 ]; then echo "release"; return; fi
  numeric_classify "$b_rel" "$h_rel" "major,minor,patch"
}
