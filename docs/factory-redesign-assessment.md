# Factory Redesign Plan — Critical Assessment

> Assesses `docs/factory-redesign-plan.md` against the repo at `main` @ `5577571` (2026-07-06,
> post-diet). The plan was written against a snapshot that predates: the CLAUDE.md diet
> (562→94 lines, measured +1.9 mean by the eval harness), Rules 21–23, real lifecycle hooks,
> the eval harness itself, and the engineering-craft knowledge loop. Verdict first, evidence after.

---

## 1. Verdict: REJECT the architecture, ADAPT four ideas

**Do not implement the plan as designed.** Its load-bearing machinery — a TypeScript/LangGraph
orchestrator, 7 new agents, gitignored `artifacts/` JSON as gate inputs, a `playbooks/` knowledge
stack with embeddings, the ≤25-LOC MIU, and a G0–G6 renumbering — conflicts with the repo's
measured, working architecture and would recreate its documented failure modes (see §3).

**Adapt** (§5): contract-first MIU ordering, mutation testing as a Rule-19 mechanical backstop,
a quality-goals axis in the SPEC, and mechanical (not prose) MIU-format validation.

Why reject the rest:
1. **The plan redesigned files it admits it never read.** Its own Caveats section lists
   `miu-methodology/SKILL.md`, `technical-architect.md`, `tech-lead.md`, `pipeline.md`,
   `plan.md`, `implement.md` as unfetched — i.e., the exact core it proposes to replace.
   W1–W4 and the "MIU redefined" table are argued against a reconstruction, and several
   claims are wrong (§2).
2. **Its central diagnosis is already falsified by measurement.** "The fix is not to add rules
   to CLAUDE.md" — correct, and the repo already took the *other* fix (the diet), measured it
   (mean 88.9→90.8, ratchet KEEP, `evals/results.tsv`). The plan offers structural redesign as
   the only escape from rule bloat; the repo found a cheaper one and has the number.
3. **Its rollout metrics are hand-rolled** ("≥30% reduction in P1 findings over two weeks",
   "equal-or-fewer review FAILs over 5 features") because it couldn't know the eval harness
   exists. Any adoption must go through the frozen-task ratchet, one change at a time — which
   the plan's big-bang Steps 1–8 cannot do.
4. **It would multiply the plugin's worst known pathology.** The 2026-07-06 diagram audit
   (`evals/BACKLOG.md` #7–10) found four components with spec-to-reality ratio of ∞ (specced,
   never run: co-review, verify-visual, setup-machine, scaffold-from-prd). The plan adds ~7
   agents, ~8 commands, an orchestrator, gate scripts, and a curator — dozens of never-run specs.

---

## 2. Stale-premise audit

