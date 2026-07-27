# dev-pipeline — Changelog

Notable additions to the pipeline (skills, gates, agents, commands). Newest first.
This is the discoverability layer: when something is added to the pipeline, it gets a
line here so agents and humans know it exists and actually use it. Referenced from
`CLAUDE.md` ("What's new").

Conventions:
- One entry per notable capability. Link the file that owns it.
- Say what it does, where it fires, and why it matters — in one or two lines.
- Keep it project-agnostic (no project names / PR numbers — lessons are general).

---

## 2026-07-24 — Worktree reclaim on session start

- **`hooks/worktree-reclaim.sh`** (SessionStart). Agent worktrees under
  `.claude/worktrees/` silently accumulate gigabytes (node_modules and all) when
  sessions crash or end without cleanup — invisible to Finder, missed by
  post-merge-only hooks. Each session start now sweeps them: a worktree is
  auto-deleted ONLY when its PR is merged AND the tree is pristine AND the local
  tip equals the merged PR's headRefOid (squash-proof) AND the path physically
  resolves inside `.claude/worktrees/`. Anything else — dirty trees, post-merge
  commits, external checkouts, gh unavailable — is reported, never deleted. The
  `rm` runs behind a guard that refuses symlinks, out-of-prefix paths, `/`,
  `$HOME`, repo roots, and any still-registered worktree; data removal is
  backgrounded to respect the 15s hook budget. Matrix:
  `tools/test-worktree-reclaim.sh` (8 cells, incl. guard unit tests on the
  verbatim-extracted function).
- **Deliver Phase 9.6 — Codex review loop** (`commands/deliver.md`). After the
  conflict gate, a project that opted in (`touch .claude/codex-review-loop`) runs the
  STANDARD bot-review loop inline: trigger → wait → triage (re-flag ledger) → fix →
  validate → bless → push → re-trigger, with convergence guards (round cap,
  trending-up stall). The marker is the standing consent for posting `@codex review`:
  present → loop runs without asking, absent → silently skipped. Ends the per-session
  ask-again inconsistency. Deliberately NOT routed through `/dev-pipeline:co-review` —
  that stays the OPTIONAL multi-source relay protected by Rule 21.

## 2026-07-23 — Uniqueness rule for the business-vs-technical gate

