#!/usr/bin/env bash
# Creates or updates the sticky please-bump PR comment via `gh api`, keyed by
# the $REPORT_MARKER at the top of the rendered report so a PR accumulates
# exactly one such comment across pushes. Requires GH_TOKEN in the
# environment (gh reads it automatically) and `gh` on PATH.

_COMMENT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_COMMENT_SCRIPT_DIR/report.sh"

# comment_find_existing <repo> <pr-number> -> existing comment id, or empty
comment_find_existing() {
  local repo="$1" pr="$2"
  gh api "repos/$repo/issues/$pr/comments" --paginate 2>/dev/null \
    | jq -r --arg marker "$REPORT_MARKER" \
        '.[] | select(.body != null and (.body | startswith($marker))) | .id' \
    | head -n1
}

# comment_post <repo> <pr-number> <body-file>
# Creates a new comment, or PATCHes the existing sticky one if found.
# Returns gh's exit code so callers can degrade gracefully (e.g. on a
# read-only fork-PR token) instead of failing the whole job over it.
comment_post() {
  local repo="$1" pr="$2" body_file="$3" existing
  existing="$(comment_find_existing "$repo" "$pr")"
  if [ -n "$existing" ]; then
    gh api --method PATCH "repos/$repo/issues/comments/$existing" -F body=@"$body_file" > /dev/null
  else
    gh api --method POST "repos/$repo/issues/$pr/comments" -F body=@"$body_file" > /dev/null
  fi
}

# Allow running this file directly:
#   PLEASE_BUMP_JSON=result.json PLEASE_BUMP_REPOSITORY=owner/repo \
#     PLEASE_BUMP_PR_NUMBER=123 GH_TOKEN=... bash src/comment.sh [title]
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -uo pipefail
  : "${PLEASE_BUMP_JSON:?PLEASE_BUMP_JSON (path to the main.sh JSON output) is required}"
  : "${PLEASE_BUMP_REPOSITORY:?PLEASE_BUMP_REPOSITORY (owner/repo) is required}"
  : "${PLEASE_BUMP_PR_NUMBER:?PLEASE_BUMP_PR_NUMBER is required}"

  json="$(cat "$PLEASE_BUMP_JSON")"
  body_file="$(mktemp)"
  report_render "$json" "${1:-Version bump check}" > "$body_file"

  if comment_post "$PLEASE_BUMP_REPOSITORY" "$PLEASE_BUMP_PR_NUMBER" "$body_file"; then
    echo "please-bump: posted/updated the PR comment."
  else
    echo "please-bump: warning: could not post the PR comment (often a read-only token on a fork PR)." >&2
    echo "please-bump: the pass/fail result above is unaffected." >&2
  fi
  rm -f "$body_file"
fi