| # | Plan claim | Now | Effect on proposal |
|---|---|---|---|
| S1 | "512-line CLAUDE.md"; "20 hard rules"; fix ≠ more rules | 94 lines, 23 rules, bodies in `docs/RULES.md`; diet measured KEEP | **Weakens** the whole framing. Also plan Step 8 rewrites CLAUDE.md's routing/gate tables — re-inflating the always-loaded file the diet just shrank and measured. |
| S2 | W4: "MIU today is a full feature slice, often >100 LOC, free-text markdown" | `skills/miu-methodology/SKILL.md`: 1–3 files max, 8 mandatory fields, tech-lead checklist rejection, explicit "a whole feature is a Level-1 task, NOT an MIU", mandatory Build/Deploy/Runtime-impact field (born from a real main-breaking incident) | **Weakens** the ≤25-LOC rewrite. The current MIU is already small and format-enforced; what it deliberately is NOT is a single pure function — the skill *bans* "DTO only" units as not independently testable. The plan would re-legalize the anti-pattern the skill exists to prevent. |
| S3 | W9: "No feedback loop captures lessons in queryable form" | post-commit journal → `/dev-pipeline:consolidate-lessons` → `engineering-craft` skill repo, refreshed per session by the SessionStart hook | **Kills** the L4 retrospectives/curator layer as designed — it duplicates a shipped loop (§3). |
| S4 | W10: "G5 referenced but not defined — documentation drift" | G5 is defined: `commands/dev-pipeline.md` Phase 8 "G5: Final ship-confidence gate" (all four verify-* green) | Stale. The drift was fixed; the plan's "renumber to G0–G6 and document G5" solves a solved problem while breaking eval ground truth (§3). |
| S5 | Hooks: "session-start, pre-compact, session-stop, post-commit, pre-push" | Real hooks are SessionStart + Stop via `hooks/hooks.json`; phantom pre-compact/session-stop references were explicitly removed (RULES.md "Session Continuity") | The plan builds on a hook inventory the repo deliberately corrected. |
| S6 | W2: "No phase produces interface contracts" | Partially stale: Rule 22 + SDK-PROBE covers third-party surfaces at design time; `verify-contract` (Phase 7.5) checks FE/BE drift post-code. What's genuinely missing: first-party contracts *authored before* implementation | The only W-item that survives, in narrowed form → MIU-A (§5). |
| S7 | Intake `goals.json` with functional/technical/quality goals, constraints, non-goals, openQuestions | Rule 23 + `spec-elicitor` Mode A already writes `docs/<slug>/SPEC.md` (Problem/Solution/Constraints/Non-goals/Success Criteria), gated at Phase 1.0 | Phase 0 is a JSON re-encoding of a shipped skill. Only the *quality-goals axis* is new → MIU-C. |
| S8 | 3.8 Reviewer: "any P1 or ≥4 P2 → FAIL" | That is verbatim Rule 8's existing threshold (`docs/RULES.md`) | The plan re-invents the review gate it didn't read. |
| S9 | "Plan output = `.claude/plans/current-feature.md`" (v1 path) | State model migrated: tracked `docs/<feature>/` is truth; `.claude/*.json` is a disposable pointer; `miu-progress.json` was deprecated after it froze | **Directly contradicts** the plan's gitignored `artifacts/` as source of truth (§4b). |
| S10 | 8 agents, "no agent writes artifact files" | 11 agents; `doc-writer` exists precisely to write the tracked artifact at every MIU boundary | The "no schema-validated write boundary" gap is half-filled by a mechanism the plan doesn't know about. |

---

## 3. Conflict map

**CONFLICTS (breaks something now working):**
- **G0–G6 renumber + 7-phase split** → breaks `evals/TASKS.md` frozen ground truth: T01/T04/T08
  expected-protocol text references the G1–G4 flow, and RUBRIC D4/D5 score adherence to the
  *current* gates. Editing frozen tasks to match a redesign is the Rule-19 tautology the eval
  README explicitly forbids ("never edit a task to match what the pipeline already does").
- **Dual v1/v2 pipelines (Steps 0–8)** → violates Rule 14's readiness test (every gate fires
  automatically; two parallel routing paths double the surface where a gate can silently not
  fire) and the eval loop's "ONE change, one delta" attribution discipline.
- **≤25-LOC MIU + rewrite of `miu-methodology/SKILL.md`** → destroys the 8-field format that
  `tech-lead.md` enforces, `implement.md` STEP 1 executes against, `doc-writer` records, and
  downstream projects depend on (luxebook's CLAUDE.md commit format and execution-doc
  convention are keyed to the current MIU). Also deletes the Build/Deploy/Runtime-impact field
  — a scar from a real incident — with no replacement in the plan's Zod schema (`sizeBudget`
  is not a build-context analysis).
