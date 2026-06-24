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

## 2026-06-24 — engineering-craft auto-bootstrap

- **Auto-bootstrap the `engineering-craft` skill on every command** (`commands/detect.md`
  STEP 0, which runs at Phase 0 of every flow). On a fresh machine where the skill is
  missing it clones the public mirror; when present it refreshes the skill clone itself
  in the background. Rate-limited to once per 24h. Clone failures degrade gracefully
  (warn, never a false "installed" success) so `/dev-pipeline:review` STEP 1.5 always has
  the incident-derived priors when they're available. `commands/init.md` STEP 1.5 just
  documents that init no longer needs a manual bootstrap step.
- **`/dev-pipeline:setup-machine` command** (`commands/setup-machine.md`). Idempotent
  fresh-machine bootstrap — detects what's missing (skill, plugin, hooks, settings,
  launchd), wraps the engineering-craft installer, verifies end-to-end. Use on first run
  on a new device or when a hook/setting drifts.
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
