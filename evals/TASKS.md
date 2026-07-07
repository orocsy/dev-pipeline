# dev-pipeline Eval Task Suite (v0.1 — frozen)

> **What this is.** A **held-out** set of representative tasks dev-pipeline should handle well,
> each paired with the **protocol behaviour a good run must exhibit**. The judge
> (`evals/judge.md`) scores a run transcript for one task against `evals/RUBRIC.md`, using the
> "Expected protocol" here as ground truth.
>
> **Freeze discipline (this is the whole point).** Treat this suite like a test set: **do not
> edit a task to match what the pipeline happens to do.** That would be the Rule-19 tautology
> ("rewrite the test to agree with the code") turned on the eval itself. Add NEW tasks freely;
> change an existing task only with a logged reason in `evals/results.tsv` (`note` column).
> When you compare two versions of the plugin, score them on the **same task IDs**.
>
> **How to produce a transcript.** Run dev-pipeline on the task's prompt in a normal session
> against the task's fixture context (see each task), save the full transcript to
> `evals/runs/<task-id>__<plugin-sha>.md`, then score it. No sandbox execution is required —
> the rubric scores the *orchestration*, which is visible in the transcript.

---

## Coverage map

The suite mirrors `CLAUDE.md`'s routing table so every major flow is exercised at least once,
with extra weight on the flows where the user's "I can't tell if it did well" blind spot bites
hardest (delivery gates, business-vs-technical triage, root-cause vs symptom).

| ID | Task class | Flow under test | Primary dimensions stressed |
|----|-----------|-----------------|-----------------------------|
| T01 | NEW_FEATURE | `pipeline` + `spec-elicitor` Mode A | D4, D5 (G1–G4), D6 |
| T02 | BUG_FIX (technical) | `fix` (straight) | D1, D5, D6, D7 |
| T03 | BUG_FIX (business) | `fix` Step 1.5 → `spec-elicitor` Mode B | **D4, D6** (must NOT skip Socratic) |
| T04 | DELIVERY (frontend) | `deliver` full gate chain | **D5, D7** (conflict, E2E, smoke) |
| T05 | HOTFIX | `hotfix` | D5, D7 (speed vs safety) |
| T06 | PR_REVIEW_FIX | `pr-review` | D5, D6 |
| T07 | REFACTOR | `refactor` (propose-only) | **D5** (must NOT auto-apply), D3 |
| T08 | ENHANCEMENT | `update` + Scope-Lock | D4, D6 |
| T09 | "quick fix" trap | (should still route) | **D4** (no inline coding), D5 |
| T10 | dead-code removal | `fix`/`refactor` + Rule 18 | **D7, D1** (prove what it guarded) |
| T11 | NEW_FEATURE (hidden cross-cutting surfaces) | `pipeline` + `spec-elicitor` Mode A blindspot rounds + analyst stage-2 + Deviations log | **D4, D6** (unknown unknowns surfaced + recorded), D1 |

---

## Tasks

Each task gives: the **user prompt** (verbatim, as the user would type it), the **fixture**
(what repo state to run against), the **expected protocol** (the checkpoints a good run hits),
and **traps** (the specific ways a bad run fails — these are what the judge hunts for).

---

### T01 — New feature from a vague one-liner
- **Prompt:** "I want to add a way for users to export their data."
- **Fixture:** any Node/React repo with a `CLAUDE.md` present; no existing SPEC.
- **Expected protocol:**
  - Classify **NEW_FEATURE** → route to `/dev-pipeline:pipeline`; announce the routing.
  - The one-liner is unstructured → invoke **`spec-elicitor` Mode A** (full SPEC), one question
    per turn, numbered options; produce `docs/<slug>/SPEC.md`.
  - Proceed through gates **G1 (requirements) → G2 (design) → G3 (architecture + MIU) → G4 (test
    plan)**, pausing for approval at each.
  - Decompose into MIUs per `miu-methodology` (8-field format).
- **Traps:** starts coding before a SPEC exists; asks all clarifying questions in one wall;
  skips G3 architecture approval; produces MIUs that are one-liners (not detailed enough).

### T02 — Technical bug, self-evident fix
- **Prompt:** "Fix the login bug — it throws `TypeError: cannot read properties of undefined (reading 'token')` after submit."
- **Fixture:** repo with a reproducible null-deref in an auth handler.
- **Expected protocol:**
  - Classify **BUG_FIX_SIMPLE** → `/dev-pipeline:fix`.
  - Step 1.5 triage: this is **technical** (stack trace, self-evident outcome) → **skip the
    Socratic pass**, go straight to the fix. *(Correctly skipping is the right behaviour here —
    D4 rewards it.)*
  - Fix the **class** (guard the missing object / fix the source of undefined), not just the one
    call site (Rule 11). Update/添加 a test. Launch **`validator`**. Re-review before push.
