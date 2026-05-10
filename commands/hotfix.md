---
description: Production incident fast path — skip design phases, straight to fix, validate, deliver. For production-down or critical regressions only.
---

# Development Pipeline: Hotfix

You are fixing a production incident. Speed matters. Skip all design phases.
All steps are pre-approved. Do not ask for permission. Run to completion.

⚠️ This flow bypasses G1–G3. G4 (final approval before push) still applies.

---

## STEP 1: Capture Incident Context (60 seconds max)

Answer these from the user's description or logs — do NOT ask:
- What is broken? (symptom)
- What changed last? (`git log --oneline -10`)
- Is there an error message / stack trace?

```bash
git log --oneline -10
git diff HEAD~1 -- $(git diff --name-only HEAD~1)
```

---

## STEP 2: Reproduce Locally

Write the minimal failing test or reproduction script first. If you cannot reproduce, say so explicitly before proceeding.

---

## STEP 3: Fix

Implement the targeted fix. Touch the minimum number of files.
No refactoring. No "while I'm here" improvements. Fix the incident only.

After fixing:
```bash
npx tsc --noEmit
npx eslint . --quiet
npm test -- --passWithNoTests
```

---

## STEP 4: G4 Gate — Final Approval

```
✅ G4 HOTFIX: Fix ready.
Symptom:  [what was broken]
Root cause: [why it broke]
Fix:      [what changed, N files]
Tests:    ✅ passing
⚠️ Confirm to push directly to main. [Y to continue]
```

Wait for explicit confirmation.

---

## STEP 5: Deliver

After G4 approval, delegate to `/dev-pipeline:deliver`.

The deliver flow will:
- Commit with `hotfix:` prefix
- Push and create PR
- Auto-merge if CI passes
- Deploy immediately

---

## STEP 6: Post-Incident Note

After merge, add a brief entry to `.claude/docs/RECENT_CHANGES.md`:
```
[HOTFIX] [date] — [symptom] — root cause: [X] — fixed by: [change summary]
```

Run `/dev-pipeline:sync` to refresh all living documents.
