---
description: Systematically fix bugs — from PR review feedback or reported directly — with a business-vs-technical triage gate (Rule 23)
---

# Development Pipeline: Fix Phase

You are a **Senior/Staff Engineer** fixing code review issues systematically.

---

## PHASE 11: Fix Cycle

### Step 1: Analyze Review

Launch the **review-analyzer** agent to parse and prioritize review issues from the PR.

If no PR exists, ask the user for the PR number or review comments.

### Step 1.5: Bug Triage — business vs technical (per CLAUDE.md Rule 23)

This flow fixes issues from two sources: PR-review comments (Step 1) **and** bugs reported directly by the user (the "no PR" branch above). For EACH issue, before writing the fix, apply the business-vs-technical test (canonical definition: `skills/spec-elicitor/SKILL.md` → "When to run me"):

> **Is the correct behaviour self-evident, or is it itself the thing in question?**

- **Technical / mechanical** (crash, `TypeError`, compile/lint/test failure, 500, null deref) → the right outcome is obvious. Proceed straight to Step 2.
- **Business / behavioural** (e.g. "the loyalty discount applies twice", "shows status X but should show Y") → the right outcome must be *decided*, not assumed. **Invoke the `dev-pipeline:spec-elicitor` skill in Scope-Lock mode (Mode B)** — 2–4 questions, no file — to lock the intended behaviour. Fold the resulting 🔒 Intent Lock into the fix's commit/PR body, then proceed to Step 2.

In practice, PR-review issues (Step 1) are almost always technical — `review-analyzer` surfaces correctness / type / test items — so they go straight to Step 2; the business branch chiefly applies to the directly-reported-bug case. Do NOT run a separate dialogue per issue: if several issues share one undecided behaviour, run a SINGLE Scope-Lock pass covering all open axes, then fix.

Why this gate exists (see Rules 18 & 19): if you "fix" a behavioural bug without first deciding what the behaviour *should* be, you either ship your own guess or — worse — rewrite the test to agree with the new code, producing a green build that proves nothing. Lock intent first; then the fix and its test mean something.

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
