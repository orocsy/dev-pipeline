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

**Intent check (per CLAUDE.md Rule 23).** Apply the business-vs-technical test (`skills/spec-elicitor/SKILL.md` → "When to run me"): is the intended behaviour of this enhancement self-evident, or is an axis still undecided — "should it also handle invited users?", "does the new toggle apply per-user or per-org?". If an axis is undecided, **invoke the `dev-pipeline:spec-elicitor` skill in Scope-Lock mode (Mode B)** — 2–4 questions, no file — and fold the 🔒 Intent Lock into the G1 scope statement below. If the change is purely mechanical (rename, bump, obvious tweak), skip straight to G1.

G1 gate:
```
✅ G1: Enhancement scoped.
Changing: [what]
Files: [list]
Tests to extend: [list]
Intent locked: [🔒 Intent Lock summary if Scope-Lock ran, else "behaviour self-evident — no clarification needed"]
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
