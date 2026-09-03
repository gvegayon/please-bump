#!/usr/bin/env bash
# Reads a file at a given git ref (or the working tree) and pulls a version
# string out of it, either via named `parts` regexes assembled through a
# template, or via an escape-hatch `command`. Bash 3.2 compatible.

# Distinct exit codes so callers (main.sh) can tell "file absent" apart from
# "file present but nothing matched" apart from "command failed" — each gets
# a different on-missing/on-no-match policy.
EXTRACT_MISSING=3
EXTRACT_NO_MATCH=4
EXTRACT_COMMAND_FAILED=5

# The sentinel ref meaning "read the working tree" instead of a git ref.
EXTRACT_WORKTREE="__worktree__"

extract_file_exists_at() {
  local ref="$1" path="$2"
  if [ "$ref" = "$EXTRACT_WORKTREE" ]; then
    [ -f "$path" ]
  else
    git cat-file -e "${ref}:${path}" 2>/dev/null
  fi
}

extract_read_file_at() {
  local ref="$1" path="$2"
  if [ "$ref" = "$EXTRACT_WORKTREE" ]; then
    [ -f "$path" ] || return 1
    cat "$path"
  else
    git show "${ref}:${path}" 2>/dev/null
  fi
}

# extract_part <content> <ere-with-one-capture-group> -> prints the capture
# from the first matching line; returns 1 if no line matches. Matching is
# done with bash's own [[ =~ ]] engine, the same POSIX-ERE dialect as
# `sed -E`/`grep -E`, so there is no delimiter-escaping to worry about.
extract_part() {
  local content="$1" regex="$2" line
  while IFS= read -r line; do
    if [[ "$line" =~ $regex ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
  done <<< "$content"
  return 1
}

# extract_version <ref> <file> <parts-json-object> <assemble-template> <command-or-empty-or-null>
# Prints the assembled version string on stdout and returns 0 on success.
# Returns $EXTRACT_MISSING if the file does not exist at <ref>.
# Returns $EXTRACT_NO_MATCH if the file exists but not every named part
# matched (for a `command` rule, this is never returned — see COMMAND_FAILED).
# Returns $EXTRACT_COMMAND_FAILED if a `command` rule's command exited
# non-zero or printed nothing.
extract_version() {
  local ref="$1" file="$2" parts_json="$3" assemble="$4" command="$5"

  if [ -n "$command" ] && [ "$command" != "null" ]; then
    local out status
    out="$(PLEASE_BUMP_REF="$ref" PLEASE_BUMP_FILE="$file" bash -c "$command" 2>/dev/null)"
    status=$?
    if [ "$status" -ne 0 ] || [ -z "$out" ]; then
      return "$EXTRACT_COMMAND_FAILED"
    fi
    printf '%s\n' "$out" | head -n1
    return 0
  fi

  if ! extract_file_exists_at "$ref" "$file"; then
    return "$EXTRACT_MISSING"
  fi

  local content
  content="$(extract_read_file_at "$ref" "$file")"

  local result="$assemble" any_missing=0 name regex value
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    regex="$(jq -r --arg n "$name" '.[$n]' <<< "$parts_json")"
    if value="$(extract_part "$content" "$regex")"; then
      result="${result//"{$name}"/$value}"
    else
      any_missing=1
    fi
  done <<< "$(jq -r 'keys[]' <<< "$parts_json")"

  if [ "$any_missing" -eq 1 ]; then
    return "$EXTRACT_NO_MATCH"
  fi
  printf '%s' "$result"
  return 0
}
