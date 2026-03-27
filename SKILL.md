---
name: copilot-review-loop
description: "Runs an autonomous Copilot review loop on a PR in the background — requests review, reads comments, classifies severity, fixes code, resolves threads, re-requests review, and repeats. Bails if the PR is irredeemable, stops if only nitpicks remain or feedback is not applicable in project context. Runs in a git worktree in the background so you can keep working. Trigger on: 'copilot review', 'review loop', 'start a review session', 'iterate on copilot feedback', 'fix PR comments', 'copilot review PR #N', 'run copilot review', 'review in background', or any request to run/start/begin copilot review on a PR."
---

# Copilot Review Loop

Autonomous Copilot code review loop. Requests review, classifies comments by severity with project-context awareness, fixes code, resolves threads, re-requests review, and repeats.

**This skill runs in a git worktree** for isolation. **Always launch as a background agent** so the user gets their terminal back immediately.

When spawning the agent, use:
```
Agent(
  run_in_background: true,
  name: "copilot-review-<PR_NUM>"
)
```

**Permission model:** Background agents inherit the parent session's permission settings. When the user is running in **auto mode**, the background agent will also run in auto mode — no tool calls will be blocked. If the user is NOT in auto mode, Bash/Edit/Write calls may require approval, which can cause the background agent to stall. In that case, recommend the user enable auto mode before launching (`/auto`) or run the skill in the foreground.

**Exit conditions:**
- **Clean pass**: Copilot reports "generated no new comments"
- **Nitpicks only**: All remaining feedback is style/preference — fix and stop
- **Contextual override**: All remaining feedback is not applicable in this project's context — dismiss and stop
- **Bail**: PR is irredeemable — new criticals keep appearing, same critical won't fix, or moderate churn
- **Cap**: 7 cycles max

## Prerequisites

Before starting, verify:

```bash
# Must be authenticated
gh auth status
```

Note: This skill uses the GitHub REST API directly (`gh api`) to request and re-request Copilot reviews. It does NOT require `gh` v2.88.0+ or `gh pr edit --add-reviewer`.

**RECOMMENDED**: Enable "Review new pushes" in the Copilot code review ruleset (Settings > Rules > Rulesets > Copilot code review > Review new pushes) for automatic re-review on push. If not enabled, the skill uses an API workaround (add/remove/add reviewer) to trigger re-reviews programmatically.

## Step 1: Parse the PR

If the user provides a PR number (from args or natural language), use it directly.

Otherwise, auto-detect from the current branch:

```bash
gh pr view --json number,headRefName,baseRepository -q '{
  number: .number,
  branch: .headRefName,
  owner: .baseRepository.owner.login,
  repo: .baseRepository.name
}'
```

Extract and store: `OWNER`, `REPO`, `PR_NUM`, `BRANCH`.

If no PR found, ask the user for the PR number.

## Step 2: Concurrency Guard

```bash
git worktree list | grep "copilot-review-${PR_NUM}"
```

If a worktree already exists for this PR, report: "A copilot review loop is already running for PR #N. Wait for it to finish or remove the stale worktree." and stop.

## Step 3: Create Worktree and Enter Background

**Spawn this as a background agent now** using `Agent(run_in_background: true)`. The user should get their terminal back immediately.

Ensure the PR branch exists locally before creating the worktree:

```bash
git fetch origin "${BRANCH}" 2>/dev/null || git fetch origin "refs/pull/${PR_NUM}/head"
```

Create the worktree using the companion script. The worktree is created in **detached HEAD** mode so it works even when the user is currently on the PR branch:

```bash
SKILL_DIR="$HOME/.claude/skills/copilot-review-loop"
"${SKILL_DIR}/scripts/worktree.sh" create "${BRANCH}" "${PR_NUM}"
```

**Note**: Because the worktree uses detached HEAD, use `git push origin HEAD:${BRANCH}` instead of plain `git push` when pushing from the worktree.

The worktree path will be `$TMPDIR/copilot-review-<PR_NUM>` (macOS/Linux) or `$TEMP/copilot-review-<PR_NUM>` (Windows), falling back to `/tmp/copilot-review-<PR_NUM>`.

**All subsequent operations run from inside the worktree directory.**

Set up a trap to ensure cleanup on any exit:

```bash
trap '"${SKILL_DIR}/scripts/worktree.sh" remove "${PR_NUM}"' EXIT
```

## Step 4: Initialize Loop State

```
cycle = 0
maxCycles = 7
lastSeenReviewAt = null
criticalHistory = []
moderateHistory = []
totalFixesApplied = 0
totalSkipped = 0
totalDismissed = 0
```

## Step 5: Request Initial Copilot Review

```bash
gh api --method POST "repos/${OWNER}/${REPO}/pulls/${PR_NUM}/requested_reviewers" \
  -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
```

### Re-requesting Copilot Review (after Copilot has already submitted)

GitHub has no official API to re-request a review from a reviewer who already submitted. The workaround is an **add -> remove -> add** sequence:

