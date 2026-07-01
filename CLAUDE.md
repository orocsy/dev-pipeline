# dev-pipeline Plugin — Auto-Loading Instructions

This file auto-loads whenever the `dev-pipeline` plugin is enabled. It contains ALL pipeline-specific rules. The user-level `~/.claude/CLAUDE.md` deliberately stays thin; everything below is plugin territory.

If you are reading this, you MUST follow every rule here in addition to the user-level rules.

**What's new:** read [`CHANGELOG.md`](CHANGELOG.md) for recently-added skills, gates, and agents. New capabilities are easy to add and then forget exist — the changelog is the one place that lists them so they actually get used. Skim it at session start; anything added there is in force.

---

## AUTO-INVOCATION RULES (NON-NEGOTIABLE)

You are a self-running agent. You MUST invoke the correct pipeline flow automatically — the user should NEVER have to ask you to follow the pipeline. These rules fire on EVERY turn.

### Rule 1: Route EVERY code request to a pipeline command FIRST

Before writing ANY code, invoke the matching command from the workflow routing table below. Do NOT start coding inline. Do NOT "quickly fix" something without a flow. The pipeline IS how you work.

### Rule 2: Follow hook directives IMMEDIATELY

When a hook emits an AUTO-REVIEW DIRECTIVE or any other action directive, execute it IMMEDIATELY — before responding to the user. These directives are non-optional.

### Rule 3: Auto-detect phase transitions

After completing each MIU, check if ALL MIUs for the current product task are done. If yes:
1. Announce: "All MIUs complete. Proceeding to delivery gate."
2. Invoke `/dev-pipeline:deliver` automatically — do NOT wait for the user to ask.

After each commit, when the post-commit hook emits the AUTO-REVIEW DIRECTIVE:
1. Run the self-review (deep-reviewer + typescript-reviewer + security-reviewer) BEFORE your next response.
2. Do NOT skip this. Do NOT say "I'll review later." Do it NOW.

### Rule 4: NEVER merge or deliver without the delivery flow

- NEVER run `gh pr merge` directly. ALWAYS use `/dev-pipeline:deliver`.
- NEVER create a PR without first running self-review, E2E (if required), and env validation.
- NEVER improvise a delivery flow. The 10-step gated process in `/dev-pipeline:deliver` exists for a reason.
- If you find yourself about to run `gh pr merge` — STOP. Invoke `/dev-pipeline:deliver` instead.

### Rule 5: Auto-resume pipeline on session start

When `session-start.sh` reports an active pipeline (phase, task, MIU progress):
- If MIUs are in-progress → resume implementation at the current MIU.
- If all MIUs are complete but no PR exists → invoke `/dev-pipeline:deliver`.
- If a PR exists with review comments → invoke `/dev-pipeline:pr-review`.
- If `DEEP_REVIEW_REQUIRED` marker is present → run deep review immediately.

### Rule 6: E2E is mandatory for payment, auth, and multi-step flows

When the feature touches payment/billing, authentication/authorization, or multi-step user journeys:
- E2E tests MUST exist and MUST pass before delivery.
- If E2E tests don't exist, create them as part of an E2E MIU.
- NEVER skip E2E by saying "we can add this later" for these critical flows.

### Rule 7: Environment variables are a hard gate

Before any PR or merge:
- Check EVERY `process.env.X` in the diff against `.env.example`.
- If ANY env var is missing from `.env.example` → BLOCK. Do not proceed.
- Ask the user to confirm the var exists in CI and production environments.

### Rule 8: Pre-Push Review Gate (MANDATORY — NEVER RELY ON ASYNC REVIEW BOTS)

An async review bot posting comments on the PR is NOT a review step. It is a safety net that may be delayed, may be disconnected, or may miss race conditions and state bugs. It is never primary.

**Primary review happens BEFORE push, locally, via `/dev-pipeline:review`.**

Hard rules:
- Never run `git push` without first running `/dev-pipeline:review` in the same session on the current HEAD.
- `/dev-pipeline:review` must launch parallel reviewers (deep, typescript, security, test) AND, if installed, delegate to the `/code-review` 5-agent sweep from the `code-review` plugin.
- On PASS, the command writes `.claude/.last-reviewed-sha` with the current HEAD SHA — this is the "blessing".
- On any P1 finding or 4+ P2 findings, the command BLOCKS push, invokes `/dev-pipeline:fix`, and re-runs itself on the new HEAD.
- The pre-push git hook (installed by `~/.claude/setup-git-hooks.sh`) reads `.claude/.last-reviewed-sha` and refuses pushes whose HEAD does not match.
- Every new commit invalidates the blessing. Re-review before every push.

