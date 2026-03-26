#!/bin/bash
set -euo pipefail

# worktree.sh — manage git worktrees for copilot-review-loop
# Usage:
#   worktree.sh create <branch> <pr_num>
#   worktree.sh remove <pr_num>

get_worktree_path() {
  local pr_num="$1"
  local temp_dir="${TEMP:-/tmp}"
  echo "${temp_dir}/copilot-review-${pr_num}"
}

cmd_create() {
  local branch="${1:-}"
  local pr_num="${2:-}"

  if [ -z "$branch" ] || [ -z "$pr_num" ]; then
    echo "Usage: worktree.sh create <branch> <pr_num>" >&2
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

  # Verify branch is not already checked out
  if git worktree list | grep -q "\[$branch\]"; then
    echo "Error: branch '$branch' is already checked out" >&2
    exit 1
  fi

  local wt_path
  wt_path="$(get_worktree_path "$pr_num")"

  # Clean up stale worktree if path exists
  if [ -d "$wt_path" ]; then
    echo "Cleaning up stale worktree at $wt_path"
    git worktree remove --force "$wt_path" 2>/dev/null || true
    rm -rf "$wt_path" 2>/dev/null || true
  fi

  git worktree add "$wt_path" "$branch"
  echo "$wt_path"
}

cmd_remove() {
  local pr_num="${1:-}"

  if [ -z "$pr_num" ]; then
    echo "Usage: worktree.sh remove <pr_num>" >&2
    exit 1
  fi

  local wt_path
  wt_path="$(get_worktree_path "$pr_num")"

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