```bash
# Step 1: Add Copilot back as pending reviewer (alongside its submitted review)
gh api --method POST "repos/${OWNER}/${REPO}/pulls/${PR_NUM}/requested_reviewers" \
  -f 'reviewers[]=copilot-pull-request-reviewer[bot]'

# Step 2: Remove the pending request
# IMPORTANT: DELETE uses username "Copilot" (not "copilot-pull-request-reviewer[bot]")
gh api --method DELETE "repos/${OWNER}/${REPO}/pulls/${PR_NUM}/requested_reviewers" \
  -f 'reviewers[]=Copilot'

# Step 3: Add again — this triggers a fresh review
gh api --method POST "repos/${OWNER}/${REPO}/pulls/${PR_NUM}/requested_reviewers" \
  -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
```

Use this sequence at the end of each cycle (step 6h) to trigger the next review. If "Review new pushes" is enabled on the repo, the push alone will trigger re-review and this sequence is not needed — but the add/remove/add workaround works regardless of ruleset configuration.

## Step 6: Main Loop (repeat until exit condition)

```
while cycle < maxCycles:
  cycle += 1
```

### 6a: Poll for Copilot Review Completion

Query every 15 seconds. Timeout after 5 minutes (20 polls). If Copilot hasn't responded after 5 minutes, post a PR comment reporting the timeout, report to terminal, cleanup worktree, and **EXIT LOOP** (bail).

**IMPORTANT -- Copilot author login**: In GraphQL, Copilot's author login is `"copilot-pull-request-reviewer"` (NOT `"copilot"` or `"Copilot"` -- those are REST API values). Always filter by this exact string.

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviews(last: 20) {
          nodes {
            author { login }
            state
            submittedAt
            body
          }
        }
        commits(last: 1) {
          nodes { commit { pushedDate committedDate } }
        }
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 10) {
              nodes {
                body
                author { login }
                path
                line
                originalLine
              }
            }
          }
        }
      }
    }
  }
' -F owner="${OWNER}" -F repo="${REPO}" -F pr="${PR_NUM}"
```

**Filter the response**: Extract only reviews and threads where `author.login == "copilot-pull-request-reviewer"`. Ignore all other reviewers.

```
{
  review: latest review node where author.login == "copilot-pull-request-reviewer" (sorted by submittedAt),
  latestCommit: last commit's pushedDate (preferred) or committedDate (fallback),
  unresolvedThreads: reviewThread nodes where isResolved == false AND first comment's author.login == "copilot-pull-request-reviewer"
}
```

**Decision logic (in order):**

1. **No Copilot review exists**: Trigger one with `gh pr edit --add-reviewer "@copilot"`, wait for next poll.
2. **`review.submittedAt` < `latestCommit`**: Copilot hasn't reviewed latest push. Wait. Use `pushedDate` (not `committedDate`) for this comparison — `committedDate` is the author timestamp which can be older than the actual push.
3. **`review.submittedAt` <= `lastSeenReviewAt`**: Re-triggered review hasn't arrived yet. Wait. This prevents the race condition where the loop sees a stale review and falsely concludes there are no comments.
4. **`review.body` contains "generated no new comments"**: Clean pass. **STOP (clean).**
5. **`review.body` contains "generated N comments" (N > 0)**: Proceed to classify.

**Rate limiting**: If GraphQL returns 403/429, back off exponentially (30s, 60s, 120s). Bail after 3 consecutive backoff failures.

### 6b: Classify Each Unresolved Comment

For each unresolved Copilot thread (filtered by `author.login == "copilot-pull-request-reviewer"`), classify as:

- **CRITICAL**: Security vulnerability, data loss, race condition, crash, logic error, broken API contract
- **MODERATE**: Real bug but contained, missing edge case, error handling gap
- **NITPICK**: Style, naming, "consider using X", overengineering suggestion, semantic preference

### 6c: Contextual Evaluation

For each classified comment, read:
- The flagged line and its surrounding function/block
- Direct callers of the flagged function (1 level up)
- Relevant CLAUDE.md conventions and project patterns

**Do NOT scan**: entire codebase, transitive callers, unrelated files. Keep evaluation scope tight to control token usage.

Evaluate whether the concern is actually valid in this project's context. Downgrade or dismiss comments that are not applicable. Examples:
- "Missing error handling" but caught upstream -> NITPICK or skip
- "SQL injection" but ORM handles it -> skip
- "Use X pattern" but project uses Y per convention -> NITPICK

### 6d: Assess PR Health

Generate a semantic fingerprint for each critical: `file_path:function_name:issue_summary`
(e.g., `auth/session.ts:refreshToken:race-condition`). Do NOT use line numbers for fingerprinting -- they shift after fixes.

Record in `criticalHistory[cycle] = {count, fingerprints}`.
Record in `moderateHistory[cycle] = {count}`.

**BAIL if any:**
- New criticals appearing across 3+ consecutive cycles (whack-a-mole)
- Same critical fingerprint persists after 2 fix attempts
- Critical count increasing cycle over cycle
- Moderate count not decreasing over 3+ consecutive cycles

-> On bail: post PR comment (bail template from PR Comment Templates section below), report to terminal, cleanup worktree, **EXIT LOOP**.

**STOP if:**
- All remaining comments are NITPICK after contextual evaluation
- All remaining comments dismissed as not applicable in project context

-> On nitpick stop: fix nitpicks, resolve threads, commit, push, post PR comment, **EXIT LOOP**.
-> On contextual override: resolve threads, post dismissal summary, **EXIT LOOP**.

**CONTINUE**: Criticals/moderates exist and trend is improving.

### 6e: Fix Code

Fix in priority order: criticals first, then moderates.

For each comment:
1. Read the referenced file and line
2. Understand the suggestion and evaluate if it makes sense
3. Apply the fix
4. If a suggestion is incorrect or conflicts with project architecture, skip it and note the reason

**Do not blindly accept every suggestion.**

### 6f: Run Tests

Detect test command (in order):
1. `CLAUDE.md` explicit test instructions
2. `package.json` -> `npm test`
3. `Makefile` -> `make test`
4. `pytest.ini` / `setup.cfg` -> `pytest`
5. Go project -> `go test ./...`
6. If nothing found, skip and note in report

Run with 5-minute timeout.

**On failure:** Attempt 1 fix. If fix conflicts with Copilot suggestion, revert that suggestion (mark skipped). Re-run. If still failing, revert all cycle changes with `git checkout .` and bail with report.

### 6g: Commit and Push

Commit with conventional format:

```
fix: resolve copilot review feedback (cycle N)

