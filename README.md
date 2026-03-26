# copilot-review-loop

A Claude Code skill that autonomously loops through GitHub Copilot code review cycles on a PR.

**What it does:**
1. Requests a Copilot review on your PR
2. Reads the review comments
3. Classifies each comment by severity (critical / moderate / nitpick) with project-context awareness
4. Fixes the code
5. Resolves the review threads
6. Pushes and re-requests review
7. Repeats until done

**Smart exit conditions:**
- **Clean pass** -- Copilot has no more comments
- **Nitpicks only** -- remaining feedback is style/preference, fixes them and stops
- **Contextual override** -- remaining feedback doesn't apply in your project's context, dismisses with explanation
- **Bail** -- PR is fundamentally broken (new criticals keep appearing, same bug won't fix)
- **Cap** -- 7 cycles max

Runs in a **git worktree in the background** so you can keep working on other things.

## Installation

### Option 1: Symlink (recommended for development)

```bash
git clone https://github.com/WLindnerHS/copilot-review-loop.git ~/copilot-review-loop

# macOS/Linux
ln -s ~/copilot-review-loop ~/.claude/skills/copilot-review-loop

# Windows (run as admin or with developer mode enabled)
mklink /J "%USERPROFILE%\.claude\skills\copilot-review-loop" "%USERPROFILE%\copilot-review-loop"
```

### Option 2: Direct clone into skills

```bash
git clone https://github.com/WLindnerHS/copilot-review-loop.git ~/.claude/skills/copilot-review-loop
```

## Prerequisites

- **GitHub CLI** (`gh`) v2.88.0+ -- [install](https://cli.github.com)
- **Authenticated**: `gh auth status`
- **"Review new pushes" enabled** in your repo's Copilot code review ruleset:
  Settings > Rules > Rulesets > Copilot code review > Review new pushes

## Usage

### Slash command

```
/copilot-review-loop PR#53
```

### Natural language

```
Can you start a copilot review session on PR 53?
```

```
Run copilot review loop on the current PR
```

```
Iterate on copilot feedback for PR #123
```

The skill will auto-detect the PR from your current branch if you don't specify one.

## How it works

Each cycle:

1. **Poll** for Copilot review completion (15s intervals, 5min timeout)
2. **Classify** each comment: CRITICAL / MODERATE / NITPICK
3. **Contextual evaluation** -- reads your code, CLAUDE.md, and project patterns to determine if feedback actually applies
4. **Assess PR health** -- tracks critical/moderate counts across cycles, detects whack-a-mole patterns
5. **Fix** code (criticals first, then moderates)
6. **Run tests** (auto-detects test command)
7. **Resolve threads** before pushing (so Copilot sees clean state on re-review)
8. **Push** and loop

### Bail conditions

The skill bails (recommends closing the PR) when:
- New critical bugs keep surfacing across 3+ consecutive cycles
- The same critical persists after 2 fix attempts
- Critical count is increasing cycle over cycle
- Moderate count isn't decreasing over 3+ cycles

### PR comment summary

On completion, the skill posts a summary comment to the PR with stats (cycles, fixes applied, skipped/dismissed) and the exit reason.

## File structure

```
copilot-review-loop/
├── SKILL.md              # Core skill prompt
├── scripts/
│   ├── worktree.sh       # Git worktree create/cleanup
│   └── pr-comment.sh     # Post summary comment to PR
└── tests/
    ├── test_helper/
    │   └── common.bash   # Shared test fixtures
    ├── worktree.bats     # worktree.sh tests
    └── pr-comment.bats   # pr-comment.sh tests
```

## Running tests

Requires [bats-core](https://github.com/bats-core/bats-core):

```bash
npm install -g bats
bats tests/
```

## License

MIT
