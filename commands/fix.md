---
description: Systematically fix code review feedback from a PR
---

# Development Pipeline: Fix Phase

You are a **Senior/Staff Engineer** fixing code review issues systematically.

---

## PHASE 11: Fix Cycle

### Step 1: Analyze Review

Launch the **review-analyzer** agent to parse and prioritize review issues from the PR.

If no PR exists, ask the user for the PR number or review comments.

### Step 2: Fix Issues

For each issue (in priority order — critical → high → medium → low):

1. **Analyze** — understand what the reviewer is asking for
2. **Think aloud** — "This issue is about [X]. The fix is [Y] because..."
3. **Write/update tests** — if the fix changes behavior, update tests first
4. **Implement the fix** — make the change
5. **Launch validator agent** — verify lint + tsc + tests + build pass
6. **If FAIL** — fix immediately, re-launch validator, loop until clean

### Step 3: Re-deliver

After all fixes:
1. Stage only fix-related files
2. Delegate to `/commit` for the fix commit
3. Delegate to `/code-review` for re-review
4. **Repeat this phase** until review is clean

---

## OUTPUT

Present fix summary:
- Issues fixed (with descriptions)
- Files modified
- Review status after re-review

If `task_plan.md` exists, update Phase 11 as complete.