Integration with delivery:
- `/dev-pipeline:deliver` MUST invoke `/dev-pipeline:review` as Phase 8.5 (between verification and commit/push). If review blocks, deliver halts.
- If `/dev-pipeline:deliver` is invoked and the bless file is missing or stale, it auto-invokes `/dev-pipeline:review` first — no user prompt needed.

Override (incidents only):
- `REVIEWED=1 git push` bypasses the hook, logs to `.claude/.review-overrides.log`, and obligates you to run a retroactive review in the same session.

### Rule 9: Refactor is PROPOSE-ONLY — never silently rewrite working code

Refactoring touches code that already works. The bar is higher than bug fixes because the downside of a bad refactor is silent breakage of shipped behavior.

Hard rules:
- `/dev-pipeline:refactor` produces a **refactor proposal document**, not a diff. It lists findings grouped by severity (style / maintainability / performance / architecture) with concrete rewrite sketches.
- You NEVER apply a refactor without the user accepting specific proposals by ID.
- Accepted proposals are split into MIUs and run through the normal pipeline: plan → implement → review → test → deliver. No shortcuts.
- Architecture-level rewrites (changing boundaries, swapping a framework, restructuring data flow) are flagged separately with a "Requires Architectural Review" tag. They do NOT auto-route; the user must explicitly green-light each one.
- Scope limits: the orthodox refactor flow analyzes at most ONE module/domain per run. Whole-repo sweeps are a separate scheduled task.

Triggers (in order of preference):
1. **Manual** — user says "refactor X", "clean this up", "propose improvements".
2. **Post-delivery one-shot** — after a PR merges cleanly, `/dev-pipeline:deliver` MAY offer to run `/dev-pipeline:refactor` on the just-delivered module.
3. **Scheduled cloud routine** — a daily task (via the `schedule` skill) sweeps the repo and opens a refactor-proposal PR. The PR is never auto-merged; it waits for human triage.

Do NOT invoke the refactor flow opportunistically mid-feature. It belongs on clean `main`, not partway through implementation.

### Rule 10: Read project docs BEFORE writing code

Order of reads when starting work that touches deployment topology, runtime URLs, env-var contracts, or data-model invariants:

1. `README.md`
2. Project root `CLAUDE.md` (and `.claude/CLAUDE.md`)
3. `.claude/docs/ARCHITECTURE.md` and `.claude/docs/URL_TOPOLOGY.md` (if present)
4. `docs/architecture-*.md`, `docs/deployment-*.md`
5. THEN code (`vercel.json`, `next.config.js`, source)

**Readiness test:** can you state, in one sentence per app, what hostname + path each deployed app lives at, including any framework-level redirects? If not, you haven't read enough docs — re-read before writing.

Failure mode this prevents: assuming an "obvious" architecture by back-inferring from one config file. Long-form rationale: `docs/PHILOSOPHY.md §7`.

### Rule 11: Fix patterns, not enumerations

When a bug is reported, look for the GENERAL CLASS and fix at the class level. Do NOT add one-off rewrites / redirects for each specific failing input that surfaces.

- Anti-pattern: user reports "`/en/admin` shows a fake store" → add a redirect for `/admin`. Next week: "`/en/media` too" → add another redirect.
- Right pattern: root cause is the fallback that renders a fake tenant on any error. Drop the fallback. Every random slug now 404s, no per-slug fix needed.

**Test before declaring fixed:** "what other inputs would have triggered the same root cause, and does my fix cover them?" If you can't enumerate them, you fixed the symptom, not the bug. Long-form: `docs/PHILOSOPHY.md §8`.

### Rule 12: No file is "out of scope" inside the repo

Every file in the working repo is fixable — `next.config.js`, `vercel.json`, `Dockerfile`, CI workflows, `package.json`. If the right fix is one layer UP (config / build / framework / infra), edit that one, don't constrain yourself to "my page code".

Anti-framing to catch yourself: "X is still there because it's a [framework/platform]-level thing that's outside my page code." Reframe as: "X is configurable in `<file>`. Options are A, B, C. I recommend B because <reasons>."

Test: before declaring a fix complete, ask "is there a SIMPLER fix one level UP that I dismissed because it's not in my immediate code area?" Long-form: `docs/PHILOSOPHY.md §9`.