- **Gitignored `artifacts/` as gate input, pre-push reading `artifacts/phase-6/review.json`** →
  breaks the fresh-clone handoff guarantee (`miu-methodology` state model: "handoff relies on
  tracked docs + git, NEVER on local JSON") and re-creates the exact failure that got
  `miu-progress.json` deprecated.
- **Scaffolding phase (Phase 2)** → scope creep into `spec-forge`'s territory. RULES.md:
  dev-pipeline owns feature work in EXISTING projects; scaffolding is the sibling's job,
  bridged only by `scaffold-from-prd`. The plan quotes this split in Part 1 and ignores it in Part 2.

**DUPLICATES (one fact, one home — plan adds a second home):**
- **Hybrid knowledge layer (playbooks/ + retrospectives/ + Knowledge Curator + embeddings)** ≈
  engineering-craft loop (journal → consolidate-lessons → skill) + `deps.json` hybridSkills +
  skill-router phase-based selection + context7 (L3). The plan itself concedes (§1.5) the
  foundation "already exists". The one novel bit — per-phase injection — is skill-router's job;
  improve the router, don't build a parallel stack. A vector index over retrospectives is
  infrastructure with no runtime to host it.
- **Reviewer Gate Agent + review.json** ≈ Rule 8 blessing + `/dev-pipeline:review` parallel
  reviewers with the identical P1/4×P2 threshold.
- **`traceability.json` (Phase 6)** ≈ `verify-traceability` (Phase 8.6) + G5.
- **Intake `goals.json`** ≈ spec-elicitor SPEC.md (Rule 23).
- **"sourcesConsulted ≥2 with excerpts"** ≈ Rule 22's SDK-PROBE evidence rows (for third-party
  surfaces — the place where citations are load-bearing).

**COMPLEMENTS (real gaps — cross-checked against BACKLOG + honesty audit):**
- **Contract-first authoring for first-party boundaries** (narrowed W2). Nothing today forces
  the DTO/type/schema MIU to be written and approved before its consumers. → MIU-A.
- **Mutation testing** as a mechanical Rule-19 backstop — genuinely new enforcement; nothing
  in validate/review detects tautological test rewrites mechanically today. → MIU-B.
- **Explicit quality-goals axis** (the multi-goal scoring idea, minus the JSON scoring
  ceremony). SPEC.md has Success Criteria but no forced quality/NFR axis. → MIU-C.
- **Mechanical validation of agent output format** (the schema-validation *idea*, applied to
  the tracked markdown the repo actually uses, not to new JSON). → MIU-D.
- Note: the honesty-audit gaps (co-review/verify-visual/setup-machine never run, BACKLOG #7–9)
  are *not* addressed by anything in the plan — it would add more never-run surface, not less.

---

## 4. Core ideas on their merits

**(a) ≤25-LOC parallel MIUs.** Does not survive Claude Code's execution model.
- *Context economics*: each unit-implementer subagent must load contracts + conventions +
  neighboring code; for a 25-LOC output the fixed context cost dominates. The plan's own cited
  source reports >$10/task for large agent groups; it budgets model tiers but not context.
- *Merge reality*: the plan's own worked example puts MIU-0001 and MIU-0002 in the *same file*
  (`password.ts`) and dispatches them "in parallel". Parallel subagents editing one file need
  per-agent worktrees + a merge step the plan never specifies; without it, this is a conflict
  generator.
- *Gate amplification*: per-MIU commit → post-commit AUTO-REVIEW DIRECTIVE + Stop-hook blessing
  churn on every 12-line unit. The current pipeline's per-commit machinery is priced for
  feature-slice MIUs.
- *Granularity regression*: "one pure function" re-legalizes the "DTO-only" unit the current
  skill bans for good reason (not independently functional/testable). The 25-LOC cap optimizes
  the wrong variable: MIU quality failures on record (the workspace-package incident) were
  *build-context* failures, invisible to a LOC budget.
- Salvage: the *dependency DAG* is already in the current format (`Depends on:` field, tech-lead
  refuses cycles). Batched sequential execution of independent MIUs is available today without
  any redesign.

**(b) Schema-validated JSON artifacts between phases.** Right instinct, wrong substrate.
- The enforcement *idea* (machine-checkable, non-prose gates) is sound and matches the repo's
  own trajectory (hooks made Rules 2/5/8 deterministic).
- But: Zod validation implies a Node orchestrator runtime the plugin doesn't have (it is
  markdown prompts + bash hooks); gitignored JSON as truth contradicts the doc-writer model
  and failed once already (S9); and JSON artifacts are unreadable by the humans who approve
  G1–G4. The tracked-markdown philosophy is not an accident — it is the fresh-clone handoff
  contract.
