#!/usr/bin/env bash
# Changed-file detection and include/exclude path matching for the
# `when: changed` group gate. Bash 3.2 compatible.

# paths_changed_files <base-ref> <head-ref> -> one changed path per line.
# Uses the triple-dot form (diff against the merge-base of base and head) so
# unrelated commits that have since landed on the base branch don't show up
# as "changed" in the PR. <head-ref> may be the literal string "__worktree__"
# (matching extract.sh's $EXTRACT_WORKTREE) to diff against the current
# working tree, uncommitted changes included, instead of a committed ref.
paths_changed_files() {
  local base_ref="$1" head_ref="${2:-HEAD}"
  if [ "$head_ref" = "__worktree__" ]; then
    local merge_base
    merge_base="$(git merge-base "$base_ref" HEAD 2>/dev/null)" || merge_base="$base_ref"
    git diff --no-color --name-only "$merge_base"
    return
  fi
  git diff --no-color --name-only "${base_ref}...${head_ref}"
}

# _paths_entry_matches <file> <entry> -> exit 0 if it matches.
# An entry ending in "/" is a directory prefix. Anything else is matched as
# a shell glob against the exact file path (so a bare filename only matches
# that one path; use a trailing "/" for a directory, or "*" for a wildcard).
_paths_entry_matches() {
  local file="$1" entry="$2"
  case "$entry" in
    */)
      case "$file" in
        "$entry"*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *)
      case "$file" in
        $entry) return 0 ;;
        *) return 1 ;;
      esac
      ;;
  esac
}

# paths_file_included <file> <includes-newline-list> <excludes-newline-list>
# -> exit 0 if <file> is covered by includes and not excluded. An empty
# includes list matches nothing (callers should special-case "no includes at
# all" upstream — config.jq already guarantees every group gets a non-empty
# effective include list).
paths_file_included() {
  local file="$1" includes="$2" excludes="$3"
  local entry matched=1
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    if _paths_entry_matches "$file" "$entry"; then
      matched=0
      break
    fi
  done <<< "$includes"
  [ "$matched" -eq 0 ] || return 1

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    if _paths_entry_matches "$file" "$entry"; then
      return 1
    fi
  done <<< "$excludes"
  return 0
}

# paths_group_touched <changed-files-newline-list> <includes-newline-list> <excludes-newline-list>
# -> prints "true" or "false"
paths_group_touched() {
  local changed="$1" includes="$2" excludes="$3" f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if paths_file_included "$f" "$includes" "$excludes"; then
      echo "true"
      return
    fi
  done <<< "$changed"
  echo "false"
}