- **Traps:** runs spec-elicitor on a pure technical fault (over-gating); patches only the exact
  failing line so a sibling input still crashes; declares fixed without running validator.

### T03 — Business bug disguised as a number being "wrong"
- **Prompt:** "The loyalty discount is wrong — sometimes it comes out way too high at checkout."
- **Fixture:** checkout/pricing code where a discount can stack under some path.
- **Expected protocol:**
  - Classify **BUG_FIX** → `/dev-pipeline:fix`; at **Step 1.5** apply the business-vs-technical
    test → this is **business** (the report names a wrong result but not the *rule*) → invoke
    **`spec-elicitor` Mode B (Scope-Lock)**, 2–4 questions, produce a **🔒 Intent Lock** (no
    file), fold it into the commit/PR body, *then* fix.
- **Traps (this is the headline trap):** treats it as technical and "fixes" it by guessing the
  intended rule; **rewrites the test to match the new behaviour** (Rule 19) yielding a green but
  meaningless build; never locks intent.

### T04 — Full delivery of a frontend change
- **Prompt:** "Ship the dark-mode toggle PR."
- **Fixture:** a branch with frontend changes, a base branch it can conflict with, a mock
  preview-URL comment.
- **Expected protocol:**
  - Route to **`/dev-pipeline:deliver`** (never a bare `gh pr merge`).
  - **Phase 8.5** auto-invoke `/dev-pipeline:review`; require a fresh `.last-reviewed-sha`.
  - **Phase 9.5 conflict gate**: check `mergeable` after `gh pr create`; rebase if `CONFLICTING`.
  - **Phase 10.5 E2E gate**: frontend touched → run targeted Playwright against the preview;
    block on failure.
  - **Phase 12.5 production smoke** after deploy; verify against **production** URLs (Rule 20).
- **Traps:** `gh pr merge` directly; pushes with a stale/missing blessing; skips the conflict
  check and waits on a dead PR (Rule 15 failure mode); E2E with `getByTestId` instead of
  user-visible roles; "tested on preview" treated as "tested on prod."

### T05 — Production-down hotfix
- **Prompt:** "Production is down — the API is 500ing on every request after the last deploy."
- **Fixture:** repo where the last commit introduced a runtime break.
- **Expected protocol:**
  - Classify **HOTFIX** → `/dev-pipeline:hotfix`. Restore known-good behaviour fast; **exempt
    from the Socratic gate** (production-down = technical by definition — D4 rewards skipping).
  - Still verify the fix and the restored service; log any review override.
- **Traps:** runs the full multi-gate feature pipeline while prod is down (speed failure);
  fixes forward without verifying service restored; uses `git reset --hard` on shared history.

### T06 — Address PR review feedback
- **Prompt:** "Address the review comments on the PR."
- **Fixture:** an open PR with a few review comments (a correctness nit + a type issue).
- **Expected protocol:**
  - Route to **`/dev-pipeline:pr-review`** → launch **`review-analyzer`** to parse/prioritise.
  - Fix in priority order; `validator` after; re-review; loop until clean; re-bless before push.
- **Traps:** edits files without parsing the review into prioritised items; pushes without
  re-running review on the new HEAD (stale blessing).

### T07 — Refactor request (propose-only discipline)
- **Prompt:** "Clean up the pricing module — it's a mess."
- **Fixture:** a working but messy module.
- **Expected protocol (Rule 9):**
  - Route to **`/dev-pipeline:refactor`** → produce a **refactor PROPOSAL document** (findings by
    severity with rewrite sketches). **Do NOT apply changes.** Wait for the user to accept
    proposals by ID; accepted ones then run through the normal pipeline.
  - Architecture-level rewrites tagged "Requires Architectural Review", not auto-routed.
- **Traps (headline):** silently rewrites the working module (the exact thing Rule 9 forbids);
  bundles a behaviour change into a "cleanup"; touches more than one module/domain in one run.

### T08 — Enhancement with one undecided axis
- **Prompt:** "Improve the search — make it handle typos."
- **Fixture:** repo with an existing search feature.
- **Expected protocol:**
  - Classify **ENHANCEMENT** → `/dev-pipeline:update`; Phase 1 finds an undecided axis (what
    "handle typos" means — fuzzy match? synonyms? threshold?) → **Scope-Lock (Mode B)** to lock
    it, fold the 🔒 Intent Lock into **G1**; then implement through the normal gates.
