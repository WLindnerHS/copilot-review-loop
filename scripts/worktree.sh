#!/bin/bash
set -euo pipefail

# worktree.sh — manage git worktrees for copilot-review-loop
# Usage:
#   worktree.sh create <branch> <pr_num>
#   worktree.sh remove <pr_num>

get_worktree_path() {
  local pr_num="$1"
  local temp_dir="${TMPDIR:-${TEMP:-/tmp}}"
  echo "${temp_dir}/copilot-review-${pr_num}"
}

cmd_create() {
  local branch="${1:-}"
  local pr_num="${2:-}"

  if [ -z "$branch" ] || [ -z "$pr_num" ]; then
    echo "Usage: worktree.sh create <branch> <pr_num>" >&2
    exit 1
  fi

  # Validate pr_num is strictly numeric to prevent path traversal
  if ! [[ "$pr_num" =~ ^[0-9]+$ ]]; then
    echo "Error: pr_num must be a positive integer, got '$pr_num'" >&2
    exit 1
  fi

  # Verify we're in a git repo
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: not in a git repository" >&2
    exit 1
  fi

  # Verify branch exists
  if ! git rev-parse --verify "$branch" > /dev/null 2>&1; then
    echo "Error: branch '$branch' does not exist" >&2
    exit 1
  fi

  local wt_path
  wt_path="$(get_worktree_path "$pr_num")"

  # Prune stale worktree registrations (directory gone but still tracked by git)
  git worktree prune 2>/dev/null || true

  # Clean up stale worktree if path exists
  if [ -d "$wt_path" ]; then
    echo "Cleaning up stale worktree at $wt_path"
    git worktree remove --force "$wt_path" 2>/dev/null || true
    rm -rf "$wt_path" 2>/dev/null || true
  fi

  # Use --detach to avoid "branch already checked out" errors when the user
  # is currently on the PR branch. The skill pushes via git push origin HEAD:<branch>.
  git worktree add --detach "$wt_path" "$branch"
  echo "$wt_path"
}

cmd_remove() {
  local pr_num="${1:-}"

  if [ -z "$pr_num" ]; then
    echo "Usage: worktree.sh remove <pr_num>" >&2
    exit 1
  fi

  # Validate pr_num is strictly numeric to prevent path traversal
  if ! [[ "$pr_num" =~ ^[0-9]+$ ]]; then
    echo "Error: pr_num must be a positive integer, got '$pr_num'" >&2
    exit 1
  fi

  local wt_path
  wt_path="$(get_worktree_path "$pr_num")"

  # Prune stale registrations first (directory gone but still tracked by git)
  git worktree prune 2>/dev/null || true

  if [ -d "$wt_path" ]; then
    git worktree remove --force "$wt_path" 2>/dev/null || true
    rm -rf "$wt_path" 2>/dev/null || true
    echo "Removed worktree at $wt_path"
  else
    echo "No worktree found at $wt_path"
  fi
}

# Main dispatch
command="${1:-}"
shift || true

case "$command" in
  create) cmd_create "$@" ;;
  remove) cmd_remove "$@" ;;
  *)
    echo "Usage: worktree.sh {create|remove} ..." >&2
    exit 1
    ;;
esac
