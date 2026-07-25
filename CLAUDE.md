# dev-pipeline Plugin — Auto-Loading Instructions

Auto-loads when the plugin is enabled. This file is deliberately SHORT: it carries the routing table, the gates, and the one-line form of every rule. Full bodies (rationale, failure-mode narratives, decision trees) live in [`docs/RULES.md`](docs/RULES.md) — same rule numbers. **What's new**: skim [`CHANGELOG.md`](CHANGELOG.md) at session start; anything there is in force.

---

## ROUTING (check every turn that involves code)

Classify the request, announce it in one line ("Classified as BUG_FIX → `/dev-pipeline:fix`"), invoke the command BEFORE writing code. Never silently fall through to ad-hoc coding.

| Request pattern | Type | Flow |
|---|---|---|
| "Add/Build/Create [new]" | NEW_FEATURE | `/dev-pipeline:pipeline` |
| "Improve/Update/Enhance [existing]" | ENHANCEMENT | `/dev-pipeline:update` |
| "Fix [bug]" / [error message] | BUG_FIX | `/dev-pipeline:fix` |
| "Debug [intermittent issue]" | BUG_FIX_COMPLEX | `/dev-pipeline:pipeline` |
| "Clean up/Refactor/Simplify [X]" | REFACTOR_PROPOSAL | `/dev-pipeline:refactor` (propose-only) |
| "Address review/PR feedback" | PR_REVIEW_FIX | `/dev-pipeline:pr-review` |
| "Production down" | HOTFIX | `/dev-pipeline:hotfix` |
| "ship it" / "merge" / "open PR" | DELIVERY | `/dev-pipeline:deliver` |
| "Add tests" | ADD_TESTS | `/dev-pipeline:pipeline` (skip design) |
| "New project" / PRD | NEW_PROJECT | `/dev-pipeline:scaffold-from-prd` |
| "Performance" | PERFORMANCE | `/dev-pipeline:perf` |
| Unclassified code request | BUG_FIX | `/dev-pipeline:fix` (safe default) |

**Trivial-change bypass (the one sanctioned shortcut):** if the diff is describable in one sentence, touches ≤2 files, and has NO schema/env/auth/payment/URL-topology surface — implement directly WITH a test, then log `{"event":"trivial-bypass", "reason":…}` to `.claude/agent-events.jsonl`. Everything larger routes. When unsure, route.

If ambiguous, ask ONE classification question. Business-intent ambiguity → the routed command runs the Socratic gate first (Rule 23).

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

1. **Route first** — every code request goes through a pipeline command (trivial bypass above is the only exception).
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
14. **Cross-checks are constraints, not manual gates** — every gate must fire automatically; if a ship can complete without a gate firing, wire the missing trigger.
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

---

## PROJECT KNOWLEDGE

`.claude/docs/` living documents (`PROJECT_STATUS.md`, `ARCHITECTURE.md`, `RECENT_CHANGES.md`) are the FIRST read — but code remains ground truth: if a doc is >1 day old, contradicts the code, or the answer is load-bearing, verify in the code and run `/dev-pipeline:sync`. Missing docs → `/dev-pipeline:sync init`.

Delegated references (auto-loading skills — do not reimplement here): MIU decomposition → `skills/miu-methodology` · project detection → `skills/project-detector` · skill/adapter routing → `skills/skill-router` · cross-file seam traces → `skills/cross-file-reasoning` · Socratic elicitation → `skills/spec-elicitor`.

Sibling tool: `spec-forge` scaffolds NEW projects (only `/dev-pipeline:scaffold-from-prd` bridges to it). Toolbelt MCPs (browser/memory/research) are used INSIDE phases; they never replace gates.

---

## EMERGENCY OVERRIDE

`REVIEWED=1 git push` bypasses the blessing gate — incidents only, auto-logged to `.claude/.review-overrides.log`, retroactive review required in the same session.
