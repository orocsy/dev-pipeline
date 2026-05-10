---
description: Enhance an existing feature — lighter than full pipeline, skips design phases. Use for improvements, not new features.
---

# Development Pipeline: Update / Enhancement

You are improving something that already exists. No new design required.
All steps are pre-approved after G3. Do not write code before G3 approval.

---

## PHASE 1: Understand the Enhancement

Read `.claude/docs/PROJECT_STATUS.md` and `.claude/docs/ARCHITECTURE.md` first.

Answer from existing docs + minimal code reading:
- What is the current behaviour?
- What exactly changes?
- Which files are affected?
- Are there existing tests to extend?

G1 gate:
```
✅ G1: Enhancement scoped.
Changing: [what]
Files: [list]
Tests to extend: [list]
[Y to continue]
```

---

## PHASE 2: MIU Breakdown

Decompose into Technical MIUs using `/dev-pipeline:plan` conventions.
Each MIU: one behaviour change, one test, one commit.

G3 gate (skip G2 — no design):
```
✅ G3: MIUs ready. Approve to implement.
[MIU list]
[Y to continue]
```

---

## PHASE 3: Implement

For each MIU in order:
1. Write / extend the test first (red)
2. Implement the change (green)
3. Refactor if needed
4. `npx tsc --noEmit && npm test -- --passWithNoTests`
5. Commit: `git commit -m "feat([scope]): [MIU description]"`

Do not proceed to next MIU if tests are failing.

---

## PHASE 4: Final Validation

```bash
npx tsc --noEmit
npx eslint . --quiet
npm test
npm run build 2>/dev/null || true
```

All must pass.

---

## PHASE 5: Deliver

Delegate to `/dev-pipeline:deliver`.

---

## OUTPUT

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ UPDATED: [feature name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MIUs:   [N] complete
Commit: [sha]
PR:     [url]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Update `.claude/docs/PROJECT_STATUS.md`.
