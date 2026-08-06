---
description: Analyze and fix code review issues from a PR
argument-hint: [pr-number]
---

# Fix Code Review Issues

Analyze review comments on a pull request, prioritize them, and fix each issue systematically.

## Context

- PR number: $ARGUMENTS
- Current branch: !`git branch --show-current`
- Working directory: !`pwd`

## Workflow

### Step 1: Analyze Review Comments

Launch the **review-analyzer** agent to:
- Fetch all review comments from PR #$1
- Verify each issue against the actual code
- Categorize by severity (Critical / Important / Minor)
- Filter out false positives
- Create a prioritized fix plan

### Step 2: Present Fix Plan

Show the user the prioritized issue list. Ask which issues they want to fix. Wait for approval before proceeding.

### Step 3: Fix Each Issue (MIU methodology)

For each approved issue, in priority order:
1. **Think aloud** — explain what the issue is and why it matters
2. **Fix the issue** — make the minimal, focused change
3. **Launch the validator agent** — verify lint + tsc + tests + build all pass
4. **If validation fails** — fix immediately, re-validate until clean
5. **Move to next issue** — only after current issue is verified

### Step 4: Commit Fixes

After all issues are fixed and validated:
- Stage ONLY the files related to fixes (not unrelated changes)
- Use `/commit` to create a well-formatted commit
- Push to the PR branch

### Step 5: Re-Review (Optional)

Ask the user: "Would you like to run /code-review on the updated PR?"
If yes, delegate to `/code-review`.

## Important Rules

- Fix issues ONE AT A TIME (never batch)
- Validate AFTER EACH fix (never accumulate)
- Stage only necessary files (never `git add -A`)
- If a fix introduces new issues, fix those before moving on

---

## Before you call it fixed: run the gates

This command does not reach `/dev-pipeline:validate` or `/dev-pipeline:review`, so a fix
landed here is otherwise ungated. Run the craft gates against the files you touched before
declaring the fix complete:

```bash
git diff --name-only HEAD > /tmp/changed-files.txt
tools/run-craft-gates.sh --changed-files /tmp/changed-files.txt
# 0 clean/NA · 1 findings · 2 gate execution error (gates did NOT run — not a pass)
```

A fix that closes one finding and opens another is the single most common way a review
round becomes three. Then `/dev-pipeline:review` to re-bless HEAD before pushing.
