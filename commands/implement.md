---
description: Execute the implementation phase — write code per MIU spec, run tests, then run the validation gate (Phase 8). Never skips validation. E2E is required if playwright.config.ts exists.
---

# Development Pipeline: Implement

You are executing approved MIUs. Code to spec, test incrementally, then run the full validation gate. No MIU is "done" until Phase 8 passes.

All steps are pre-approved. Run to completion.

---

## STEP 0: Load Context

Read `.claude/miu-progress.json` and identify the current in-progress MIU.
Read `.claude/docs/ARCHITECTURE.md` and `RECENT_CHANGES.md` — do not explore the codebase if the answer is there.
Load the stack skill from `skills/skill-router/SKILL.md` to confirm which patterns to use.

---

## STEP 1: Implement the MIU

Follow the 8-field MIU spec exactly (acceptance criteria, files affected, dependencies, test requirements).

Rules during implementation:
- One file open at a time — read fully before editing.
- Type everything. No `any` without a comment explaining why.
- Write the test alongside the implementation, not after.
- If you discover the spec is wrong or incomplete, STOP — surface the gap to the user, do not improvise.

---

## STEP 2: Incremental Smoke Check (after each file changed)

```bash
# Fast feedback loop — tsc only, no full test suite yet
npx tsc --noEmit 2>&1 | head -20
```

Fix type errors before moving to the next file. Never accumulate type debt across files.

---

## STEP 3: Unit Tests for This MIU

```bash
# Run only tests related to the changed files (fast)
pnpm turbo test --filter=...[HEAD^1] 2>/dev/null || \
pnpm test --run 2>/dev/null || \
npm test
```

All MIU-specific tests must pass before proceeding. Do not leave failing tests and "come back to them."

---

## STEP 4: Assumption Check (MANDATORY — automatic, before MIU is marked complete)

Invoke the `assumption-checker` agent. It is read-only — no tests, no side
effects. Its job is to compare THIS MIU's diff against the project's
canonical docs (README, project CLAUDE.md, `.claude/docs/ARCHITECTURE.md`,
`.claude/docs/URL_TOPOLOGY.md`, `docs/architecture-*.md`, `prisma/schema.prisma`,
CORS configs) and report drift.

```
Output classes:
  PASS  → continue to STEP 5.
  WARN  → MEDIUM findings; surface in the MIU summary, continue to STEP 5.
  BLOCK → CRITICAL or HIGH findings; do NOT mark the MIU done. Present
          findings to user, then either:
            - resolve the drift (rebase changes to match the doc), OR
            - update the doc (if the doc was stale), OR
            - explicitly waive with an inline justification recorded in
              the MIU's `engineering rationale` block.
```

Why this is automatic, not opt-in: a single undetected wrong-URL / wrong-API
assumption costs hours to unwind. A 30-second assumption check catches it at
the MIU boundary, before the next MIU layers more code on top of the bad
assumption. See `agents/assumption-checker.md` for the full spec including
the failure mode that motivated it.

---

## STEP 5: Mark MIU Complete (tentatively)

Update `.claude/miu-progress.json`: set this MIU status to `"pending-validation"`.

---

## STEP 6: Check if All MIUs Are Complete

```bash
# Are all MIUs for the current product task in "pending-validation" or "done"?
cat .claude/miu-progress.json | jq '.tasks[] | select(.status != "done" and .status != "pending-validation") | .id'
```

If any MIU is still `"in-progress"` or `"pending"`, loop back to STEP 1 for the next MIU.

If all MIUs are `"pending-validation"` → proceed to Phase 8.

---

## STEP 7: Phase 8 — Validation Gate (MANDATORY — never skip)

Invoke `/dev-pipeline:validate` in full. This runs:

```
lint → type-check → unit tests → browser E2E → build
```

### E2E is NOT optional when Playwright is configured

```bash
# This check is authoritative — do NOT rely on turbo test to cover E2E
PLAYWRIGHT_FOUND=false
for cfg in playwright.config.ts playwright.config.js playwright.config.mjs apps/*/playwright.config.ts; do
  [[ -f "$cfg" ]] && PLAYWRIGHT_FOUND=true && break
done

if $PLAYWRIGHT_FOUND; then
  echo "⚠️  Playwright config detected → E2E REQUIRED in Phase 8"
  echo "    /dev-pipeline:validate will invoke scripts/pipeline-e2e.sh"
  echo "    Do NOT proceed if E2E is not executed."
fi
```

**Under no circumstances should Phase 8 be considered passed if:**
- E2E was detected but not run
- E2E was run manually outside the pipeline without a logged exit code
- The output says "e2e tests (if configured)" and was silently skipped
- `pnpm turbo test` was used as a proxy for E2E (it is not — it maps to unit tests only)

If `/dev-pipeline:validate` exits with an error, do NOT proceed. Fix the failure, commit nothing, re-run validate.

---

## STEP 8: On Phase 8 Pass — Update Progress + Hand Off

```bash
# Mark all MIUs done
# (validate writes this on success — confirm it happened)
cat .claude/miu-progress.json | jq '.tasks[].status'
```

Expected: all `"done"`.

Then announce: *"All MIUs complete. Phase 8 passed. Proceeding to delivery gate."*

Invoke `/dev-pipeline:deliver` automatically — do NOT wait for the user to ask.