### Rule 13: Self-correct mid-process, not just at output

When an assumption is corrected (by the user, by a different agent, by your own re-reading), STOP and:
1. Acknowledge the correction explicitly.
2. Re-read the relevant docs to verify the corrected version.
3. List what work-already-done depended on the now-wrong assumption.
4. Redo that affected work in the SAME turn — do NOT continue forward on top of the corrected assumption.

The `assumption-checker` agent (see `agents/assumption-checker.md`) is the automatic version of this — it fires at every MIU boundary and pre-review. Manual self-correction kicks in BEFORE the agent has a chance to. Long-form: `docs/PHILOSOPHY.md §10`.

### Rule 14: Cross-check is a CONSTRAINT, not a manual gate

Every cross-check in dev-pipeline must be AUTOMATIC, not user-invoked:

- `/dev-pipeline:implement` invokes `assumption-checker` at every MIU boundary (between code and "mark MIU done").
- `/dev-pipeline:review` invokes `assumption-checker` FIRST in the parallel-reviewer set, before deep / typescript / security / test.
- Post-commit hook emits `AUTO-REVIEW DIRECTIVE` → Rule 2 acts on it.
- Pre-push hook requires fresh `.last-reviewed-sha` → Rule 8 enforces.

**Readiness test:** "Can the human user complete a feature ship without typing any `/dev-pipeline:*` command, and still get every gate fired?" If yes, automation is right. If no, find the missing trigger and wire it.

If any gate becomes opt-in instead of automatic, the workflow has decayed back to "human notices the drift if they happen to look". Long-form: `docs/PHILOSOPHY.md §11`.

### Rule 15: Raised PR ≠ shippable PR — conflict gate is mandatory

Immediately after `gh pr create`, `/dev-pipeline:deliver` MUST check the PR's mergeable state. A `CONFLICTING` PR is dead — no review automation (PR-comment bots, branch protection) fires on a PR that can't merge, and the PR sits in limbo until a human notices.

The flow:
1. `gh pr view <N> --json mergeable,mergeStateStatus` (poll briefly if `UNKNOWN`).
2. If `MERGEABLE` or `UNSTABLE` (CI still running) → proceed.
3. If `CONFLICTING` / `DIRTY` → `git fetch origin <base>`, `git rebase origin/<base>`, resolve hunk by hunk (read BOTH sides, prefer COMBINING when both sides add new functionality), re-run lint + tsc + tests, `git push --force-with-lease`, re-verify mergeable.
4. Only after PR is `MERGEABLE` → hand off to code-review / CI.

Spec lives in `commands/deliver.md → PHASE 9.5: Conflict Gate`. There is no override — a conflicting PR cannot proceed to review by definition, so skipping the gate doesn't unblock anything, it just delays discovery.

**Failure mode this prevents:** a real session opened a PR and started waiting for automated review. The PR had conflicts with main, so the reviewer never fired — the wait was for nothing. The user had to notice and prompt the agent to check. Building this into the pipeline means the agent never lets a conflicting PR sit idle. Long-form: `docs/PHILOSOPHY.md §11` (cross-check as constraint, applied to PR lifecycle).

### Rule 16: Frontend changes require E2E against the deploy preview

After code review passes and BEFORE merge, `/dev-pipeline:deliver` MUST run targeted Playwright E2E against the Vercel preview URL for any PR that touches frontend files. Unit tests can't observe SSR hydration, basePath redirects, footer placement under real browser rendering, or visual regressions that only manifest at runtime — and those are precisely the bugs that have shipped to prod despite green unit tests.

The flow:
1. `git diff --name-only origin/<base>..HEAD` → detect which apps' src/messages/public dirs changed (admin / booking / packages/ui).
2. Parse the vercel[bot] PR comment for preview URLs.
3. For each affected app: `PLAYWRIGHT_<APP>_URL=<preview> npx playwright test --project=<app>-chromium tests/e2e/<app>/`
4. **Block merge on failure.** No override — the cost is ~40s on an already-built preview, far less than one prod post-mortem.
5. Docs-only / config-only / backend-only PRs skip automatically (detection in Step 1).

Spec: `commands/deliver.md → PHASE 10.5: Browser E2E Gate`.

**What "like a user" means in these specs:** assertions use `page.getByRole`, `page.getByText`, real clicks, real navigation. Not `getByTestId` (which can pass even when the user-visible flow is broken — wrong heading, missing link, hidden CTA). Not `waitForLoadState('networkidle')` (Vercel previews include analytics scripts that never let the network truly idle — use per-assertion auto-wait instead).

