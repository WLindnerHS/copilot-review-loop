# common.bash — shared test fixtures and mocks for copilot-review-loop tests

# Create a temporary git repo for worktree tests
setup_git_repo() {
  export TEST_REPO_DIR="$(mktemp -d)"
  cd "$TEST_REPO_DIR"
  git init
  git config user.name "Test"
  git config user.email "test@test.com"
  git commit --allow-empty -m "initial commit"
  git checkout -b test-branch
  git checkout -b main
}

teardown_git_repo() {
  cd /
  # Clean up any worktrees first (both git tracking and actual directories)
  if [ -d "$TEST_REPO_DIR" ]; then
    cd "$TEST_REPO_DIR"
    git worktree list --porcelain | grep "^worktree " | grep -v "$TEST_REPO_DIR$" | awk '{print $2}' | while read wt; do
      git worktree remove --force "$wt" 2>/dev/null || true
      rm -rf "$wt" 2>/dev/null || true
    done
    cd /
    rm -rf "$TEST_REPO_DIR"
  fi
}

# Mock gh CLI — records calls and returns canned responses
# Uses unquoted heredoc so GH_MOCK_DIR is baked in at creation time.
mock_gh() {
  export GH_MOCK_DIR="$(mktemp -d)"
  export PATH="$GH_MOCK_DIR:$PATH"
  cat > "$GH_MOCK_DIR/gh" << MOCK
#!/bin/bash
echo "\$@" >> "$GH_MOCK_DIR/gh_calls.log"
cat >> "$GH_MOCK_DIR/gh_stdin.log" 2>/dev/null || true
if [ -f "$GH_MOCK_DIR/gh_response" ]; then
  cat "$GH_MOCK_DIR/gh_response"
fi
exit \${GH_MOCK_EXIT:-0}
MOCK
  chmod +x "$GH_MOCK_DIR/gh"
}

set_gh_response() {
  echo "$1" > "$GH_MOCK_DIR/gh_response"
}

set_gh_exit_code() {
  export GH_MOCK_EXIT="$1"
}

get_gh_calls() {
  cat "$GH_MOCK_DIR/gh_calls.log" 2>/dev/null || echo ""
}

get_gh_stdin() {
  cat "$GH_MOCK_DIR/gh_stdin.log" 2>/dev/null || echo ""
}

teardown_gh_mock() {
  rm -rf "$GH_MOCK_DIR"
  unset GH_MOCK_DIR GH_MOCK_EXIT
}
