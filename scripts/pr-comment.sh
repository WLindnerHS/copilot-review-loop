#!/bin/bash
set -euo pipefail

# pr-comment.sh — post a summary comment to a PR
# Usage: echo "$BODY" | pr-comment.sh <pr_num>
# Runs from within a git repo (worktree) so gh auto-detects owner/repo.

pr_num="${1:-}"

if [ -z "$pr_num" ]; then
  echo "Usage: pr-comment.sh <pr_num>" >&2
  echo "  Body is read from stdin." >&2
  exit 1
fi

# Validate pr_num is strictly numeric
if ! [[ "$pr_num" =~ ^[0-9]+$ ]]; then
  echo "Error: pr_num must be a positive integer, got '$pr_num'" >&2
  exit 1
fi

# Read body from stdin into a temp file so we can check if it's empty
body_file="$(mktemp "${TMPDIR:-${TEMP:-/tmp}}/copilot-review-loop.XXXXXX")"
trap 'rm -f "$body_file"' EXIT
cat > "$body_file"

if [ ! -s "$body_file" ]; then
  echo "Error: empty body from stdin" >&2
  exit 1
fi

gh pr comment "$pr_num" --body-file "$body_file"
