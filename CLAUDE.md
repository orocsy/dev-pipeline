# dev-pipeline Plugin — Auto-Loading Instructions

Auto-loads when the plugin is enabled. This file is deliberately SHORT: it carries the recipe routing table, the gates, and the one-line form of every rule. Full bodies (rationale, failure-mode narratives, decision trees) live in [`docs/RULES.md`](docs/RULES.md) — same rule numbers. **What's new**: skim [`CHANGELOG.md`](CHANGELOG.md) at session start; anything there is in force.

---

## ROUTING — pick a recipe (check every turn that involves code)

Take the FIRST recipe below whose *When* fits, announce it in one line — `Recipe: <id> — <flow>` — and start its first step BEFORE writing code. A recipe runs only the phases that task type needs: do not default to the full pipeline because it looks safest. Keep the announcement in exactly that form; the learning watcher reads it to learn which recipes work. Source of truth: [`recipes/recipes.json`](recipes/recipes.json); escalation triggers, skips and done-when are in [`skills/skill-router/SKILL.md`](skills/skill-router/SKILL.md) → Recipe Routing. In the table `/x` means `/dev-pipeline:x`.

<!-- recipes:compact:begin -->
| Recipe | When | Flow |
|---|---|---|
| `hotfix` | Production is down or a critical regression is live right now. | `/hotfix` → prod smoke → `bug-fix` follow-up |
| `trivial` | Diff fits one sentence, touches at most 2 files, and has no schema/env/auth/payment/URL-topology surface. | implement + test → log trivial-bypass |
| `docs-sync` | Docs, living docs, handoff or README updates with no change to code behaviour. | `/sync` or doc-writer → `/deliver` |
| `review-only` | Review, audit or second opinion on a diff, branch or PR; no fixing asked for. | `/review` or code-review → report → stop |
| `test-only` | Add or repair tests, or raise coverage, without changing behaviour. | test-planner → tests → `/validate` → `/review` → `/deliver` |
| `ui-design-round` | The ask is visual/UX: designs, options, mockups, a redesign, or a partner's UI change request. No building yet. | design-checker → design skill → ui-design.md for every platform → user picks → stop |
| `prd-digest` | A PRD, brief or spec arrives for an EXISTING project and must become a plan. No code yet. | prd-parser → spec-elicitor gaps → `/plan` (1-6) → stop at G4 |
| `new-project` | Start a brand-new project from a PRD or description. | `/scaffold-from-prd` |
| `contract-change` | An API/OpenAPI/DTO/shared-fixture change that another lane (backend, web, iOS, admin) consumes. | `/plan` (contract + consumers) → producer + all consumer types in one PR → `/verify-contract` → `/verify-blast-radius` → `/review` → `/deliver` → tell each lane |
| `bug-fix` | A reported bug, error message or wrong behaviour with a findable cause. | `/fix` → red test → `/validate` → `/review` → `/deliver` |
| `pr-feedback` | Review comments on an open PR need answering or fixing. | `/pr-review` → `/validate` → `/review` → push |
| `enhancement` | Improve an existing feature inside one module with no schema/auth/payment/env/URL surface. | `/update` → `/validate` → `/review` → `/deliver` |
| `refactor` | Clean up, restructure or simplify working code. | `/refactor` (propose-only) |
| `perf` | Something is slow, heavy or janky. | `/perf` → fixes as `enhancement` |
| `deliver` | Ship it: commit, push, open or merge a PR, deploy. | `/deliver` |
| `feature` | New capability, screen, endpoint or flow; or anything touching schema, auth, payments, env vars or URL topology; or a complex/intermittent bug. | `/pipeline` (phases 0-12, G1-G4) |
<!-- recipes:compact:end -->

- **Escalate** the moment a recipe's trigger appears: `Recipe: feature (escalated from enhancement: touches auth)`, then continue from the matching phase.
- **`trivial`** is the one sanctioned shortcut (implement WITH a test, log `{"event":"trivial-bypass","reason":…}` to `.claude/agent-events.jsonl`). When unsure, take the next recipe down.
- **Unclear** between two recipes → ask ONE question naming both. Unclassifiable code request → `bug-fix`. Business-intent ambiguity → the routed command runs the Socratic gate first (Rule 23).
- Never silently fall through to ad-hoc coding.

---

## GATES (stop and ask — no exceptions)

| Gate | After | Ask |
|---|---|---|
| G1 | Phase 1 requirements | "Requirements ready. Continue? [Y]" |
| G2 | Phase 3 design check | "Design reviewed. Continue? [Y]" |
| G3 | Phase 4 architecture + MIUs | "**APPROVE ARCHITECTURE** — no code until confirmed." |
| G4 | Phase 6 test plan | "**FINAL APPROVAL** — after this I run autonomously." |

After G4: Phases 7–12 run without further approval.

---

## THE RULES (one line each — full bodies in docs/RULES.md, same numbers)

