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
CORS configs) AND walk the cross-file backward traces (steps 8–14 in its Method
section) for every new symbol the MIU's diff introduces.

```
Output classes:
  PASS  → continue to STEP 4.5.
  WARN  → MEDIUM findings; surface in the MIU summary, continue to STEP 4.5.
  BLOCK → CRITICAL or HIGH findings; do NOT mark the MIU done. Present
          findings to user, then either:
            - resolve the drift (rebase changes to match the doc), OR
            - update the doc (if the doc was stale), OR
            - explicitly waive with an inline justification recorded in
              the MIU's `engineering rationale` block.
```

Why this is automatic, not opt-in: a single undetected wrong-URL / wrong-API /
cross-file assumption costs hours to unwind. A 30-60 second check at the MIU
boundary catches it before the next MIU layers more code on top of the bad
assumption. See `agents/assumption-checker.md` for the full spec including
both failure modes (assumption drift AND cross-file blindness).

---

## STEP 4.5: Cross-File Trace (MANDATORY — automatic, runs before MIU is marked complete)

Load `skills/cross-file-reasoning/SKILL.md` if it isn't already loaded. Walk the
seven traces on every NEW or CHANGED symbol the MIU's diff introduces:

1. **Env-var trace** — for every new `process.env.X`, verify producer (`.github/workflows/*.yml` / `vercel.json` / `docker-compose*.yml`), consumer, and fallback semantics (`??` vs `||`, empty-string behavior).
2. **Route / URL trace** — for every new route file, state the effective URL = `basePath + locale prefix + route group + file path`. Verify it matches what consumers / clients expect.
3. **SDK option-name trace** — for every new SDK config option, `grep -rn '<option>' node_modules/<pkg>/dist/` to verify the option exists in the installed version's type defs. SDKs silently accept unknown keys.
4. **Event lifecycle trace** — for every new emit/subscribe, identify whether listener fires inside a transaction and whether the side effect is fire-and-forget. Document trade-off if ghost-event risk exists.
5. **Mock completeness trace** — for every changed class signature, list every spec that instantiates the class and verify each mock provides the new method/field/arg.
6. **Conditional-coupling trace** — for every new effect inside a conditional, verify the gate matches THAT effect's required precondition (not piggybacked on a shared condition).
7. **Wrapper-lifecycle trace** — for every new wrapper around a long-running primitive, verify teardown is propagated inward.

This step is automatic. Skip ONLY if the MIU diff is doc-only / test-only / comment-only / pure formatting / migration-SQL-only (the allow-list at the bottom of `skills/cross-file-reasoning/SKILL.md`).

Output goes inline in the MIU's `Engineering rationale` block of the execution doc — short YAML block per the skill's output format. If any trace produces a BLOCK verdict, do NOT mark MIU complete; fix and re-run STEP 4.5.

Why this is a SEPARATE step from STEP 4: assumption-checker focuses on diff-vs-docs and includes the cross-file traces in its method, but the cross-file skill is also invokable on its own with a tighter focus (NO doc cross-check, just the seven traces). At MIU boundary, running both gives defense in depth — assumption-checker may catch drift the cross-file skill doesn't (e.g. missing doc update), and the cross-file skill enforces the trace discipline even when no doc exists yet.

The failure-mode catalog at `skills/cross-file-reasoning/FAILURE_MODES.md` is the growing list of bugs this step exists to prevent. Read it before running the traces — if the MIU matches a known pattern, the trace becomes targeted.

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
