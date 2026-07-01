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
