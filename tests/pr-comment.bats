#!/usr/bin/env bats

load 'test_helper/common'

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
  mock_gh
}

teardown() {
  teardown_gh_mock
}

@test "posts comment with body from stdin" {
  run bash -c 'echo "## Test Comment" | "$1" 42' _ "$SCRIPT_DIR/pr-comment.sh"
  [ "$status" -eq 0 ]

  local calls
  calls="$(get_gh_calls)"
  [[ "$calls" == *"pr comment 42"* ]]
  [[ "$calls" == *"--body-file"* ]]
}

@test "fails with no PR number" {
  run bash -c 'echo "body" | "$1"' _ "$SCRIPT_DIR/pr-comment.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "fails when gh command fails" {
  set_gh_exit_code 1
  run bash -c 'echo "body" | "$1" 42' _ "$SCRIPT_DIR/pr-comment.sh"
  [ "$status" -ne 0 ]
}

@test "fails with empty body from stdin" {
  run bash -c 'printf "" | "$1" 42' _ "$SCRIPT_DIR/pr-comment.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty body"* ]]
}

@test "passes through multiline markdown body" {
  run bash -c '
    printf "## Title\n**Cycles**: 3 | **Fixes**: 5\n\n- item 1\n- item 2" | "$1" 42
  ' _ "$SCRIPT_DIR/pr-comment.sh"
  [ "$status" -eq 0 ]

  local calls
  calls="$(get_gh_calls)"
  [[ "$calls" == *"pr comment 42"* ]]
}
