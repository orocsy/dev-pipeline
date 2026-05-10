---
description: Respond to PR review comments — parse, fix, validate, push. Takes PR number or reads open PR automatically.
---

# Development Pipeline: PR Review Response

You are addressing code review feedback on an open PR.
All steps are pre-approved. Do not ask for permission. Run to completion.

---

## STEP 1: Load Review Comments

```bash
PR="${1:-$(gh pr view --json number --jq '.number')}"
gh pr view "$PR" --json reviews,comments,reviewDecisions \
  | jq '.reviews[-1], .comments'
```

Categorise each comment:
- **Must-fix** — correctness, security, test failures, type errors
- **Should-fix** — style, naming, minor architecture
- **Nit** — formatting, preference (fix if trivial, note if not)

---

## STEP 2: Verify Current State

```bash
git fetch origin
git status
npx tsc --noEmit 2>&1 | tail -20
```

If there are pre-existing errors not mentioned in the review, note them separately — do NOT conflate with review feedback.

---

## STEP 3: Fix All Must-Fix and Should-Fix Items

For each item:
1. Re-read the file before editing
2. Apply the fix
3. Re-read after editing to confirm

After all fixes:
```bash
npx tsc --noEmit
npx eslint . --quiet
npm test -- --passWithNoTests
```

All must pass before proceeding.

---

## STEP 4: Commit and Push

```bash
git add -p   # stage only review-fix changes
git commit -m "fix: address PR review feedback"
git push
```

Do not squash the existing commits. Keep review fixes as a separate commit.

---

## STEP 5: Re-request Review

```bash
gh pr review "$PR" --comment \
  --body "Review feedback addressed. Summary of changes: [list each must-fix and should-fix item resolved]"
```

If nits were skipped, list them explicitly so reviewers know they were seen.

---

## OUTPUT

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ PR REVIEW ADDRESSED: #[N]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Fixed:   [N] must-fix, [N] should-fix
Skipped: [N] nits (listed above)
Pushed:  [commit sha]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
