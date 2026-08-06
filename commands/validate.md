---
description: Phase 8 validation gate — lint, type-check, unit tests, REQUIRED browser E2E (when playwright config exists), build. Fails loudly if any gate is skipped. Use after implementation is complete, before commit/deliver.
---

# Development Pipeline: Validate (Phase 8)

You are the validation gate. Your job is to PREVENT bad code from reaching the commit step. Every check is mandatory. You do NOT skip, summarize, or defer.

All steps are pre-approved. Run to completion or fail with an actionable error message.

**Consult-on-failure (best-practice sources):** validation itself stays mechanical — a green run loads no skills. But when any gate below goes red (lint, type-check, unit tests, build), BEFORE entering the fix loop check `.claude/project-context.json` → `bestPracticeSources[]` and load each `installed` source whose signal matches the failing files (e.g. `typescript-best-practices` for tsc errors, `vercel:react-best-practices` for a `.tsx` test failure). The fix should follow the source's patterns, not an ad-hoc workaround. `missing` sources → recorded fallback, never a blocker. Mapping + phase weights live in `skills/skill-router/SKILL.md` → "Best-Practice Source Routing".

---

## STEP 0: E2E Pre-detection (runs FIRST — gates the rest of the plan)

```bash
# Detect Playwright config at repo root or apps/* (monorepo-aware)
PLAYWRIGHT_CONFIG=""
for candidate in \
  playwright.config.ts \
  playwright.config.js \
  playwright.config.mjs \
  apps/*/playwright.config.ts \
  apps/*/playwright.config.js; do
  if [[ -f "$candidate" ]]; then
    PLAYWRIGHT_CONFIG="$candidate"
    break
  fi
done

if [[ -n "$PLAYWRIGHT_CONFIG" ]]; then
  echo "✅ Playwright config found: $PLAYWRIGHT_CONFIG"
  echo "⚠️  E2E IS REQUIRED for this validation run — it will not be skipped."
  E2E_REQUIRED=true
else
  echo "ℹ️  No Playwright config detected — E2E step will be skipped."
  E2E_REQUIRED=false
fi
```

**Hard rule:** If `E2E_REQUIRED=true` and E2E is not executed (for any reason including timeout, missing env vars, failed server start), Phase 8 FAILS. Do not proceed to commit. Surface the exact blocker to the user.

---

## STEP 1: Lint

```bash
# Respect turbo if present, fall back to direct eslint
if command -v pnpm &>/dev/null && grep -q '"lint"' turbo.json 2>/dev/null; then
  pnpm turbo lint --filter=...[HEAD^1]
else
  npx eslint . --ext .ts,.tsx,.js,.jsx --max-warnings=0
fi
```

Fail immediately on any error. Do NOT proceed past lint failures.

---

## STEP 2: Type-check

```bash
# Run tsc noEmit on all packages with a tsconfig
if command -v pnpm &>/dev/null && grep -q '"typecheck"' turbo.json 2>/dev/null; then
  pnpm turbo typecheck
else
  npx tsc --noEmit
fi
```

Fail immediately on type errors.

**Type-check passing is necessary but NOT sufficient for third-party surfaces** — a hand-written `.d.ts` stub can make `tsc` pass against a method that does not exist at runtime. See STEP 2.6.

---

## STEP 2.6: SDK/API Reality-Check (Phase 7.6)

If the diff imports/uses a third-party package or edits any `*.d.ts`, invoke **`/dev-pipeline:verify-sdk-surface`** (CLAUDE.md Rule 22). `tsc` trusts your stubs; this step trusts only the INSTALLED package's own `.d.ts` (+ context7 latest docs) and requires a recorded `SDK-PROBE.md`. It FAILS Phase 8 if a called/stubbed third-party method is absent from the installed types, borrowed from the wrong package, or its return shape diverges from the installed declaration.

```bash
# Loose trigger — verify-sdk-surface STEP 0 does the precise filtering (skips if none).
# $BASE was never set in this file — with it unset, "$BASE"..HEAD expanded to "..HEAD",
# which git treats as HEAD..HEAD (an empty range), so this trigger silently NEVER fired.
# Also: no "..HEAD" — this step runs pre-commit (per this file's own Phase 8 framing,
# "before commit/deliver"), so the diff must include the working tree, not just what's
# already committed. Third line mirrors review.md's own fix: fires on any added call-like
# pattern too, not just new import/require lines (a call on an ALREADY-imported package).
BASE="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD~1)"
if git diff "$BASE" --name-only | grep -qE '\.d\.ts$' \
   || git diff "$BASE" | grep -qE '^\+.*(import |require\()' \
   || git diff "$BASE" | grep -qE '^\+.*\.[A-Za-z_][A-Za-z0-9_]*\('; then
  echo "→ Phase 7.6: running /dev-pipeline:verify-sdk-surface"
fi
```

---

## STEP 2.7: Executable craft gates (MANDATORY, unconditional)