1. **Route first** — every code request starts from a recipe (ROUTING above); `trivial` is the only recipe without a pipeline command.
2. **Hook directives execute immediately** — an AUTO-REVIEW DIRECTIVE runs before your next response (the Stop hook enforces this deterministically).
3. **Auto phase transitions** — all MIUs done → invoke `/dev-pipeline:deliver` yourself; don't wait to be asked.
4. **Never merge outside the flow** — no direct `gh pr merge`; delivery is `/dev-pipeline:deliver`'s 10-step gate chain.
5. **Auto-resume on session start** — the SessionStart hook surfaces pipeline state; act on what it reports.
6. **E2E mandatory** for payment/auth/multi-step flows — no deferral.
7. **Env vars are a hard gate** — every `process.env.X` in the diff must exist in `.env.example` + CI + prod before merge.
8. **Review before push** — `/dev-pipeline:review` blesses HEAD (`.claude/.last-reviewed-sha`); the pre-push hook refuses unblessed SHAs; every new commit invalidates the blessing.
9. **Refactor is propose-only** — produce a proposal doc; never silently rewrite working code; user accepts by ID.
10. **Docs before code** — read README/CLAUDE.md/ARCHITECTURE/URL_TOPOLOGY before touching deploy topology, URLs, env contracts, or data models.
11. **Fix the class, not the instance** — before "fixed": what other inputs share this root cause?
12. **No file is out of scope** — config/build/infra files are fixable; prefer the simpler fix one layer up.
13. **Self-correct mid-process** — when an assumption is corrected, stop, list dependent work, redo it in the same turn.
14. **Cross-checks are constraints, not manual gates** — every gate must fire automatically; if a ship can complete without a gate firing, wire the missing trigger. **Scope is the FAMILY the change joins, not the diff**, and triggers match SHAPE over vocabulary: a rule keyed to `consumedAt` cannot fire on `status: pending → active`. When a rule existed and still did not fire, fix the TRIGGER, not the prose — move it from words a human must match to a surface a machine enumerates (`/dev-pipeline:review` STEP 1.7).
15. **Raised PR ≠ shippable PR** — check mergeable state immediately after `gh pr create`; a CONFLICTING PR gets no review automation.
16. **Frontend changes get E2E against the deploy preview** before merge — unit tests can't see SSR/hydration/basePath reality.
17. **Production smoke after every deploy** — preview green ≠ production green; run the narrow smoke suite against prod URLs.
18. **Removing "dead code" requires proving what it guarded** — read comments, `git log -p` the introduction, trace sibling branches, chaos-test the upstream failure.
19. **Tests changed alongside behaviour prove agreement, not correctness** — never rewrite a test to match new code as if the old expectation never existed.
20. **Verify against PRODUCTION URLs** before declaring a deploy successful.
21. **Co-Review is opt-in** — never auto-invoke `/dev-pipeline:co-review`; cursor-gate detection; convergence safeguard mandatory in `--watch`.
22. **Third-party reality-check** — never design against, call, or type-stub a third-party surface unverified against the INSTALLED package + docs; record the probe artifact (`SDK-PROBE.md`).
23. **Clarify business intent before building or fixing** — self-evident technical fault → skip; behaviour-in-question → `spec-elicitor` (Mode A full SPEC / Mode B Scope-Lock). Exempt: hotfix.
24. **Orchestrator-Advisor schema** — coordinator drafts specs → Opus-class executors run micro-milestones → advisor review between them; activates on `/orchestrate` or explicit request, otherwise direct execution. Full body: `docs/RULES.md` Rule 24.

---

## SESSION LIFECYCLE (real hooks — registered in hooks/hooks.json)

- **SessionStart** (`hooks/session-start.sh`): reports active pipeline state (branch/phase/MIU) so you resume rather than restart; refreshes the engineering-craft skill (rate-limited); surfaces a CO-REVIEW PENDING nudge when that channel is enabled.
- **Stop** (`hooks/stop-review-guard.sh`): blocks ending the turn while `.claude/.auto-review-pending` names a commit whose SHA is unblessed — run `/dev-pipeline:review`, then finish. This is Rule 2/8 made deterministic.
- Git hooks (installed via `~/.claude/setup-git-hooks.sh`): pre-commit lint/typecheck · pre-push blessing + doc guard · post-commit journal + AUTO-REVIEW DIRECTIVE.
- State: `.claude/pipeline-state.json` (thin pointer; tracked docs are the truth — see `agents/doc-writer.md`), `.claude/agent-events.jsonl` (audit trail).
- Shell regression suite for tracked-handoff/resume plumbing: `tests/run.sh`.

---

## PROJECT KNOWLEDGE

`.claude/docs/` living documents (`PROJECT_STATUS.md`, `ARCHITECTURE.md`, `RECENT_CHANGES.md`) are the FIRST read — but code remains ground truth: if a doc is >1 day old, contradicts the code, or the answer is load-bearing, verify in the code and run `/dev-pipeline:sync`. Missing docs → `/dev-pipeline:sync init`.

Delegated references (auto-loading skills — do not reimplement here): MIU decomposition → `skills/miu-methodology` · project detection → `skills/project-detector` · skill/adapter routing → `skills/skill-router` · cross-file seam traces → `skills/cross-file-reasoning` · Socratic elicitation → `skills/spec-elicitor`.

Sibling tool: `spec-forge` scaffolds NEW projects (only `/dev-pipeline:scaffold-from-prd` bridges to it). Toolbelt MCPs (browser/memory/research) are used INSIDE phases; they never replace gates.

---

## EMERGENCY OVERRIDE

`REVIEWED=1 git push` bypasses the blessing gate — incidents only, auto-logged to `.claude/.review-overrides.log`, retroactive review required in the same session.