- **The uniqueness rule** (`commands/fix.md` Step 1.5, `skills/spec-elicitor/SKILL.md` →
  "When to run me"): a finding only counts as "technical" if there is a UNIQUE correct
  outcome. When two or more defensible resolutions exist — even ones that all look purely
  technical (a reviewer's "do X or Y", a gate-semantics change, an either-way API shape) —
  it is a DECISION, so run a micro-Scope-Lock (one question, the options, your
  recommendation first) instead of silently picking. Closes the gate's known failure mode:
  each resolution looks defensible in isolation, so decision-carrying findings get misfiled
  as technical and made by default. The classifier must test uniqueness, not appearance.

## 2026-07-22 — Phase 3 becomes an EXECUTED UI-design phase (no more pause-and-ask)

The old Phase 3 told the user "run /ui-ux-pro-max + /web-design-guidelines, then come
back" — skills that weren't installed, guaranteeing a stalled pipeline on every UI
feature. Phase 3 now runs the design work itself.

- **Executed design flow** (`commands/dev-pipeline.md` PHASE 3, mirrored in
  `commands/plan.md`): design-checker gate → ensure a root `DESIGN.md` design
  foundation (create if missing) → generate `docs/<slug>/ui-design.md` via the first
  available of provided-asset → `ui-ux-pro-max` → `frontend-design` (installed
  default) → audit (`web-design-guidelines` if installed, else its checklist areas
  inline) → **G2** user approval gate. Phase 8.2 (verify-visual) compares shipped
  pixels against the approved spec.
- **deps.json**: `ui-ux-pro-max` and `web-design-guidelines` registered as optional
  externals with install commands + fallbacks (research-verified sources); the
  previous "frontend-design supersedes both" note corrected — they compose (spec
  database / audit rules / aesthetic direction are different layers).
- **agents/design-checker.md**: verdict output now reports which design skills are
  installed and hands next steps to the PIPELINE, never to the user.
- **Gating clarified** (`commands/dev-pipeline.md` PHASE 3.1): non-UI work
  (backend/config/tooling/pure-logic) skips 3.2–3.5 entirely — the executed design
  flow is UI-features-only, never a toll on every run.
- **Frontend review triggers** (`commands/review.md` STEP 1.5): trigger greps now
  cover `frontend-design-system-drift` (Tailwind token/className diffs),
  `frontend-async-state` (useEffect/promise diffs), and `accessibility-state-sync`
  (role/aria diffs) — previously all triggers were backend-shaped, so pure-frontend
  diffs loaded zero engineering-craft priors.
- **Orchestrator-Advisor schema** (`docs/RULES.md` new rule): coordinator drafts
  detailed specs → Opus-class executors run small verifiable milestones → coordinator
  reviews as advisor between milestones.

## 2026-07-12 — Stack-matched best-practice sources (phase-weighted routing)

No new gates, no phase renumbering. The router stays a harness: mappings say WHICH skill
to consult WHEN — the practice content lives in the source skills.

- **Best-Practice Source Routing** (`skills/skill-router/SKILL.md`, new section — the
  single home): declarative table mapping detected stack signals to best-practice skill
  sources — `typescript-best-practices` (user-level), `vercel:react-best-practices` /
  `vercel:nextjs` (vercel plugin), `drizzle-orm-patterns` / `better-auth` /
  `zod-validation-utilities` / `turborepo-monorepo` (developer-kit-typescript) — plus
  KNOWN GAPS with Context7 fallbacks (hono, trpc/orpc, tanstack-*). Better-T-Stack
  scaffolds have no meta-skill: they decompose into component signals and route per
  component.
- **Resolution + pinning** (`commands/detect.md` STEP 3b): detect resolves the table
  against what is actually installed and pins `bestPracticeSources[]` (each
  installed/missing + fallback) into `.claude/project-context.json`; phases read the
  pin, never re-derive. A missing source is a flagged gap + fallback, never a blocker.
- **Phase weights** — how each phase consults the pin: implement loads matching
  installed sources per-MIU BEFORE code (`commands/implement.md` STEP 0/1); review
  primes the matching reviewer prompts (`commands/review.md` STEP 2); validate is
  consult-on-failure only — a green run loads nothing (`commands/validate.md`); fix
  consults before writing each fix (`commands/fix.md` Step 2).
- **Gate surface** (`commands/dev-pipeline.md` / `commands/plan.md` Phase 4): the
  architecture-approval gate prints "stack X detected → these sources will be active in
  implement/review/validate/fix — confirm/override"; overrides are recorded back into
  the pin. skill-scout (`agents/skill-scout.md`) reports the sources with
  installed/missing status and install hints; new sources registered in `deps.json`
  (including a `better-t-stack` search-required entry so skill-doctor watches for an
  upstream meta-skill).

## 2026-07-06 — Blindspot pass, architecture-first ordering, explicit Deviations log

Field-guide review items #15–#17 (see `evals/BACKLOG.md`), landed pending ratchet. No new
gates, no phase renumbering; the SPEC contract stays six sections.

- **Blindspot pass — unknown unknowns, two stages** (`skills/spec-elicitor/SKILL.md`
  "Blindspot rounds" + `agents/requirements-analyst.md` "Blindspot findings" +
  `commands/dev-pipeline.md` / `commands/plan.md` Phase 1.1): after the six sections,
  Mode A runs a code-blind decide-or-defer round over commonly-forgotten surfaces
  (topics from installed engineering-craft categories, static fallback otherwise; max
  2 rounds); Phase 1.1 then presents the analysts' code-grounded findings the same way
  (max 2 loops). Outcomes land in a `## 7. Blindspots considered` SPEC APPENDIX —
  Decided folds into the relevant section, Deferred is exempt from Phase 8.6 tracing
  (`commands/verify-traceability.md` STEP 1). Mode B: at most ONE mini-blindspot
  question when the locked axis touches a shared surface.
- **Architecture-impact questions first** (`skills/spec-elicitor/SKILL.md` Rule 9):
  among candidate questions, ask FIRST those whose answer would change component
  boundaries, the data model, or an external contract — a late answer there
  invalidates work; a late cosmetic answer invalidates nothing.
- **Explicit Deviations log** (`commands/implement.md` STEP 1 + `agents/doc-writer.md`
  + `commands/deliver.md` PHASE 9): a mid-MIU edge case forcing divergence from the
  approved plan takes the CONSERVATIVE option and is logged immediately under
  `## Deviations` in the tracked execution doc (what / why / conservative choice /
  non-conservative alternative); no conservative resolution means it is NOT a
  deviation — stop and ask. doc-writer verifies logging at MIU boundary + deliver;
  the PR body gains a "Deviations from plan" section (omitted when empty). Log and
  surface only — never a silent divergence, never a new gate.
- **New frozen eval task T11** (`evals/TASKS.md`): "feature with hidden cross-cutting
  surfaces" — instruments blindspot rounds, the stage-2 analyst loop, appendix
  recording, deferred-item exemption at 8.6, and silent-deviation traps.

### Deviations from the locked design

Practicing this entry's own rule — the implementation diverged from the locked design in
three places, each resolved conservatively and logged here (what diverged / why /
conservative choice / non-conservative alternative):

- **`evals/README.md` task-count fix (10 → 11).** What diverged: the design listed only
  `evals/TASKS.md` as the eval-suite change, but the README hard-codes the frozen task
  count in two lines. Why: adding T11 made those lines factually wrong. Conservative
  choice: update the two counts in place, nothing else in the README. Non-conservative
  alternative: derive the count dynamically or restructure the README so it never states
  a number — larger blast radius than the feature warrants.
- **Activation-banner line in `skills/spec-elicitor/SKILL.md`.** What diverged: the
  design specified the blindspot rounds but said nothing about the skill's activation
  banner. Why: the banner is the user's only up-front signal of what the interview will
  do; omitting the pass there makes the batched round 1 feel like a protocol violation.
  Conservative choice: add ONE line to the existing banner (both occurrences, incl. the
  worked example) announcing the Mode A blindspot pass. Non-conservative alternative:
  redesign the banner format or add a separate blindspot banner — not needed.
- **Rule-1 exception codified in place.** What diverged: the design's "present ONE
  compact decide-or-defer list" contradicts Protocol Rule 1 (one question per turn),
  which the design never reconciled. Why: leaving two absolute rules in conflict invites
  the skill to "fix" it either way at runtime. Conservative choice: codify the batched
  list as an explicit, narrowly-scoped exception at the point of use (step 3 of the
  stage-1 procedure), leaving Rule 1's text authoritative. Non-conservative alternative:
  rewrite Rule 1 itself to allow batching generally, or split the round into per-surface
  turns (doubles interview length) — both rejected.

## 2026-07-06 — Factory-redesign adaptations: 4 ideas adopted, architecture rejected

Per `docs/factory-redesign-assessment.md` (the external redesign plan's architecture was
rejected; its four transplantable ideas landed as prompt/tool changes — no new runtime,
no gate renumbering, zero always-loaded additions). Each awaits its own ratchet round.

- **Contract-first MIU ordering** (`skills/miu-methodology/SKILL.md` "Contract-source
  rule" + `agents/tech-lead.md`): MIUs defining first-party contracts (DTOs, shared
  types, zod schemas, API shapes) precede their consumer MIUs in the DAG; cross-boundary
  MIUs name their contract file in "What it does". Fires at Phase 4-5 decomposition.
- **Mutation-testing backstop for Rule 19** (`commands/validate.md` STEP 3.5 +
  `docs/RULES.md` Rule 19): OPT-IN — when a diff rewrites existing test assertions AND
  the repo has Stryker configured, mutation tests run scoped to changed files; <70%
  score surfaces as a review finding. Mechanically detects tautological test rewrites.
- **Quality-goals axis in the SPEC** (`skills/spec-elicitor/SKILL.md` §6 "Quality
  Criteria (质量标准)" + `commands/verify-traceability.md`): Mode A elicits measurable
  NFRs (perf budgets, rate limits, audit logging — or an explicit "simplicity wins");
  Phase 8.6 traces them like acceptance criteria (new `quality` category).
- **Mechanical MIU-format validator** (`tools/validate-miu-breakdown.sh`, called from
  `commands/implement.md` STEP 0): the tech-lead checklist made executable — 8 fields,
  Files ≤3, enums, Build/Deploy stated, ≥2 done-when, DAG (no forward refs), and the
  contract-source rule. Exit 1 lists every miss before any MIU is implemented.

## 2026-07-06 — CLAUDE.md diet + real lifecycle hooks (measured by the eval harness)

- **CLAUDE.md 562 → ~94 lines.** The always-loaded file now carries ONLY the routing
  table, the G1–G4 gate table, the one-line normative form of Rules 1–23, session
  lifecycle, and pointers. Full rule bodies (rationale, failure-mode narratives,
  decision trees) relocated wholesale to `docs/RULES.md` — same rule numbers, zero
  content loss. Rationale: official guidance — an over-long always-loaded file makes
  the model ignore half of it; the churn history showed every incident becoming a new
  prose paragraph in always-on space.
- **Real Claude Code lifecycle hooks** (`hooks/hooks.json`): SessionStart
  (`session-start.sh` — pipeline-state resume signal, rate-limited engineering-craft
  refresh, opt-in co-review nudge; the file Rules 5 had referenced but which never
  existed) and Stop (`stop-review-guard.sh` — blocks turn-end while an unblessed
  commit has a pending AUTO-REVIEW DIRECTIVE; loop-safe via stop_hook_active;
  fail-open). Rules 2/5 are now deterministic instead of prose-hopeful.
- **Trivial-change bypass** (Rule 1): one-sentence diff, ≤2 files, no
  schema/env/auth/payment/URL surface → implement directly with a test + an audit log
  line. Ends the routing tax on typo-class changes; everything larger still routes.
- **`disable-model-invocation: true`** on `co-review` (Rule 21 opt-in made mechanical)
  and `setup-machine` (machine mutation, human-initiated only). Deliberately NOT
  applied to deliver/deploy/hotfix — their auto-invocation is core design (Rule 3/14)
  and their side effects are gated internally (blessing, gates, smoke).
- **Living-docs precedence softened**: docs are the first read, but code remains
  ground truth for load-bearing answers (the phantom-hooks incident this very change
  fixes was a stale-doc artifact).
- Measured: eval-harness baseline (T03/T05/T07) recorded before this change; post-diet
  re-score in `evals/results.tsv`.

## 2026-07-01 — hardening pass on both 2026-06-30 additions

Both entries below were adversarially reviewed after landing; each surfaced real,
verified-by-execution bugs (not just prose review) that are now fixed:

- **SDK reality-check** (Rule 22 / `verify-sdk-surface.md`): fixed 6 mechanical gaps —
  detection missed scoped `require('@scope/pkg')` and dynamic `import()`; `$PKG`
  extraction from matched import lines was undefined; the untyped-package fallback
  ("prove it exists in runtime dist / not borrowed from a different package") was
  asserted with no procedure — now has concrete greps that reproduce the reference bug
  at 3 independent checkpoints; the return-shape check only operationalized the
  declared side, not the diff's actual consumption; the probe-row enforcement had no
  checkable join (`$SURFACES`/`$PROBED` referenced, never assigned) — now a mechanical
  diff of a persisted surface list against the probe table. **Generalized Rule 22 from
  "verify SDK method calls" (implementation-time) to "verify any third-party surface a
  DESIGN depends on" (design-time)** — `technical-architect` now runs the same
  context7 + installed-types check before finalizing an architecture, with a
  "Third-Party Surfaces Verified" table in its output. The original bug's design doc
  already *claimed* verification; a post-hoc code gate alone doesn't stop a design
  from assuming something false in the first place.
- **Co-review**: fixed a cold-start bug (a brand-new doc channel's `REVIEW-CYCLE.md`
  was never scaffolded, so the adapter had nothing to detect against — the channel
  was permanently stuck) and wired `roundHistory` into the cursor schema so the
  convergence safeguard's "trending up" / "reappeared after resolved" checks read
  real per-round data instead of being narrated with nothing backing them. The first
  draft of that fix was itself broken (jq scalars wrapped in arrays, a false-positive
  on round 1) — caught by actually running it against synthetic data, not by re-reading
  the prose.

## 2026-06-30 — SDK/API reality-check gate (Rule 22)

- **`/dev-pipeline:verify-sdk-surface` command** (`commands/verify-sdk-surface.md`, Phase 7.6).
  Proves every third-party SDK method the diff *calls* or *type-stubs* actually exists — with
  the right signature and **exact return shape** — in the INSTALLED package
  (`node_modules/<pkg>/**/*.d.ts`), cross-checked against latest docs via **context7**, and
  requires a recorded `docs/<feature>/SDK-PROBE.md`. Blocks on: method absent from installed
  types, a stub borrowing a method from the wrong package, or a return-shape mismatch (reading
  `x.url` when the type is `x.data.url`).
- **CLAUDE.md Rule 22** — "never type or call a third-party surface you haven't verified against
  the installed package + latest docs." Types are derived from installed `.d.ts`, never invented;
  untyped packages may only stub runtime-proven methods and must not fake another SDK's method.
- **Wired to fire** (not aspirational): `commands/review.md` STEP 1.6 and `commands/validate.md`
  STEP 2.6 auto-invoke it whenever the diff imports/uses a third-party package or edits a `*.d.ts`.
- **Failure mode it prevents:** a real production 500 — `getUploadMetadata` hand-stubbed onto
  `wx-server-sdk` (no types, no such method) with an invented shape; the real method + shape were
  in `@cloudbase/node-sdk`'s `.d.ts` the whole time. A design doc *claimed* "verified against
  @cloudbase/node-sdk@2.10.0" but produced no probe — Rule 22 makes the probe a checkable artifact.

## 2026-06-30 — cross-agent co-review relay

- **`/dev-pipeline:co-review` command** (`commands/co-review.md`, optional/opt-in). Fetches
  external reviews from MULTIPLE sources/formats, integrates them, responds back, and manages
  Claude↔Codex turn-taking so a review relay never deadlocks, both-edits-at-once, or loops
  forever. Generalizes the manual `@codex review` loop into a bounded, auto-stopping flow.
  Two resolution paths by `Finding.kind`: `code` → `/dev-pipeline:fix` → re-bless → push;
  `design` → edit the design doc, no code gate (the doc-ping-pong case).
- **`co-review-adapter` agent** (`agents/co-review-adapter.md`). The pluggable "not one format"
  contract — each source implements detect / parse / respond / retrigger / cursorAfter and
  normalizes to one canonical `Finding` shape (a superset of the review-findings table). Ships
  two MVP adapters: `gh-pr-bot` (delegates parse to `review-analyzer` for live-code verification
  + the re-flag trap) and `doc` (git-tracked `REVIEW-CYCLE.md`, turn-marker handoff).
- **Convergence safeguard** (baked from a real 7-round relay that never hit zero). `--watch`
  auto-stops on round-cap / stall / trend-up / a resolved finding reappearing, and a
  false-positive ledger suppresses re-flags (e.g. "`os.getenv` already covered"). Cursor-gating
  (timestamp / doc-SHA) means re-anchored old comments are never re-processed.
- **Opt-in session-start nudge** (`hooks/co-review-nudge.sh`). Gated on
  `.claude/co-review/enabled`; surfaces `CO-REVIEW PENDING` when another agent left new input.
  Suggestion only — NOT auto-run (see CLAUDE.md Rule 21).

## 2026-06-24 — engineering-craft auto-bootstrap

- **Layered, self-healing `engineering-craft` skill bootstrap.** Three independently
  rate-limited paths converge the skill without manual setup: the SessionStart hook (primary,
  once per session), `commands/detect.md` STEP 0 (secondary safety net for flows that run
  detect), and `/dev-pipeline:review` STEP 1.5 (self-bootstraps if review is invoked
  directly). detect uses its own `.last-skill-sync` marker, separate from the hook's
  `.last-mirror-sync`, so a mirror-only refresh can't suppress a needed skill pull. On a
  fresh machine the missing skill is cloned from the public HTTPS mirror; when present it's
  fast-forward-refreshed. Each marker is advanced **only on a successful clone/pull**, so one
  offline blip can't suppress bootstrap for a day. The `stat` mtime read is GNU/BSD-portable
  (tries `-c %Y` before `-f %m`). `commands/init.md` STEP 1.5 documents the layering
  accurately (it's not "every command").
- **`/dev-pipeline:setup-machine` command** (`commands/setup-machine.md`). Idempotent
  fresh-machine bootstrap — detects what's missing (skill, plugin, hooks, settings,
  launchd), clones the skill first (the installer lives inside it, so it can't clone
  itself), then runs the installer for the rest, defaulting all clones to public HTTPS so
  a device with no SSH key still works. macOS-first (launchd). Use on first run on a new
  device or when a hook/setting drifts.
- **Knowledge-reference sidecar** (`commands/review.md` STEP 1.5b). `/dev-pipeline:review`
  emits `.claude/knowledge-refs-<sha>.json` recording which engineering-craft rules primed
  the reviewer prompts. Reserved for a future rule-decay loop in
  `/dev-pipeline:consolidate-lessons` (not yet consumed) — a write-only audit trail until
  that loop exists.

## 2026-06-07 — Socratic gate across fix/update + business-vs-technical classifier

- **Widened the Socratic trigger surface** (`skills/spec-elicitor/SKILL.md`,
  `CLAUDE.md` Rule 23). The elicitor used to fire only for new features
  (`plan` / `dev-pipeline` / `scaffold-from-prd`). It now also fires for enhancements
  (`update`) and **business/behavioural bugs** (`fix` Step 1.5) — anywhere a request's
  *intended behaviour* is undecided, not just a literal requirements phase.
- **Business-vs-technical test** (`skills/spec-elicitor/SKILL.md` → "When to run me").
  Canonical litmus: "is the correct behaviour self-evident, or is it itself the thing in
  question?" Self-evident (TypeError, crash, build break) → skip; must-be-decided
  ("discount applies twice") → run the pass. Rule 23 and every flow point at this one definition.
- **Scope-Lock mode (Mode B)** (`skills/spec-elicitor/SKILL.md`). A lightweight 2–4-turn
  pass for enhancements/bugs that writes NO file — returns a 🔒 Intent Lock folded into the
  caller's gate (`update` G1 / `fix` triage) and the commit/PR body. Keeps small fixes out
  of Phase 8.6 traceability machinery. The original full-SPEC behaviour is Mode A.
- **`requirements-analyst` open questions are now framed Socratically**
  (`agents/requirements-analyst.md`) — clarify / probe assumptions / probe evidence /
  alternatives / implications, with numbered options.

## 2026-05-28

- **Merge the two lesson stores into one canonical home.** Cross-file-seam failure
  modes are now authored ONLY in `skills/cross-file-reasoning/FAILURE_MODES.md`
  (always present, live-appendable mid-trace). `/dev-pipeline:consolidate-lessons`
  publishes a generated, read-only mirror into the engineering-craft repo's
  `cross-file-seams` category. One fact, one author; the public mirror stays complete.
- **De-project the knowledge base.** Stripped all project-specific coordinates
  (project names, PR numbers, reviewer-bot names, monorepo paths, internal doc links)
  from the lesson/skill/gate files. Lessons read as general engineering craft — the
  mechanism, how it was learned, and the fix, never "which project."

## 2026-05-27 — Cross-file reasoning

- **`cross-file-reasoning` skill** (`skills/cross-file-reasoning/SKILL.md`). Seven
  backward-traces (env-var, route/URL, SDK option, event lifecycle, mock completeness,
  conditional coupling, wrapper lifecycle) run at every MIU boundary
  (`/dev-pipeline:implement`) and pre-push (`/dev-pipeline:review`). A BLOCK verdict
  halts the calling command. Growing catalog in `FAILURE_MODES.md`.
- **Build/Deploy/Runtime MIU field** (`skills/miu-methodology/SKILL.md`). Every MIU
  must state which build contexts a change affects and how each is satisfied — catches
  "passed local gates, broke an isolated Docker/CI build that only runs on main."
- **STEP 5.5 Deployment-Build Parity gate** (`commands/validate.md`). Enumerates and
  runs every deployable's REAL build command (incl. `docker build` + a runtime require
  smoke) and reproduces any CI job gated to non-PR branches locally.
- **`doc-writer` agent** (`agents/doc-writer.md`). Keeps the git-tracked `docs/`
  execution log as the source of truth at every MIU boundary and at deliver; the local
  `.claude/*.json` is demoted to a thin disposable pointer.

## 2026-05-25 — Engineering-craft auto-update pipeline

- **`/dev-pipeline:consolidate-lessons`** (`commands/consolidate-lessons.md`). Sweeps
  per-project `.learnings/JOURNAL.md`, classifies entries (cross-file / new-pattern /
  refinement / noise), folds them into the engineering-craft knowledge base, and
  publishes the cross-file mirror.
- **Journal capture** (`hooks/post-commit`). Commits matching `fix(`, `hotfix(`,
  `regression(`, `revert(`, or `review-fix:` append a structured entry to
  `<repo>/.learnings/JOURNAL.md`. Never fails the commit.
- **Scheduled reminder** (`hooks/consolidate-lessons-notify.sh` + launchd plist
  `com.engineering-craft.consolidation-reminder`, every 2 days). Counts unconsolidated
  entries and posts a notification; consolidation itself stays interactive.

## 2026-05-24 — Socratic spec elicitation

- **`spec-elicitor` skill** (`skills/spec-elicitor/SKILL.md`). Walks the user from a
  vague idea to a complete SPEC (Problem / Solution / Constraints / Non-goals / Success
  Criteria) one numbered-options question at a time. Fires at the very start of
  `/dev-pipeline:plan`, `/dev-pipeline:dev-pipeline`, and `/dev-pipeline:scaffold-from-prd`
  when no written SPEC/PRD exists. Output: `docs/<slug>/SPEC.md`.