- Fixed: <description of each fix>
- Skipped: <description of each skip and why>
```

Resolve all fixed/evaluated threads via GraphQL **BEFORE pushing** (so Copilot's auto-triggered re-review sees a clean state):

```bash
gh api graphql -f query='
  mutation {
    resolveReviewThread(input: {threadId: "<THREAD_NODE_ID>"}) {
      thread { isResolved }
    }
  }
'
```

Then push (detached HEAD requires explicit refspec):

```bash
git push origin HEAD:${BRANCH}
```

**Push failure handling:**
- Merge conflict -> bail and report "Push failed due to merge conflict. Manual resolution needed."
- Branch protection rejection -> bail and report the rejection reason
- Other -> retry once with 10s delay, then bail

### 6h: Record and Report

```
lastSeenReviewAt = review.submittedAt
```

Report to terminal:
```
[copilot-review-loop] Cycle N/7 complete -- fixed X criticals, Y moderates | Z criticals, W moderates remaining
```

**Re-request Copilot review** using the add/remove/add workaround from Step 5:

```bash
gh api --method POST "repos/${OWNER}/${REPO}/pulls/${PR_NUM}/requested_reviewers" \
  -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
gh api --method DELETE "repos/${OWNER}/${REPO}/pulls/${PR_NUM}/requested_reviewers" \
  -f 'reviewers[]=Copilot'
gh api --method POST "repos/${OWNER}/${REPO}/pulls/${PR_NUM}/requested_reviewers" \
  -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
```

**Loop continues to next cycle.**

## Step 7: Post Summary and Cleanup

On any exit (clean, nitpick stop, contextual override, bail, cap):

Post summary comment to PR using the companion script:

```bash
echo "${SUMMARY}" | "$HOME/.claude/skills/copilot-review-loop/scripts/pr-comment.sh" "${PR_NUM}"
```

Use the appropriate template from the **PR Comment Templates** section below based on exit reason.

Report final status to terminal.

Worktree cleanup happens automatically via the EXIT trap.

## Error Handling

- **Network/API failures**: Retry up to 2 times with 10s delay. If still failing, bail and report the error.
- **Auth token expiration**: If `gh auth status` fails mid-loop, bail and report "GitHub authentication expired. Re-authenticate and restart."
- **Worktree cleanup failure** (locked files on Windows): Report stale worktree path for manual cleanup.

## PR Comment Templates

### Clean Pass
```
## Copilot Review Loop -- Complete
**Cycles**: N | **Fixes applied**: N | **Skipped (not applicable)**: N

All Copilot feedback resolved. Ready for human review.
```

### Nitpicks Only
```
## Copilot Review Loop -- Complete
**Cycles**: N | **Fixes applied**: N | **Nitpicks fixed (final pass)**: N

Remaining Copilot feedback was style/preference only. Applied and stopped.
```

### Contextual Override
```
## Copilot Review Loop -- Complete
**Cycles**: N | **Fixes applied**: N | **Dismissed (not applicable)**: N

Remaining feedback not applicable in project context:
- `file:line` -- "issue" -> reason for dismissal
```

### Bail
```
## Copilot Review Loop -- Bailed
**Cycles**: N | **Fixes applied**: N | **Recurring/new criticals**: N

This PR appears to have fundamental issues -- new critical bugs keep surfacing as others are fixed. Recommend closing and rethinking the approach.

**Unresolved criticals:**
- `file:line` -- description (reason for bail)
```

### Cap Hit
```
## Copilot Review Loop -- Stopped (iteration cap)
**Cycles**: 7 | **Fixes applied**: N

Hit 7-cycle cap. Remaining issues need manual review.
```