**Failure mode this prevents:** a real session shipped OAuth-compliance pages whose unit tests were green but whose actual SSR behaviour (hydration mismatch, post-mount redirect) wasn't observable without a browser. Post-merge review caught the hydration issue — but it would have been caught earlier if E2E was a per-PR gate from the start. That session introduced E2E specs that verify the OAuth-reviewer journey end to end; this rule makes that kind of coverage a constraint for future frontend PRs, not a per-feature decision.

### Rule 17: Production smoke after every deploy

PHASE 12.5 of `/dev-pipeline:deliver` runs a **smoke-test subset** of Playwright specs against PRODUCTION URLs five minutes after deploy completes. Preview E2E (Rule 16 / PHASE 10.5) catches code-level regressions; production smoke catches **environment-level regressions** that only surface in prod (missing prod env var, CORS misconfig, CDN cache rule breaking dynamic routes, etc.).

The flow:
1. Wait 5 minutes for CDN propagation / DNS TTL / post-deploy migrations.
2. Resolve production URLs from `.claude/docs/URL_TOPOLOGY.md` (auto-captured by `/dev-pipeline:url-topology`).
3. Run a **narrow** spec subset (~5 specs, < 60s total) — NOT the full suite. Full suite runs against preview pre-merge; production smoke verifies the deploy is healthy, not exhaustive coverage.
4. On failure: alert with triage commands (`gh run view`, Vercel logs, rollback command). Code is already in production at this point — speed matters.

Spec: `commands/deliver.md → PHASE 12.5: Production Smoke Test`.

**Skill references for writing smoke specs:** `playwright-expert` (fullstack-dev-skills marketplace), `test-master` (fullstack-dev-skills), `verification` (vercel plugin). Listed in `deps.json → external.skills[]` so agents pick them up via the standard skill-router flow rather than reinventing Playwright patterns per-feature.

**Failure mode this prevents:** PR passes preview E2E, merges, deploys, breaks in production because of an env-config drift. Without this phase, first signal is a user report. With it, signal is in the deliver log within ~1 minute after deploy stabilises.

### Rule 18: Removing "dead code" requires proving what it guarded against

Before deleting any code path that handles a rare branch (fallback, retry, defensive null-check, special-case handler), do the following — in this order:

1. **Read the surrounding comments.** Load-bearing safety code usually has a doc-comment naming the failure mode it handles. If the comment says "would surface as 404s" — that IS the failure mode. Believe it.
2. **`git log -p -- <file>` the introduction.** Find the commit that added it. Read the commit message. The author wrote down what they were guarding against. If the message says "fallback for transient API outages" — the fallback is not SEO theatre, it's outage protection.
3. **Trace what the same caller does in OTHER branches.** If `error → fallback` and `not-found → notFound()`, those are two different failure modes; collapsing them is a semantic change, not a cleanup.
4. **Chaos test.** Simulate the upstream failure (mock the API as failing) and watch what the user sees. If the answer changes from "degraded page" to "404 page" after your removal, you've changed user-visible behaviour — that's not dead-code cleanup, that's a feature regression disguised as refactoring.
5. **Only then remove.** And update the test that exercises that branch — DON'T rewrite the test to assert the new behaviour as if it was always right. Add a new test for the new behaviour and leave the old one as a regression check (or explicitly delete it with a comment explaining why the old behaviour is no longer desired).

**Failure mode this prevents:** a real production outage. A booking tenant page had a `buildFallbackTenant()` helper that rendered a shell when `getTenant` returned `'error'`. A PR deleted it on the theory it was "SEO pollution on unknown slugs". But unknown slugs already 404'd via the `'not-found'` branch — the fallback only ever fired on `'error'` (SSR couldn't reach the API). Removing it converted every transient upstream failure (e.g. a bot-challenge on the SSR origin) into a permanent 404 for real customers. The comment in the layout literally said "cross-continent fetch failures / timeouts that surface as 404s because getTenant catches the error" — a load-bearing warning, deleted in the same PR.

Long-form + concrete walk-through: `docs/PHILOSOPHY.md §12`.

### Rule 19: Tests that change behaviour are NOT proof of correctness — they're proof of agreement with yourself

When changing a code path, do not rewrite the existing test to assert the new behaviour. That's tautology — your test will pass because you wrote it to pass. The test you trusted before the change should still pass after the change OR fail in a way that surfaces the semantic shift.

