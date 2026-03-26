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

  local expected_path="${TMPDIR:-${TEMP:-/tmp}}/copilot-review-42"
  [ -d "$expected_path" ]

  git worktree list | grep -q "copilot-review-42"
}

@test "create: outputs the worktree path" {
  cd "$TEST_REPO_DIR"
  run "$SCRIPT_DIR/worktree.sh" create test-branch 42
  [ "$status" -eq 0 ]

  local expected_path="${TMPDIR:-${TEMP:-/tmp}}/copilot-review-42"
  [[ "$output" == *"$expected_path"* ]]
}

@test "create: fails if branch does not exist" {
  cd "$TEST_REPO_DIR"
  run "$SCRIPT_DIR/worktree.sh" create nonexistent-branch 42
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]] || [[ "$output" == *"not a valid"* ]] || [[ "$output" == *"invalid reference"* ]]
}

@test "create: works when branch is already checked out (detached HEAD)" {
  cd "$TEST_REPO_DIR"
  git checkout test-branch
  run "$SCRIPT_DIR/worktree.sh" create test-branch 42
  [ "$status" -eq 0 ]

  local expected_path="${TMPDIR:-${TEMP:-/tmp}}/copilot-review-42"
  [ -d "$expected_path" ]
}

@test "create: cleans up stale worktree if path already exists" {
  cd "$TEST_REPO_DIR"
  "$SCRIPT_DIR/worktree.sh" create test-branch 42
  local wt_path="${TMPDIR:-${TEMP:-/tmp}}/copilot-review-42"

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

@test "create: fails with non-numeric pr_num" {
  cd "$TEST_REPO_DIR"
  run "$SCRIPT_DIR/worktree.sh" create test-branch "../escape"
  [ "$status" -ne 0 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "fails with no command" {
  run "$SCRIPT_DIR/worktree.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

# --- remove command ---

@test "remove: removes an existing worktree" {
  cd "$TEST_REPO_DIR"
  "$SCRIPT_DIR/worktree.sh" create test-branch 42
  local wt_path="${TMPDIR:-${TEMP:-/tmp}}/copilot-review-42"
  [ -d "$wt_path" ]

  run "$SCRIPT_DIR/worktree.sh" remove 42
  [ "$status" -eq 0 ]
  [ ! -d "$wt_path" ]
  ! git worktree list | grep -q "copilot-review-42"
}

@test "remove: succeeds even if worktree doesn't exist" {
  cd "$TEST_REPO_DIR"
  run "$SCRIPT_DIR/worktree.sh" remove 999
  [ "$status" -eq 0 ]
  [[ "$output" == *"No worktree found"* ]]
}

@test "remove: fails with no arguments" {
  cd "$TEST_REPO_DIR"
  run "$SCRIPT_DIR/worktree.sh" remove
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "remove: fails with non-numeric pr_num" {
  cd "$TEST_REPO_DIR"
  run "$SCRIPT_DIR/worktree.sh" remove "../escape"
  [ "$status" -ne 0 ]
  [[ "$output" == *"positive integer"* ]]
}
