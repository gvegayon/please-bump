#!/usr/bin/env bash
# please-bump orchestrator: resolves the config, walks every group, extracts
# and compares versions, and prints one JSON result document. Bash 3.2
# compatible. Meant to be run (not sourced) — `main` runs automatically when
# invoked as a script, and is skipped when sourced by the test suite.

set -uo pipefail

MAIN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$MAIN_SCRIPT_DIR/config.sh"
. "$MAIN_SCRIPT_DIR/paths.sh"
. "$MAIN_SCRIPT_DIR/extract.sh"
. "$MAIN_SCRIPT_DIR/schemes/semver.sh"
. "$MAIN_SCRIPT_DIR/schemes/numeric.sh"
. "$MAIN_SCRIPT_DIR/schemes/r.sh"
. "$MAIN_SCRIPT_DIR/schemes/pep440.sh"

# ---- inputs (env vars) ----
: "${PLEASE_BUMP_CONFIG:=.github/please-bump.yaml}"
: "${PLEASE_BUMP_PRESETS_DIR:=$MAIN_SCRIPT_DIR/../presets}"
: "${PLEASE_BUMP_HEAD_REF:=HEAD}"
: "${PLEASE_BUMP_WORKDIR:=.}"
: "${PLEASE_BUMP_JSON_OUT:=}"

# scheme_dispatch_compare <scheme> A B -> -1 | 0 | 1
scheme_dispatch_compare() {
  case "$1" in
    semver) semver_compare "$2" "$3" ;;
    pep440) pep440_compare "$2" "$3" ;;
    r) r_compare "$2" "$3" ;;
    numeric) numeric_compare "$2" "$3" ;;
    *) echo "0" ;;
  esac
}

# scheme_dispatch_classify <scheme> A B <comma-labels-or-empty> -> label
scheme_dispatch_classify() {
  local scheme="$1" a="$2" b="$3" labels="${4:-}"
  case "$scheme" in
    semver) semver_classify "$a" "$b" ;;
    pep440) pep440_classify "$a" "$b" ;;
    r) r_classify "$a" "$b" ;;
    numeric) numeric_classify "$a" "$b" "$labels" ;;
    *) echo "invalid-scheme" ;;
  esac
}

_extract_status_name() {
  case "$1" in
    0) echo "found" ;;
    "$EXTRACT_MISSING") echo "missing" ;;
    "$EXTRACT_NO_MATCH") echo "no_match" ;;
    "$EXTRACT_COMMAND_FAILED") echo "command_failed" ;;
    *) echo "error" ;;
  esac
}

main_check_base_ref() {
  if ! git rev-parse --verify -q "${PLEASE_BUMP_BASE_REF}^{commit}" >/dev/null 2>&1; then
    echo "please-bump: base ref '$PLEASE_BUMP_BASE_REF' is not reachable in this checkout." >&2
    echo "please-bump: fetch it first, e.g.:" >&2
    echo "please-bump:   git fetch --no-tags --depth=1 origin $PLEASE_BUMP_BASE_REF" >&2
    echo "please-bump: ...or check out with 'fetch-depth: 0'." >&2
    exit 1
  fi
}