Three safer patterns:

1. **Add a new test for the new behaviour, leave the old test alone.** If the old test now fails, that failure is meaningful — it tells you the behaviour DID change in a user-visible way. Triage: was the old behaviour incorrect (delete the test with a comment) or are you about to break something (revisit the change)?
2. **Property-based / invariant test.** Frame the assertion at a higher level than the specific behaviour. e.g. "real tenant URLs do not return 404" — this stays true across both implementations.
3. **End-to-end against the deployed artefact.** Unit tests can be rewritten to anything; E2E against a real browser against a real deploy reflects what users see.

**Failure mode this prevents:** a page test asserted "renders fallback entity with ALL fields null when the fetch returns error". A change rewrote it to "calls notFound when the fetch returns error (no fallback)". Both versions passed locally — but they were asserting OPPOSITE behaviours. The rewrite gave false confidence in the change.

Long-form: `docs/PHILOSOPHY.md §13`.

### Rule 20: Verify against PRODUCTION URLs, not preview URLs, before declaring a deploy successful

Preview deploys differ from production in subtle but consequential ways:

- Different env-var scopes (Preview vs Production scope in Vercel — easy to misconfigure ONE without the other)
- Different upstream credentials (preview hits staging DB / sandbox Stripe; production hits real DB / live Stripe)
- Different CDN cache config (preview is "no-cache by default"; production caches aggressively)
- Different domain (preview is `*.vercel.app`; production is your real domain — CORS allow-lists may exclude one)
- Different IP egress reputation at the CDN layer

A green preview E2E plus green production smoke is the minimum bar. Preview alone is not a smoke check; it's a build check.

PHASE 12.5 (Rule 17) already encodes this. Rule 20 names it explicitly so it can't be quietly skipped: "I tested it on preview and it worked" is not the same statement as "I tested it on production and it worked".

Long-form: `docs/PHILOSOPHY.md §13` (combined with Rule 19 — same root cause).

### Rule 21: Co-Review is OPT-IN — never auto-invoke it

`/dev-pipeline:co-review` relays review between Claude and another agent (Codex) across multiple sources (GitHub PR bots, shared design docs) and manages the turn-taking. It is a **deliberately optional** flow: it is NOT part of the default `plan→implement→review→deliver` pipeline and MUST NOT be wired into Rule 1 (route every request) or Rule 5 (auto-resume). It activates only when (a) the user runs it, or (b) the user opts in per-project via `touch .claude/co-review/enabled`, which surfaces a `CO-REVIEW PENDING` nudge at session start (a suggestion, not an auto-run).

Hard rules:
- Detection is ALWAYS cursor-gated (timestamp for PR bots, doc commit SHA for docs). Re-anchored/re-flagged old items are NOT new — never re-process them (this is the fix for the runaway-relay failure below).
- In `--watch` mode the **convergence safeguard is mandatory**: auto-STOP and hand back to the user on round-cap, stall (≥ threshold findings again), a resolved/false-positive finding reappearing, or findings trending up. Confirmed false positives go to a suppression ledger. Never loop indefinitely.
- Turn-taking is a cooperative lock: write only when it's your turn, flip + commit to hand off, and NEVER force-push a co-review doc (last-writer reconciles).

**Failure mode this prevents:** a real session ran 7 manual `@codex review` rounds that never converged to zero — the bot re-flagged already-fixed lines (e.g. `os.getenv` already covered by an existing pattern) and a fix introduced a fresh regression each round. Cursor-gating + the convergence safeguard turn that unbounded manual loop into a bounded, auto-stopping relay. See `commands/co-review.md` and `agents/co-review-adapter.md`.

---

## MANDATORY WORKFLOW ROUTING

Every code change routes to a named flow. There is no inline coding without a pipeline.

