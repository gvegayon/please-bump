#!/usr/bin/env bash
# Loads and resolves a please-bump config file into the normalized JSON
# manifest defined by config.jq. Can be sourced (defines config_resolve) or
# run directly: config.sh <config-file> [presets-dir]
set -uo pipefail

_CONFIG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# config_load_presets <dir> -> JSON object {name: preset-def, ...} on stdout
config_load_presets() {
  local dir="$1" acc="{}" f name j
  for f in "$dir"/*.yaml; do
    [ -e "$f" ] || continue
    name="$(basename "$f" .yaml)"
    j="$(yq -o=json eval '.' "$f")" || { echo "please-bump: failed to parse preset $f" >&2; return 1; }
    acc="$(jq -c --arg n "$name" --argjson v "$j" '. + {($n): $v}' <<<"$acc")"
  done
  echo "$acc"
}

# config_resolve <config-file> <presets-dir> -> resolved manifest JSON on stdout.
# Exits non-zero (after printing every error to stderr) if the config does not
# parse, or any group/rule could not be resolved.
config_resolve() {
  local config_file="$1" presets_dir="${2:-}"

  if [ ! -f "$config_file" ]; then
    echo "please-bump: config file not found: $config_file" >&2
    return 1
  fi

  local config_json
  config_json="$(yq -o=json eval '.' "$config_file" 2>&1)" || {
    echo "please-bump: failed to parse $config_file as YAML:" >&2
    echo "$config_json" >&2
    return 1
  }

  local builtin_types="{}"
  if [ -n "$presets_dir" ] && [ -d "$presets_dir" ]; then
    builtin_types="$(config_load_presets "$presets_dir")" || return 1
  fi

  local user_types
  user_types="$(jq -c '.types // {}' <<<"$config_json")"
  local merged_types
  merged_types="$(jq -nc --argjson b "$builtin_types" --argjson u "$user_types" '$b + $u')"

  local full_input
  full_input="$(jq -c --argjson types "$merged_types" '. + {types: $types}' <<<"$config_json")"

  local resolved
  resolved="$(jq -f "$_CONFIG_SCRIPT_DIR/config.jq" <<<"$full_input")" || {
    echo "please-bump: internal error resolving config (config.jq failed)" >&2
    return 1
  }

  local errors
  errors="$(jq -r '
    .release_source as $rs
    | ( if (["releases", "tags"] | index($rs)) == null
      then ["release-source: unknown value '\''\($rs)'\'' (expected releases or tags)"]
      else [] end )
    + [ .groups | to_entries[] | .key as $g
        | (.value | select(has("_error")) | "\($g): \(._error)"),
          (.value.rules[] | select(has("_error")) | "\($g): \(._error)") ]
    | .[]
  ' <<<"$resolved")"

  if [ -n "$errors" ]; then
    echo "please-bump: configuration errors:" >&2
    while IFS= read -r line; do
      echo "  - $line" >&2
    done <<< "$errors"
    return 1
  fi

  echo "$resolved"
}

# Allow running this file directly, e.g. for local debugging:
#   bash src/config.sh .github/please-bump.yaml presets
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  config_resolve "$@"
fi
