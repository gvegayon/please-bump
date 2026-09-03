#!/usr/bin/env bash
# Zero-dependency test harness. Runs every tests/unit/*.sh and
# tests/integration/*.sh as an independent bash process and aggregates
# pass/fail. Bash 3.2 compatible (macOS runner default).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
export PLEASE_BUMP_ROOT="$ROOT"

total_files=0
failed_files=0
failed_names=""

run_one() {
  f="$1"
  total_files=$((total_files + 1))
  name="$(basename "$f")"
  echo "== $name =="
  if bash "$f"; then
    :
  else
    failed_files=$((failed_files + 1))
    failed_names="$failed_names $name"
    echo "  ** $name FAILED **"
  fi
  echo ""
}

only="${1:-}"

for f in "$HERE"/unit/*.sh; do
  [ -e "$f" ] || continue
  case "$only" in
    unit|"") run_one "$f" ;;
  esac
done

for f in "$HERE"/integration/*.sh; do
  [ -e "$f" ] || continue
  case "$only" in
    integration|"") run_one "$f" ;;
  esac
done

echo "================================"
if [ "$failed_files" -gt 0 ]; then
  echo "$failed_files/$total_files test files FAILED:$failed_names"
  exit 1
fi
echo "$total_files test files passed"