- Adaptation: validate the *existing* markdown mechanically (grep/awk in a step or hook) —
  the tech-lead checklist is already a schema in prose; make it executable (MIU-D).

**(c) 7 phases vs 12 + G1–G4.** Mostly a rename, partly scope creep, one real insertion.
- Rename: Intake≈Phase 1.0+1.1, Architect≈Phase 4, Skeletons+units≈Phase 5 breakdown + Phase 7
  TDD, Assembly≈Phases 7.5/8/8.x, its G6≈G5. The claimed "collapse of seven kinds of thinking
  into Phase 4" is inaccurate: architecture (P4), decomposition (P5), and test design (P6) are
  already separate phases with separate agents and two gates (G3, G4) between them.
- Scope creep: Scaffolding (spec-forge's job), Knowledge Curator, orchestrator.
- Real insertion: a contracts-before-consumers discipline. That is worth ~30 lines of skill
  text, not a phase, an agent, and a dependency-cruiser gate.

---

## 5. Adapted implementation — 4 MIUs, ratchet-gated, ordered by value/risk

Sequence AFTER the current BACKLOG items 1–3 (hotfix/deliver encoding gaps outrank all of this
on expected score impact). One MIU per ratchet round; revert on non-improvement.

```
MIU-A: Contract-first MIU ordering rule
  Block: INFRASTRUCTURE (plugin docs)   Type: modify-existing   Depends: none
  Files: skills/miu-methodology/SKILL.md, agents/tech-lead.md
  What: (1) tech-lead checklist gains: "MIUs that define first-party contracts (DTOs, shared
    types, zod schemas, API shapes) MUST precede their consumer MIUs in the DAG; every
    cross-boundary MIU names its contract file in `What it does`." (2) SKILL.md gains a
    'Contract-source rule' subsection + one granularity example. NO new phase, NO LOC caps,
    NO change to the 8 fields.
  Build/Deploy impact: none (prompt-only).
  Test plan: eval T01 (vague feature → decomposition order) and T04 (frontend delivery)
    re-run; judge should see contract MIU ordered first; D2/D3 movement expected.
  Done when: ratchet KEEP on T01+T04 mean; tech-lead output in transcript shows the ordering.

MIU-B: Mutation-testing backstop for Rule 19
  Block: INFRASTRUCTURE   Type: modify-existing   Depends: none
  Files: commands/validate.md, docs/RULES.md (Rule 19 body), CHANGELOG.md
  What: validate gains an OPT-IN step — when the diff REWRITES existing test assertions
    (detected via `git diff -- '*.spec.*' '*.test.*'` showing changed `expect` lines) AND
    Stryker is configured in the repo, run mutation tests scoped to changed files; surface
    score, flag <70% as a review finding (not a hard block initially). Rule 19 body references it.
  Build/Deploy impact: none in the plugin; consumer repos opt in by having Stryker.
  Test plan: eval T03 (business bug), T09 (quick-fix trap), T10 (dead-code removal) — the
    three tasks whose traps involve test rewrites; judge D6/D7.
  Done when: ratchet KEEP on T03+T09+T10 mean; step fires only on assertion-rewrite diffs.

MIU-C: Quality-goals axis in the SPEC
  Block: INFRASTRUCTURE   Type: modify-existing   Depends: none
  Files: skills/spec-elicitor/SKILL.md, commands/verify-traceability.md
  What: Mode A adds a 6th section "Quality criteria" (measurable NFRs: rate limits, audit
    logging, perf budgets — each with a measurable criterion); verify-traceability traces
    quality criteria alongside acceptance criteria. This is the plan's multi-goal idea minus
    the 0–2 JSON scoring ceremony.
  Build/Deploy impact: none.
  Test plan: eval T01, T08 (the elicitation tasks); judge D2 (delegation quality) + D7.
  Done when: ratchet KEEP on T01+T08; SPEC.md in transcript contains the section; 8.6 traces it.

MIU-D: Mechanical MIU-format validation (schema idea, markdown substrate)
  Block: INFRASTRUCTURE   Type: new-file + modify-existing   Depends: MIU-A (validates its rule too)
  Files: tools/validate-miu-breakdown.sh, commands/implement.md (STEP 0 calls it)
  What: a bash validator over docs/<feature>/<feature>-miu-breakdown.md asserting the 8
    fields exist per MIU, Files ≤3, Depends form a DAG (no forward refs), Build/Deploy field
    stated, contract-MIU ordering (MIU-A). Exit 1 with named misses. Replaces prose-checklist
    hope with a deterministic check — the plan's §5.1 value at zero new runtime.
  Build/Deploy impact: plugin ships a shell script; no node dependency.
  Test plan: unit-test the script against 3 fixture breakdowns (valid / missing-field /
    cyclic); eval T01, T04, T07 (breakdown-producing tasks).
  Done when: script tested standalone; ratchet KEEP on T01+T04+T07 mean.
```

---

## 6. Explicitly do NOT build

| Item | Why not |
|---|---|
| `tools/orchestrator/` (LangGraph/XState state machine) | New runtime, new failure surface, zero eval coverage; the "state machine" already exists as command flows + hooks, and those are what the judge scores. |
| 7 new agents (intake/scaffolding/contract/skeleton/unit/assembler/curator) | Multiplies the never-run-spec pathology (BACKLOG #7–10); intake≈spec-elicitor, reviewer≈Rule 8, assembler≈validate/deliver, scaffolding=spec-forge. |
| `artifacts/` + `schemas/` (gitignored JSON truth) | Contradicts the tracked-docs handoff contract; the repo already deprecated exactly this pattern (`miu-progress.json`). |
| ≤25-LOC MIU redefinition + SKILL.md rewrite | §4a. Deletes the Build/Deploy field (a real-incident scar), re-legalizes banned granularity, invalidates downstream consumers and eval ground truth. |
| Parallel unit-implementer subagents + topological scheduler | §4a: context cost, same-file merge conflicts (in the plan's own example), per-commit gate churn. Revisit only if a real bottleneck is *measured*. |
| `playbooks/` + retrospectives embeddings + Knowledge Curator | Duplicates engineering-craft loop + skill-router + context7. One fact, one home: new lessons go through consolidate-lessons. |
| G0–G6 renumber + v1/v2 dual pipelines | Breaks frozen TASKS/RUBRIC ground truth; violates Rule 14 and the one-change-one-delta eval discipline. |
| Module Skeletons phase (`throw new Error("Pending MIU")` stubs) | Anti-TDD: mass not-implemented stubs make the red phase meaningless and leave the repo full of compiling-but-lying surfaces between phases. The current red-green loop per MIU is stricter. |
| Scaffolding phase | spec-forge's job; the sibling split is a deliberate, documented boundary. |
| Weekly curator PRs / retrospective automation | Automation of a loop (consolidate-lessons) that already has a manual cadence and no evidence of being the bottleneck. |

**Bottom line:** the plan is a thoughtful design for a plugin that no longer exists. Its four
transplantable organs are listed in §5; everything else should be declined with this document
as the record, so the decision isn't re-litigated (the repo's own rationale-capture rule,
applied to itself).