# main_process_file <base_ref> <head_ref> <file> <parts_json> <assemble> <command> <on_missing> <on_no_match>
# Prints one JSON object describing this file's extraction outcome.
main_process_file() {
  local base_ref="$1" head_ref="$2" file="$3" parts_json="$4" assemble="$5" command="$6" on_missing="$7" on_no_match="$8"

  local base_version head_version base_code head_code base_status head_status
  base_version="$(extract_version "$base_ref" "$file" "$parts_json" "$assemble" "$command")"; base_code=$?
  head_version="$(extract_version "$head_ref" "$file" "$parts_json" "$assemble" "$command")"; head_code=$?
  base_status="$(_extract_status_name "$base_code")"
  head_status="$(_extract_status_name "$head_code")"

  local outcome="ok" error="" is_new="false"

  if [ "$base_status" = "missing" ] && [ "$head_status" = "missing" ]; then
    if [ "$on_missing" = "skip" ]; then
      outcome="skipped"
    else
      outcome="error"; error="not found at base or head"
    fi
  elif [ "$base_status" = "missing" ] && [ "$head_status" = "found" ]; then
    is_new="true"
  elif [ "$base_status" = "missing" ]; then
    outcome="error"; error="added, but did not match the configured pattern at head"
  elif [ "$head_status" = "missing" ]; then
    outcome="error"; error="existed at base but was removed"
  elif [ "$base_status" != "found" ] || [ "$head_status" != "found" ]; then
    if [ "$on_no_match" = "skip" ]; then
      outcome="skipped"
    else
      outcome="error"
      if [ "$base_status" != "found" ] && [ "$head_status" != "found" ]; then
        error="did not match the configured pattern at base or head"
      elif [ "$base_status" != "found" ]; then
        error="did not match the configured pattern at base"
      else
        error="did not match the configured pattern at head"
      fi
    fi
  fi

  jq -nc \
    --arg file "$file" \
    --arg outcome "$outcome" \
    --arg error "$error" \
    --argjson is_new "$is_new" \
    --arg base_status "$base_status" \
    --arg head_status "$head_status" \
    --arg base_version "$base_version" \
    --arg head_version "$head_version" \
    '{
      file: $file,
      outcome: $outcome,
      error: (($error | select(length > 0)) // null),
      is_new: $is_new,
      base_status: $base_status,
      head_status: $head_status,
      base_version: (if $base_status == "found" then $base_version else null end),
      head_version: (if $head_status == "found" then $head_version else null end)
    }'
}

_not_real_bump_labels='["unchanged","downgrade","build-only","invalid-base","invalid-head","invalid-scheme"]'