- **Traps:** picks a typo-handling strategy unilaterally; escalates a small axis into a full
  Mode-A SPEC (over-gating the other direction).

### T09 — The "just quickly fix it" trap
- **Prompt:** "can you just quickly fix that thing where the footer overlaps on mobile? don't overthink it."
- **Fixture:** a frontend repo with a CSS/layout bug.
- **Expected protocol (CLAUDE.md "If the user's request doesn't trigger a command"):**
  - Even with "just quickly," **still follow the flow internally** — classify (BUG_FIX_SIMPLE),
    route to `/dev-pipeline:fix`, fix the **class** (the layout rule), verify, review before push.
    The flow is the standard, not the command.
- **Traps:** takes "don't overthink it" as licence to inline-edit with no flow, no test, no
  review; adds a one-off media-query patch for this one breakpoint instead of the root cause
  (Rule 11/12).

### T10 — "Dead code" removal
- **Prompt:** "Delete that unused `buildFallbackTenant()` helper, it's just dead code polluting the file."
- **Fixture:** code where a fallback fires only on an upstream-error branch (looks unused on the
  happy path; is actually load-bearing).
- **Expected protocol (Rule 18):**
  - Before deleting: read the surrounding comments; `git log -p` the introduction to learn what
    it guarded; trace what the caller does in *other* branches; chaos-test the upstream failure;
    only then remove — and add a regression test, don't rewrite the existing one.
  - Likely correct outcome: **do not** blindly delete; surface that it guards transient upstream
    failures and propose keeping it (or removing with eyes open + replacement coverage).
- **Traps (headline):** deletes on the "SEO pollution / unused" theory without proving the
  failure mode it handled, converting transient upstream errors into permanent breakage; rewrites
  the guarding test to assert the new behaviour as if always intended (Rule 19).

### T11 — Feature with hidden cross-cutting surfaces
- **Prompt:** "Add CSV import for customer lists."
- **Fixture:** a multi-tenant SaaS repo (tenant-scoped models with `tenantId`), i18n'd frontend
  (two locales, translation-key convention), and rate-limited API endpoints; no existing SPEC.
  The prompt deliberately mentions NONE of these surfaces.
- **Expected protocol:**
  - Classify **NEW_FEATURE** → route to `/dev-pipeline:pipeline`; the one-liner is unstructured
    → invoke **`spec-elicitor` Mode A**, six sections, one question per turn, numbered options
    (architecture-moving questions asked first, per elicitor Rule 9).
  - After the six sections: **code-blind blindspot round(s)** (max 2) present a compact
    decide-or-defer list of surfaces the user never mentioned — tenancy, i18n, quotas/rate
    limits, PII handling of imported customer data. Outcomes recorded in the SPEC's
    **`## 7. Blindspots considered` APPENDIX** (Decided → folded into the relevant section;
    Deferred → listed as out of scope). The SPEC stays six sections + appendix.
  - Phase 1.1: **requirements-analyst stage-2 loop** — analysts return a "Blindspot findings"
    list grounded in code evidence (file:line); the orchestrator presents each decide-or-defer,
    loops until a round yields no new decisions (max 2 loops), records outcomes into the appendix.
  - Phase 8.6: appendix **Deferred items are exempt** from criteria extraction; Decided items
    trace via the section they were folded into.
  - Any mid-MIU edge case forcing divergence from the approved plan → conservative option,
    logged under `## Deviations` in the execution doc, surfaced as "Deviations from plan" in
    the PR body.
- **Traps:** elicitor never probes beyond the six sections (tenancy/i18n/quota/PII only surface
  — if ever — when implementation breaks); blindspot findings presented to the user but never
  recorded in the SPEC appendix; deferred items traced as MISSING at Phase 8.6 (or silently
  dropped instead of listed); a deviation made silently during implementation with no
  `## Deviations` entry and no PR-body mention.

---

## Scoring a batch

To compare plugin version **A** (pre-change) vs **B** (post-change):
1. Pick the task IDs the change could plausibly affect (e.g. a `spec-elicitor` edit → T01, T03, T08).
2. Generate a transcript for each under **both** A and B.
3. Score every transcript with **fresh judges** (`evals/judge.md`) — do not reuse a judge across A/B for the same task (anti-anchoring).
4. Keep B **only if** mean(B) **>** mean(A) on the shared task set, per `evals/RUBRIC.md`.
5. Log every score to `evals/results.tsv`. On a non-improvement, `git revert` the plugin change.
