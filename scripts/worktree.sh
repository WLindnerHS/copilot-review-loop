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

kill_worktree_processes() {
  local wt_path="$1"
  # Extract the directory name for fallback matching (e.g., "copilot-review-83")
  local wt_name
  wt_name="$(basename "$wt_path")"
  # Normalize path for matching (handle Windows path separators)
  local normalized_path
  normalized_path="$(cd "$wt_path" 2>/dev/null && pwd -W 2>/dev/null || echo "$wt_path")"

  if command -v powershell.exe > /dev/null 2>&1; then
    # Windows: use PowerShell to find and kill processes whose command line
    # references the worktree path (catches node/jest/npm workers)
    local escaped_path
    escaped_path="${normalized_path//\\/\\\\}"
    powershell.exe -Command "
      Get-CimInstance Win32_Process |
        Where-Object { \$_.CommandLine -like '*${escaped_path}*' -or \$_.CommandLine -like '*${wt_name}*' } |
        ForEach-Object {
          Write-Host \"Killing PID \$(\$_.ProcessId) (\$(\$_.Name))\"
          Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    " 2>/dev/null || true
  else
    # Unix: find processes with cwd or cmdline referencing the worktree
    local pids
    pids="$(lsof +D "$wt_path" 2>/dev/null | awk 'NR>1{print $2}' | sort -u || true)"
    if [ -z "$pids" ]; then
      # Fallback: grep for the path in /proc cmdlines
      pids="$(grep -rl "$wt_path" /proc/*/cmdline 2>/dev/null | grep -oP '/proc/\K[0-9]+' | sort -u || true)"
    fi
    if [ -n "$pids" ]; then
      echo "Killing processes in worktree: $pids"
      echo "$pids" | xargs kill -TERM 2>/dev/null || true
      sleep 1
      echo "$pids" | xargs kill -KILL 2>/dev/null || true
    fi
  fi
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

  # Verify branch exists (check local ref first, then remote)
  local resolved_branch="$branch"
  if ! git rev-parse --verify "$branch" > /dev/null 2>&1; then
    if git rev-parse --verify "origin/$branch" > /dev/null 2>&1; then
      resolved_branch="origin/$branch"
    else
      echo "Error: branch '$branch' does not exist locally or on origin" >&2
      exit 1
    fi
  fi

  local wt_path
  wt_path="$(get_worktree_path "$pr_num")"

  # Prune stale worktree registrations (directory gone but still tracked by git)
  git worktree prune 2>/dev/null || true

  # Clean up stale worktree if path exists (kill orphaned processes first)
  if [ -d "$wt_path" ]; then
    echo "Cleaning up stale worktree at $wt_path"
    kill_worktree_processes "$wt_path"
    git worktree remove --force "$wt_path" 2>/dev/null || true
    if [ -d "$wt_path" ]; then
      sleep 2
      rm -rf "$wt_path" 2>/dev/null || true
    fi
  fi

  # Use --detach to avoid "branch already checked out" errors when the user
  # is currently on the PR branch. The skill pushes via git push origin HEAD:<branch>.
  git worktree add --detach "$wt_path" "$resolved_branch"
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

  # Kill any processes still running inside the worktree (orphaned test runners, etc.)
  # This prevents locked files on Windows and zombie processes on all platforms.
  if [ -d "$wt_path" ]; then
    kill_worktree_processes "$wt_path"
  fi

  # Prune stale registrations first (directory gone but still tracked by git)
  git worktree prune 2>/dev/null || true

  if [ -d "$wt_path" ]; then
    git worktree remove --force "$wt_path" 2>/dev/null || true
    # On Windows, files may still be locked briefly after process kill; retry once
    if [ -d "$wt_path" ]; then
      sleep 2
      rm -rf "$wt_path" 2>/dev/null || true
    fi
    if [ -d "$wt_path" ]; then
      echo "Warning: could not fully remove $wt_path — some files may be locked" >&2
    else
      echo "Removed worktree at $wt_path"
    fi
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