# main_process_group <name> <group_json> <changed_files_list> -> one JSON object
main_process_group() {
  local name="$1" group_json="$2" changed="$3"

  local when consistency on_empty_group includes excludes
  when="$(jq -r '.when' <<< "$group_json")"
  consistency="$(jq -r '.consistency' <<< "$group_json")"
  on_empty_group="$(jq -r '.on_empty_group' <<< "$group_json")"
  includes="$(jq -r '.paths_include[]' <<< "$group_json")"
  excludes="$(jq -r '.paths_exclude[]' <<< "$group_json")"

  local touched="true"
  if [ "$when" != "always" ]; then
    touched="$(paths_group_touched "$changed" "$includes" "$excludes")"
  fi

  if [ "$touched" != "true" ]; then
    # Nothing to compare, but the report still reads better showing the
    # version currently in place instead of a blank "--". Best-effort: pull
    # it from the first rule's first file at head; leave it out entirely
    # (rather than erroring) if that file is missing or doesn't match --
    # this is cosmetic, not a check.
    local skip_version=""
    local first_rule first_file
    first_rule="$(jq -c '.rules[0] // empty' <<< "$group_json")"
    if [ -n "$first_rule" ]; then
      first_file="$(jq -r '.files[0] // empty' <<< "$first_rule")"
      if [ -n "$first_file" ]; then
        local sparts sassemble scommand
        sparts="$(jq -c '.parts' <<< "$first_rule")"
        sassemble="$(jq -r '.assemble' <<< "$first_rule")"
        scommand="$(jq -r '.command' <<< "$first_rule")"
        skip_version="$(extract_version "$PLEASE_BUMP_HEAD_REF" "$first_file" "$sparts" "$sassemble" "$scommand" 2>/dev/null)" || skip_version=""
      fi
    fi
    jq -nc --arg name "$name" --arg v "$skip_version" \
      '{name: $name, status: "skipped", message: "no changes under this group'"'"'s paths", base_version: (($v | select(length > 0)) // null), head_version: (($v | select(length > 0)) // null), bump: null, files: []}'
    return
  fi

  local files_ndjson classified_ndjson
  files_ndjson="$(mktemp)"
  classified_ndjson="$(mktemp)"

  local nrules i
  nrules="$(jq -r '.rules | length' <<< "$group_json")"
  i=0
  while [ "$i" -lt "$nrules" ]; do
    local rule_json scheme part_labels parts assemble command on_missing on_no_match nfiles k f file_result
    rule_json="$(jq -c ".rules[$i]" <<< "$group_json")"
    scheme="$(jq -r '.scheme' <<< "$rule_json")"
    part_labels="$(jq -r '(.part_labels // []) | join(",")' <<< "$rule_json")"
    parts="$(jq -c '.parts' <<< "$rule_json")"
    assemble="$(jq -r '.assemble' <<< "$rule_json")"
    command="$(jq -r '.command' <<< "$rule_json")"
    on_missing="$(jq -r '.on_missing' <<< "$rule_json")"
    on_no_match="$(jq -r '.on_no_match' <<< "$rule_json")"

    nfiles="$(jq -r '.files | length' <<< "$rule_json")"
    k=0
    while [ "$k" -lt "$nfiles" ]; do
      f="$(jq -r ".files[$k]" <<< "$rule_json")"
      file_result="$(main_process_file "$PLEASE_BUMP_BASE_REF" "$PLEASE_BUMP_HEAD_REF" "$f" "$parts" "$assemble" "$command" "$on_missing" "$on_no_match")"
      file_result="$(jq -c --arg scheme "$scheme" --arg labels "$part_labels" '. + {scheme: $scheme, part_labels: $labels}' <<< "$file_result")"
      echo "$file_result" >> "$files_ndjson"
      k=$((k + 1))
    done
    i=$((i + 1))
  done

  local fr outcome scheme labels is_new bver hver label
  while IFS= read -r fr; do
    [ -z "$fr" ] && continue
    outcome="$(jq -r '.outcome' <<< "$fr")"
    if [ "$outcome" = "ok" ]; then
      scheme="$(jq -r '.scheme' <<< "$fr")"
      labels="$(jq -r '.part_labels' <<< "$fr")"
      is_new="$(jq -r '.is_new' <<< "$fr")"
      if [ "$is_new" = "true" ]; then
        label="new"
      else
        bver="$(jq -r '.base_version' <<< "$fr")"
        hver="$(jq -r '.head_version' <<< "$fr")"
        label="$(scheme_dispatch_classify "$scheme" "$bver" "$hver" "$labels")"
      fi
      fr="$(jq -c --arg label "$label" '. + {label: $label}' <<< "$fr")"
    fi
    echo "$fr" >> "$classified_ndjson"
  done < "$files_ndjson"

  local errors ok_count status="fail" bump="" base_version="" head_version="" message=""
  errors="$(jq -s '[.[] | select(.outcome == "error")]' "$classified_ndjson")"
  ok_count="$(jq -s '[.[] | select(.outcome == "ok")] | length' "$classified_ndjson")"

  if [ "$(jq 'length' <<< "$errors")" -gt 0 ]; then
    status="fail"
    message="$(jq -r '[.[] | "\(.file): \(.error)"] | join("; ")' <<< "$errors")"
  elif [ "$ok_count" -eq 0 ]; then
    case "$on_empty_group" in
      warn) status="warn"; message="no version file found" ;;
      skip) status="skipped"; message="no version file found" ;;
      *)    status="fail"; message="no version file found" ;;
    esac
  else
    local head_versions base_versions labels_list not_real_bump not_real_count head_uniform base_uniform label_uniform
    head_versions="$(jq -s '[.[] | select(.outcome == "ok") | .head_version]' "$classified_ndjson")"
    base_versions="$(jq -s '[.[] | select(.outcome == "ok" and (.is_new | not)) | .base_version]' "$classified_ndjson")"
    labels_list="$(jq -s '[.[] | select(.outcome == "ok") | .label]' "$classified_ndjson")"
    not_real_bump="$(jq -c --argjson bad "$_not_real_bump_labels" '[.[] | select(. as $l | $bad | index($l) != null)]' <<< "$labels_list")"
    not_real_count="$(jq 'length' <<< "$not_real_bump")"
    head_uniform="$(jq '(unique | length) <= 1' <<< "$head_versions")"
    base_uniform="$(jq '(unique | length) <= 1' <<< "$base_versions")"
    label_uniform="$(jq '(unique | length) <= 1' <<< "$labels_list")"

    if [ "$consistency" = "identical" ] && { [ "$head_uniform" != "true" ] || [ "$base_uniform" != "true" ]; }; then
      status="fail"
      message="files disagree: not all at the same version ($(jq -r 'join(", ")' <<< "$head_versions"))"
    elif [ "$consistency" = "same-bump" ] && [ "$label_uniform" != "true" ]; then
      status="fail"
      message="files disagree: not all bumped the same way ($(jq -r 'join(", ")' <<< "$labels_list"))"
    elif [ "$not_real_count" -gt 0 ]; then
      status="fail"
      message="not bumped"
    else
      status="pass"
    fi

    base_version="$(jq -r '.[0] // "—"' <<< "$base_versions")"
    head_version="$(jq -r '.[0] // "—"' <<< "$head_versions")"
    bump="$(jq -r '.[0] // "—"' <<< "$labels_list")"
  fi

  jq -nc \
    --arg name "$name" \
    --arg status "$status" \
    --arg message "$message" \
    --arg base_version "$base_version" \
    --arg head_version "$head_version" \
    --arg bump "$bump" \
    --slurpfile files "$classified_ndjson" \
    '{name: $name, status: $status, message: $message, base_version: $base_version, head_version: $head_version, bump: $bump, files: $files}'

  rm -f "$files_ndjson" "$classified_ndjson"
}

