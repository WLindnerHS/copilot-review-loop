#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
  setup_git_repo
}

teardown() {
  teardown_git_repo
}

# --- create command ---

@test "create: creates worktree at expected path" {
  cd "$TEST_REPO_DIR"
  run "$SCRIPT_DIR/worktree.sh" create test-branch 42
  [ "$status" -eq 0 ]

  # Worktree should exist (check TEMP or /tmp)
  local expected_path="${TEMP:-/tmp}/copilot-review-42"
  [ -d "$expected_path" ]

  # Should appear in git worktree list
  git worktree list | grep -q "copilot-review-42"
}

@test "create: outputs the worktree path" {
  cd "$TEST_REPO_DIR"
  run "$SCRIPT_DIR/worktree.sh" create test-branch 42
  [ "$status" -eq 0 ]

  local expected_path="${TEMP:-/tmp}/copilot-review-42"
  [[ "$output" == *"$expected_path"* ]]
}

@test "create: fails if branch does not exist" {
  cd "$TEST_REPO_DIR"
  run "$SCRIPT_DIR/worktree.sh" create nonexistent-branch 42
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]] || [[ "$output" == *"not a valid"* ]] || [[ "$output" == *"invalid reference"* ]]
}

@test "create: fails if branch is already checked out" {
  cd "$TEST_REPO_DIR"
  git checkout test-branch
  run "$SCRIPT_DIR/worktree.sh" create test-branch 42
  [ "$status" -ne 0 ]
  [[ "$output" == *"already checked out"* ]]
}

@test "create: cleans up stale worktree if path already exists" {
  cd "$TEST_REPO_DIR"
  # Create first worktree
  "$SCRIPT_DIR/worktree.sh" create test-branch 42
  local wt_path="${TEMP:-/tmp}/copilot-review-42"

  # Simulate a stale worktree: remove git's tracking but leave the directory
  git worktree remove --force "$wt_path"
  mkdir -p "$wt_path"

  # Create again — should succeed by cleaning up stale directory
  run "$SCRIPT_DIR/worktree.sh" create test-branch 42
  [ "$status" -eq 0 ]
  [ -d "$wt_path" ]
}

@test "create: fails with no arguments" {
  cd "$TEST_REPO_DIR"
  run "$SCRIPT_DIR/worktree.sh" create
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "create: fails if not in a git repo" {
  cd "$(mktemp -d)"
  run "$SCRIPT_DIR/worktree.sh" create test-branch 42
  [ "$status" -ne 0 ]
}

@test "fails with no command" {
  run "$SCRIPT_DIR/worktree.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}