Same gate set as `/dev-pipeline:review` STEP 1.7, run here too because **this command does
not invoke review** — it is a peer gate chain, not a caller. A gate wired only into the
review path never fires for anyone who validates and commits, which is the family-addition
failure the gates themselves exist to catch. (Found by dogfooding: the review that
introduced STEP 1.7 enumerated its own sibling commands and found `validate.md` uncovered.)

```bash
tools/run-craft-gates.sh
GATE_RC=$?   # 0 clean/NA · 1 findings · 2 gate execution error (P1 — gates did NOT run)
```

Aggregate `GATE_RC` into the Phase 8 summary alongside lint/typecheck/tests/build.
A non-zero here fails the phase exactly like a failing test would; `2` fails it harder,
because an unrun gate is a bigger problem than a known finding.

Severity mapping and the baseline rule are identical to review STEP 1.7 — see that step;
do not restate them here, so the two cannot drift apart.

---

## STEP 3: Unit Tests

```bash
# turbo test maps to unit tests ONLY — this is intentional here
if command -v pnpm &>/dev/null && grep -q '"test"' turbo.json 2>/dev/null; then
  pnpm turbo test --filter=...[HEAD^1]
else
  pnpm test --run 2>/dev/null || npm test
fi
```

Fail on any test failure. Do NOT proceed to E2E if unit tests are red — fix unit tests first.

---

## STEP 3.5: Mutation-Testing Backstop (OPT-IN — Rule 19 mechanical check)

Green unit tests prove nothing when the diff REWROTE the assertions — a test rewritten
alongside the behaviour passes because you wrote it to pass (Rule 19: agreement with
yourself, not correctness). This step adds a mechanical backstop, gated on TWO conditions
so it never taxes ordinary runs:

1. **Trigger — the diff rewrites existing test expectations:**

```bash
BASE="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD~1)"
# Rewrite = an existing expect line REMOVED in a test file (a pure test addition — only
# '+' expect lines — is the Rule-19-safe pattern and does NOT trigger this step).
if git diff "$BASE" -- '*.spec.*' '*.test.*' | grep -qE '^-.*expect\('; then
  ASSERTION_REWRITE=true
else
  ASSERTION_REWRITE=false
fi
```

2. **Opt-in — the consumer repo has Stryker configured** (`stryker.conf.*` /
   `stryker.config.*` at root or `apps/*`, or `@stryker-mutator/core` in devDependencies).
   No Stryker → annotate `[mutation backstop: skipped — repo not opted in]` and move on.
   The plugin ships no runtime; repos opt in simply by configuring Stryker.

When BOTH hold, run mutation tests **scoped to the changed source files** (fast — not the
whole repo):

```bash
CHANGED_SRC=$(git diff "$BASE" --name-only -- '*.ts' '*.tsx' '*.js' '*.jsx' \
  | grep -vE '\.(spec|test)\.' | paste -sd, -)
if [[ -z "$CHANGED_SRC" ]]; then
  # Pure test refactor: assertions were rewritten but no source file changed —
  # there is nothing to mutate, and `--mutate ""` makes Stryker error noisily.
  echo "[mutation backstop: skipped — assertion rewrite with no changed source files (pure test refactor); nothing to mutate]"
else
  # pipefail: without it the pipeline returns tail's exit (always 0), silently
  # masking a Stryker crash — gate semantics below say a Stryker error must
  # surface as the review finding, never be swallowed.
  set -o pipefail
  npx stryker run --mutate "$CHANGED_SRC" --incremental 2>&1 | tail -20
  STRYKER_EXIT=$?
  set +o pipefail
  if [[ $STRYKER_EXIT -ne 0 ]]; then
    echo "[mutation backstop: stryker exited $STRYKER_EXIT — report this error as the review finding (gate semantics); NOT a silent skip]"
  fi
fi
```