| User Request Pattern | Task Type | Flow |
|---|---|---|
| "Add/Build/Create/Implement [new]" | NEW_FEATURE | `/dev-pipeline:pipeline` |
| "Improve/Update/Enhance [existing]" | ENHANCEMENT | `/dev-pipeline:update` |
| "Refactor/Clean up [X]" | REFACTOR | `/dev-pipeline:pipeline` (skip design phases) |
| "Fix [bug]", "[error message]" | BUG_FIX_SIMPLE | `/dev-pipeline:fix` |
| "Debug [intermittent issue]" | BUG_FIX_COMPLEX | `/dev-pipeline:pipeline` |
| "Address review", "PR feedback" | PR_REVIEW_FIX | `/dev-pipeline:pr-review` |
| "Production down", "Hotfix" | HOTFIX | `/dev-pipeline:hotfix` |
| "Add tests to existing code" | ADD_TESTS | `/dev-pipeline:pipeline` (skip design + architecture) |
| "New project from scratch" / "Scaffold from PRD" | NEW_PROJECT | `/dev-pipeline:scaffold-from-prd` (uses spec-forge) |
| "Initialise existing repo" | INIT_EXISTING | `/dev-pipeline:init` then `/dev-pipeline:pipeline` |
| "Upgrade dependency X" | DEPENDENCY_UPDATE | `/dev-pipeline:update` |
| "Performance investigation" | PERFORMANCE | `/dev-pipeline:perf` then `/dev-pipeline:pipeline` if fixes needed |
| "Refactor/Clean up/Simplify/Modernize" | REFACTOR_PROPOSAL | `/dev-pipeline:refactor` (propose-only, never auto-apply) |
| Anything unclassified | BUG_FIX_SIMPLE | `/dev-pipeline:fix` (safe default) |

**Guarantees for every flow:**
1. Spec before code — understand before implementing
2. Test proof — tests validate the change
3. Deliberate commit — clean message, never `--no-verify`
4. No silent skips — every phase runs or is explicitly skipped with justification

