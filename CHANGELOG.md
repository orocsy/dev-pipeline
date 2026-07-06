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
