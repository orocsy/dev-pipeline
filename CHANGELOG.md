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

## 2026-06-07 — Socratic gate across fix/update + business-vs-technical classifier

- **Widened the Socratic trigger surface** (`skills/spec-elicitor/SKILL.md`,
  `CLAUDE.md` Rule 21). The elicitor used to fire only for new features
  (`plan` / `dev-pipeline` / `scaffold-from-prd`). It now also fires for enhancements
  (`update`) and **business/behavioural bugs** (`fix` Step 1.5) — anywhere a request's
  *intended behaviour* is undecided, not just a literal requirements phase.
- **Business-vs-technical test** (`skills/spec-elicitor/SKILL.md` → "When to run me").
  Canonical litmus: "is the correct behaviour self-evident, or is it itself the thing in
  question?" Self-evident (TypeError, crash, build break) → skip; must-be-decided
  ("discount applies twice") → run the pass. Rule 21 and every flow point at this one definition.
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