**If the user's request doesn't trigger a pipeline command** (e.g. they're just chatting and say "can you fix that?"), you still internally follow the correct flow. The flow is the standard, not the command.

---

## DECOUPLED SIBLING TOOLS

### spec-forge (optional)

dev-pipeline references but does NOT depend on `spec-forge`, an open-source scaffolder for new-project bootstrap. They communicate only via `spec.json` files + the `spec-forge` CLI.

| Tool | Purpose | Where it lives |
|---|---|---|
| **dev-pipeline** (this plugin) | Methodology + commands for everyday feature work in EXISTING projects | `~/.claude/plugins/marketplaces/local/plugins/dev-pipeline/` |
| **spec-forge** | Scaffold a NEW project from a JSON spec | `~/Desktop/projects/spec-forge/` (override via `SPEC_FORGE_DIR`) |

The decoupling means:
- spec-forge can ship its own version cadence
- dev-pipeline stays valid for users who never need scaffolding
- A scaffolded project can be operated by dev-pipeline once it exists, without spec-forge present

`/dev-pipeline:scaffold-from-prd` is the only command that bridges the two. If `SPEC_FORGE_DIR` isn't set or doesn't exist, that command fails fast with a clear error pointing to install instructions.

---

## HOW AUTO-ROUTING ACTUALLY WORKS

The user does NOT need to type a slash command. You route automatically.

**Mechanism (runs on every user turn that involves code):**

1. **Parse the request** for intent keywords against the routing table above.
2. **Classify** into one of: NEW_FEATURE, ENHANCEMENT, REFACTOR, BUG_FIX_SIMPLE, BUG_FIX_COMPLEX, PR_REVIEW_FIX, HOTFIX, ADD_TESTS, NEW_PROJECT, DEPENDENCY_UPDATE, PERFORMANCE, REFACTOR_PROPOSAL.
3. **Announce the routing** in one line: *"Classified as BUG_FIX_SIMPLE → invoking `/dev-pipeline:fix`."*
4. **Invoke the command** before writing any code.

**Concrete examples:**

| User says | Classification | Auto-invoked |
|---|---|---|
| "fix the login bug" | BUG_FIX_SIMPLE | `/dev-pipeline:fix` |
| "the auth endpoint returns 500 intermittently" | BUG_FIX_COMPLEX | `/dev-pipeline:pipeline` |
| "add a dark mode toggle" | NEW_FEATURE | `/dev-pipeline:pipeline` |
| "the dashboard feels slow" | PERFORMANCE | `/dev-pipeline:perf` |
| "address the review comments" | PR_REVIEW_FIX | `/dev-pipeline:pr-review` |
| "ship it" / "merge" / "open PR" | DELIVERY | `/dev-pipeline:deliver` |
| "clean this file up" / "make this more idiomatic" | REFACTOR_PROPOSAL | `/dev-pipeline:refactor` (propose-only) |
| "production is down" | HOTFIX | `/dev-pipeline:hotfix` |

If the request is ambiguous, ask ONE classification question, then proceed. Never silently fall through to ad-hoc coding.

---

## TOOLBELT vs WORKFLOW — dev-pipeline AND gstack

`dev-pipeline` owns **workflow orchestration**: phases, gates, reviews, delivery, MIU decomposition, git hook enforcement. It is the process.

`gstack` (if installed) is a **toolbelt**: browser automation, persistent memory (gbrain), web research, screenshot capture, and other capability MCPs. It is not a workflow.

**Rules:**
- Always route through `dev-pipeline` for the flow. It is the default.
- Use `gstack` tools *inside* a pipeline phase whenever they help — you do NOT need the user to say "use gstack". Examples:
  - Phase 1 (requirements): use gstack memory to recall prior decisions on this project.
  - Phase 2 (research): use gstack browser to read third-party API docs or reproduce a UI issue.
  - Phase 7 (implement): use gstack memory to avoid re-learning the same codebase convention.
  - Phase 10 (deliver): use gstack browser to verify the deployed URL renders correctly.
- `gstack` NEVER replaces pipeline gates. A gstack-driven research pass still reports back into the current MIU, still goes through review, still requires a blessed SHA before push.
- If a gstack tool and a pipeline phase disagree, the pipeline wins.

In short: pipeline is *how* you work, gstack is *what* you reach for while working. Both are on by default.

---

## PIPELINE GATE ENFORCEMENT (NON-NEGOTIABLE)

You MUST stop and request explicit user approval at these moments — no exceptions:

| Gate | Trigger | What to say |
|------|---------|-------------|
| G1 | After Phase 1 (requirements) | "✅ G1: Requirements ready. Questions resolved? [Y to continue]" |
| G2 | After Phase 3 (design check) | "✅ G2: Design reviewed. Approve to continue to architecture? [Y]" |
| G3 | After Phase 4 (architecture + MIU spec) | "✅ G3: Architecture ready. **APPROVE ARCHITECTURE** — I will not write code until you confirm." |
| G4 | After Phase 6 (test plan) | "✅ G4: Plan + test scenarios ready. **FINAL APPROVAL** — after this I run autonomously to production." |

After G4 approval: execute Phases 7–12 without further approval requests.
All file ops, git, CI, and deploy are pre-approved in `settings.json`.

---

## Living Documents — The Project Brain (READ FIRST, ALWAYS)

Three documents in `.claude/docs/` are the **single source of truth** for project knowledge. Every agent MUST read them before doing any work. They replace codebase exploration.

| Document | What it answers | Read when |
|----------|----------------|-----------|
| `PROJECT_STATUS.md` | What's happening now? Branch, task, MIU progress, blockers | Every turn |
| `ARCHITECTURE.md` | How is the system built? Stack, structure, integrations, env vars | Start of new feature, delivery, review |
| `RECENT_CHANGES.md` | What changed recently? Last ~20 changes with files and context | Before any code change, to understand recent state |

### Rules for Living Documents

1. **Read before explore.** If the answer is in the docs, do NOT grep the codebase. The docs are faster and more complete.
2. **Trust but verify.** Docs have timestamps. If a doc is >1 day old or the timestamp doesn't match HEAD, run `/dev-pipeline:sync` first.
3. **Update after every meaningful change.** After committing, delegate to the project-sync agent. This is automatic via post-commit hook — but if you're doing work outside the normal commit flow, run sync manually.
4. **Never let docs go stale.** Before compaction, before delivery, at session start — sync is mandatory. A stale doc is worse than no doc.
5. **If docs don't exist:** Run `/dev-pipeline:sync init` immediately. This is the first thing you do in any project that doesn't have `.claude/docs/`.

### Agent Events Log

`.claude/agent-events.jsonl` records meaningful state transitions. Check it when:
- Starting work (what happened since your last run?)
- Before delivery (are all agents' work reflected?)
- After compaction (what did previous context do?)

---

## MIU System Reference

MIU (Minimum Implementable Unit) is the work-decomposition unit this plugin enforces. The FULL specification, granularity examples, mandatory output format, and quality gate checklist live in:

**`skills/miu-methodology/SKILL.md`**

That skill auto-loads whenever decomposition work is underway. Do NOT reimplement MIU rules here — delegate to the skill.

Quick reminders:
- Two-level decomposition: Level 1 (Product Task) → Level 2 (Technical MIU). Never confuse.
- Every Technical MIU output MUST include the 8-field format from the skill.
- If an MIU description fits in one line, it's not detailed enough — go deeper.

---

## Smart Project Detection

Project detection logic (runs at Phase 0 of every flow, also at `/dev-pipeline:init`) lives in:

**`skills/project-detector/SKILL.md`**

Do not ask the user for the project type — detect it from `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, etc. The skill also captures deploy intent from Phase 1 keywords and creates matching MIUs for config-file scaffolding (`vercel.json`, `supabase/config.toml`, etc.).

---

## Smart Skill Selection

Agents auto-select skills using the routing rules in:

**`skills/skill-router/SKILL.md`**

Covers:
- Design phase selection (Stitch MCP → Figma MCP → image → ui-ux-pro-max → design-checker → skip)
- Tech-stack skill selection (next → vercel-react + vercel-composition, nestjs → nestjs-best-practices, etc.)
- Deploy adapter selection (vercel.json → Vercel adapter, supabase/ → Supabase adapter, fly.toml → Fly adapter, etc.)

Never ask the user which skill to use. The router decides.

---

## Session Continuity

- `session-start.sh` loads project context, pipeline state, instincts, and context bridge
- `pre-compact.sh` saves state before context window compression
- `session-stop.sh` saves audit trail and detects documentation gaps
- Pipeline state persists in `.claude/pipeline-state.json`
- MIU progress persists in `.claude/miu-progress.json`
- Learned patterns persist in `.claude/instincts/`
- Agent events persist in `.claude/agent-events.jsonl`

---

## Auto-Invocation Decision Tree (check EVERY turn)

```
START OF TURN:
│
├─ Is there an AUTO-REVIEW DIRECTIVE in the hook output?
│  └─ YES → Run self-review NOW (deep-reviewer + typescript-reviewer + security-reviewer)
│           → Bless HEAD when clean → THEN handle user's request
│
├─ Is DEEP_REVIEW_REQUIRED marker present?
│  └─ YES → Run deep review NOW → Clear marker → THEN handle user's request
│
├─ Is there an active pipeline with in-progress MIUs?
│  └─ YES → Continue implementing the current MIU (don't start a new flow)
│
├─ Are ALL MIUs for the current task complete?
│  └─ YES → Has delivery been done?
│           ├─ NO PR exists → Invoke /dev-pipeline:deliver
│           ├─ PR exists, no reviews → Wait or check CI
│           └─ PR has review comments → Invoke /dev-pipeline:pr-review
│
├─ Is the user requesting a code change?
│  └─ YES → Classify (new feature / enhancement / bug fix / hotfix / PR review)
│           → Invoke the matching /dev-pipeline:* command from routing table
│           → Do NOT write code outside a pipeline flow
│
└─ Is the user asking a question / non-code task?
   └─ YES → Respond normally (no pipeline needed)
```

### Delivery Flow Auto-Trigger Conditions

`/dev-pipeline:deliver` MUST be invoked (not improvised) when ANY of these are true:
- All MIUs are marked complete in `.claude/miu-progress.json`
- User says "ship it", "merge", "deploy", "deliver", "open PR", "create PR"
- User asks to push to main/master
- Implementation phase is done and user asks "what's next?"

### Commands That Are ALWAYS Wrong to Run Directly

These commands must NEVER be run outside the delivery flow:
- `gh pr merge` → use `/dev-pipeline:deliver` Step 9
- `gh pr create` without prior `/dev-pipeline:review` → review first
- `git push` without blessed HEAD → blocked by pre-push hook
- Any ad-hoc "let me just push this" → ALWAYS run `/dev-pipeline:review` first

### Review Gate Decision Tree (add to every turn that involves push)

```
About to push or deliver?
│
├─ Does .claude/.last-reviewed-sha exist?
│  └─ NO → Invoke /dev-pipeline:review FIRST. Do not push.
│
├─ Does .claude/.last-reviewed-sha == git rev-parse HEAD?
│  └─ NO (stale) → Invoke /dev-pipeline:review on current HEAD. Do not push.
│
└─ YES, SHA matches → Push allowed. Pre-push hook will confirm.
```

---

## Emergency Override

For true incidents where there's no time for self-review:

```bash
REVIEWED=1 git push origin main
```

(Legacy env vars `DEV_PIPELINE_SKIP_REVIEW=1` and `DEV_PIPELINE_SKIP_DEEP_REVIEW=1` are also honoured.)

Every override is logged to `.claude/.review-overrides.log` with timestamp, SHA, branch, and user. After an override, run `/dev-pipeline:review` retroactively in the same session. Do not leave overrides unreviewed.
