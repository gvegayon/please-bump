#!/usr/bin/env bash
# Renders main.sh's JSON result into the GitHub-flavored Markdown used for
# both $GITHUB_STEP_SUMMARY and the sticky PR comment. Bash 3.2 compatible.

REPORT_MARKER='<!-- please-bump:comment -->'

# report_render <json> [title] -> markdown on stdout
report_render() {
  local json="$1" title="${2:-Version bump check}"
  local result base_ref icon
  result="$(jq -r '.result' <<< "$json")"
  base_ref="$(jq -r '.base_ref' <<< "$json")"
  icon="✅"
  [ "$result" = "fail" ] && icon="❌"

  echo "$REPORT_MARKER"
  echo "### $title $icon"
  echo ""
  echo "| group | base | head | bump |"
  echo "|---|---|---|---|"

  local ngroups i
  ngroups="$(jq '.groups | length' <<< "$json")"
  i=0
  while [ "$i" -lt "$ngroups" ]; do
    local g name status base_v head_v bump gicon label
    g="$(jq -c ".groups[$i]" <<< "$json")"
    name="$(jq -r '.name' <<< "$g")"
    status="$(jq -r '.status' <<< "$g")"
    base_v="$(jq -r '.base_version // ""' <<< "$g")"
    head_v="$(jq -r '.head_version // ""' <<< "$g")"
    bump="$(jq -r '.bump // ""' <<< "$g")"
    [ -z "$base_v" ] && base_v="—"
    [ -z "$head_v" ] && head_v="—"

    case "$status" in
      pass) gicon="✅"; label="**${bump}** update" ;;
      fail)
        gicon="❌"
        if [ "$bump" = "downgrade" ]; then
          label="**downgrade**"
        elif [ "$base_v" = "—" ] && [ "$head_v" = "—" ]; then
          label="no version file found"
        else
          label="not bumped"
        fi
        ;;
      skipped) gicon="⏭️"; label="skipped" ;;
      warn) gicon="⚠️"; label="no version file found" ;;
      *) gicon="❓"; label="$status" ;;
    esac

    echo "| $name | $base_v | $head_v | $gicon $label |"
    i=$((i + 1))
  done
  echo ""

  i=0
  while [ "$i" -lt "$ngroups" ]; do
    local g name status message skipped_files
    g="$(jq -c ".groups[$i]" <<< "$json")"
    name="$(jq -r '.name' <<< "$g")"
    status="$(jq -r '.status' <<< "$g")"
    message="$(jq -r '.message // ""' <<< "$g")"
    skipped_files="$(jq -r '[.files[]? | select(.outcome == "skipped") | .file] | join(", ")' <<< "$g")"

    if { [ "$status" = "fail" ] || [ "$status" = "warn" ]; } && [ -n "$message" ]; then
      echo "**$name** — $message."
      echo ""
    fi
    if [ -n "$skipped_files" ]; then
      echo "**$name** — not found, skipped: $skipped_files."
      echo ""
    fi
    i=$((i + 1))
  done

  echo "<sub>Checked $ngroups group(s) against \`$base_ref\` · [please-bump](https://github.com/gvegayon/please-bump)</sub>"
}

# report_write_summary <json> [title] -> appends to $GITHUB_STEP_SUMMARY (no-op if unset)
report_write_summary() {
  local json="$1" title="${2:-Version bump check}"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    report_render "$json" "$title" >> "$GITHUB_STEP_SUMMARY"
  fi
}