**Gate semantics (deliberately soft at introduction):**
- Mutation score **< 70%** on the changed files → surface as a **review finding**
  ("rewritten tests kill only N% of mutants in the code they claim to cover — the new
  assertions may be tautological; see Rule 19"), NOT a hard Phase 8 block.
- Mutation score ≥ 70% or step skipped → annotate and continue.
- Never silently skip when both trigger conditions hold — if Stryker errors out, report
  the error as the finding. (The empty-`CHANGED_SRC` pure-test-refactor skip above is
  annotated, not silent.)

Rule 19's three safer patterns (`docs/RULES.md`) remain the primary defense; this step is
the mechanical detector for the case where they were bypassed.

---

## STEP 4: Browser E2E (MANDATORY when Playwright config present)

If `E2E_REQUIRED=false`, skip this step and annotate: `[E2E: skipped — no playwright config]`.

If `E2E_REQUIRED=true`, run `scripts/pipeline-e2e.sh` (installed by install.sh):

```bash
# pipeline-e2e.sh handles: server spin-up → readiness wait → test run → teardown
# It reads PLAYWRIGHT_BOOKING_URL and PLAYWRIGHT_ADMIN_URL from .env.local if not set
bash "$(git rev-parse --show-toplevel)/scripts/pipeline-e2e.sh"
E2E_EXIT=$?

if [[ $E2E_EXIT -ne 0 ]]; then
  echo ""
  echo "🛑 PHASE 8 BLOCKED — E2E tests failed (exit $E2E_EXIT)"
  echo ""
  echo "Possible causes:"
  echo "  1. A test assertion failed — check playwright-report/ for trace"
  echo "  2. Dev server failed to start — check .e2e-server.log"
  echo "  3. Missing env vars — PLAYWRIGHT_BOOKING_URL, PLAYWRIGHT_ADMIN_URL not set"
  echo "     Fix: copy .env.example → .env.local and fill in local URLs"
  echo "  4. DB not seeded — run: pnpm db:seed:test"
  echo ""
  echo "Do NOT commit. Fix E2E failures, then re-run /dev-pipeline:validate."
  exit 1
fi

echo "✅ E2E passed"
```

**Never bypass E2E with a comment like "E2E can be added later" or "ran manually." It must be executed in-process with a logged exit code.**

---

## STEP 5: Build

```bash
if command -v pnpm &>/dev/null && grep -q '"build"' turbo.json 2>/dev/null; then
  pnpm turbo build --filter=...[HEAD^1]
else
  pnpm build 2>/dev/null || npm run build
fi
```

Fail on build errors. A build that passes types but fails bundling is still a blocker.

---

## STEP 5.5: Deployment-Build Parity (the context `turbo build` does NOT cover)

`pnpm turbo build` / `next build` is NOT the same as the PRODUCTION build contexts. A change can pass STEP 5 and still break the deploy because each context assembles the workspace differently (local symlinks vs Docker isolated COPY vs Vercel `buildCommand` vs the `node dist/main` runtime). **This step is MANDATORY when the diff touches any of:**

- a `Dockerfile` / container build,
- a `vercel.json` `buildCommand` / `next.config.js` / build config,
- a workspace-package dependency (added/removed/changed `package.json` deps, `main`/`exports`/`files`, or a new `import` of a `@scope/*` workspace package),
- anything under a `packages/*` that a deployed app consumes.

```bash
# 1. Enumerate deployable artifacts + their REAL build commands.
#    Don't assume `pnpm build` — read each app's vercel.json buildCommand
#    and every Dockerfile. They often differ (filters, deps-first, COPY scope).
grep -rl "buildCommand" apps/*/vercel.json 2>/dev/null
find . -maxdepth 3 -name "Dockerfile*" -not -path "*/node_modules/*"

# 2. Run each app's EXACT Vercel buildCommand (not `turbo build`):
#    e.g. cd <repo> && pnpm --filter=<app>... build   (note the deps-first `...`)

# 3. If a Dockerfile exists for a touched app, BUILD THE IMAGE — this is the
#    only faithful test of the isolated-COPY build context + the node runtime:
#    docker build -f apps/<app>/Dockerfile -t <app>-validate .
#    Then smoke the runtime require path that the image will execute, e.g.
#    docker run --rm --entrypoint sh <img> -c "node -e \"require('@scope/pkg')\""
```

### CI checks that DON'T run on PRs are YOUR job to run locally

Inspect the CI triggers. A job gated to `on: push: branches: [main]` (or any non-PR trigger) will **not** run on the PR — it runs for the FIRST time post-merge, on main. If your change affects such a job (e.g. the API Docker image build), **run it locally before merge.** A green PR that omits a main-only check is a blind merge.

```bash
grep -rn "on:\|branches:\|pull_request\|push:" .github/workflows/*.yml | head
# For each job your change touches: does it trigger on PRs? If NOT, reproduce it locally.
```

Fail this step if any production build context (container image, Vercel buildCommand, or a main-only CI build affected by the diff) was not actually executed and passing. "It builds with `turbo build`" is not sufficient evidence.

---

## STEP 6: Phase 8 Summary

Print a summary table. ALL rows must be ✅ to proceed:

```
╔══════════════════════════╦════════╗
║ Check                    ║ Status ║
╠══════════════════════════╬════════╣
║ Lint                     ║  ✅    ║
║ TypeScript               ║  ✅    ║
║ Unit tests               ║  ✅    ║
║ Mutation backstop        ║  ✅    ║  ← or [skipped — no assertion rewrite / repo not opted in]; <70% score = review finding, noted here
║ Browser E2E              ║  ✅    ║  ← or [skipped — no config] if not detected
║ Build                    ║  ✅    ║
║ Deploy-build parity      ║  ✅    ║  ← container/Vercel/main-only builds, or [n/a — no infra-touching change]
╚══════════════════════════╩════════╝
Phase 8 PASSED. Safe to proceed to commit + deliver.
```

If any row is ❌, print the specific failure and block. Do not print a partial pass summary.