main() {
  : "${PLEASE_BUMP_BASE_REF:?PLEASE_BUMP_BASE_REF is required}"

  cd "$PLEASE_BUMP_WORKDIR" || { echo "please-bump: cannot cd to working-directory '$PLEASE_BUMP_WORKDIR'" >&2; exit 1; }

  main_check_base_ref

  local resolved
  resolved="$(config_resolve "$PLEASE_BUMP_CONFIG" "$PLEASE_BUMP_PRESETS_DIR")" || exit 1

  local changed
  changed="$(paths_changed_files "$PLEASE_BUMP_BASE_REF" "$PLEASE_BUMP_HEAD_REF")"

  local groups_ndjson names name gjson
  groups_ndjson="$(mktemp)"
  names="$(jq -r '.groups | keys[]' <<< "$resolved")"
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    gjson="$(jq -c --arg n "$name" '.groups[$n]' <<< "$resolved")"
    main_process_group "$name" "$gjson" "$changed" >> "$groups_ndjson"
  done <<< "$names"

  local overall_result="pass"
  if [ "$(jq -s '[.[] | select(.status == "fail")] | length' "$groups_ndjson")" -gt 0 ]; then
    overall_result="fail"
  fi

  local final_json
  final_json="$(jq -s \
    --arg base "$PLEASE_BUMP_BASE_REF" \
    --arg head "$PLEASE_BUMP_HEAD_REF" \
    --arg result "$overall_result" \
    '{base_ref: $base, head_ref: $head, result: $result, groups: .}' \
    "$groups_ndjson")"
  rm -f "$groups_ndjson"

  if [ -n "$PLEASE_BUMP_JSON_OUT" ]; then
    printf '%s\n' "$final_json" > "$PLEASE_BUMP_JSON_OUT"
  else
    printf '%s\n' "$final_json"
  fi

  [ "$overall_result" = "pass" ]
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main
fi
