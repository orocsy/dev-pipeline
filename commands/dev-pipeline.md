---
description: Full feature development pipeline with multi-agent engineering team
argument-hint: [feature-description]
---

# Development Pipeline

You are orchestrating a complete feature development workflow that simulates an engineering team. Each phase uses specialized agents. Follow the phases IN ORDER. Never skip phases. Ask the user for approval only at the 4 defined GATES (G1-G4). Everything else runs autonomously.

Feature request: $ARGUMENTS

---

## PHASE 0: Smart Detection (silent, automatic — no user interaction)

Run `/dev-pipeline:detect` before anything else.
Outputs `.claude/project-context.json` with: project type, deploy targets, skill mapping, design source, git hooks status.
Print one-line summary only, then immediately continue to Phase 1.

---

## PHASE 1: Requirements Analysis

**Role: Product Owner / BA**

Invoke `@planning-with-files` to initialize persistent planning files:
- Create `task_plan.md` with feature phases and checkboxes
- Create `findings.md` for research discoveries
- Create `progress.md` for session logging

### PHASE 1.0: Spec Elicitation (NEW — gates Phase 1 entry)

**Check first**: did the user provide a structured SPEC, PRD, or design doc — or just a one-line idea?

- If `$ARGUMENTS` is a path to an existing SPEC/PRD, or contains a multi-paragraph structured spec → SKIP to Phase 1.1.
- If `docs/<feature-slug>/SPEC.md` already exists for this feature → READ it and SKIP to Phase 1.1.
- If the request is a **self-evident technical fault** — a stack trace, `TypeError`, compile/lint/test failure, a crash, a 500 with an obvious cause (per the business-vs-technical test in `skills/spec-elicitor/SKILL.md` → "When to run me") — → SKIP elicitation, but do NOT skip the traceability anchor: write a minimal `docs/<slug>/ISSUE.md` (3 lines — **Symptom** as reported, **Repro** if known, **Done when**: e.g. "the 500 no longer occurs under X; regression test added"). Takes seconds, and it is what Phase 1.1 uses as primary input and what Phase 8.6 (verify-traceability) traces against in place of a SPEC — without it, 8.6 blocks at the end of the pipeline for lack of any spec. (This is why `BUG_FIX_COMPLEX` routes to this command in CLAUDE.md's routing table — a technical bug must NOT be forced through full-SPEC elicitation, but it still needs a done-when.)
- Otherwise (raw sentence / vague idea / "I want to build…" / "我要做…" / a business-behavioural report whose correct behaviour is itself undecided) → invoke the **`dev-pipeline:spec-elicitor`** skill via the Skill tool BEFORE anything else. It Socratically walks the user through six sections (Problem / Solution / Constraints / Non-goals / Success Criteria / Quality Criteria) one question at a time and writes `docs/<slug>/SPEC.md`. Wait for that to complete. The SPEC becomes the input to Phase 1.1.

Do NOT skip the elicitor for "small" features — Phase 8.6 (verify-traceability) re-reads this SPEC to check every acceptance criterion shipped. No SPEC = no traceability check possible.

> *Whether* a request needs clarification at all is governed by the canonical business-vs-technical test in `skills/spec-elicitor/SKILL.md` → "When to run me" (and `CLAUDE.md` Rule 23). A brand-new feature almost always does (Mode A — full SPEC); the test mainly gates the lighter `fix` / `update` flows, which use Scope-Lock (Mode B).

### PHASE 1.1: Codebase Analysis

Launch 1-2 **requirements-analyst** agents (with the SPEC.md as their primary input, not the raw user sentence) to:
- Explore the codebase for related features and patterns
- Read all CLAUDE.md files for applicable rules
- Identify open questions and ambiguities NOT covered by the SPEC
- Report **Blindspot findings** — surfaces the change touches per the codebase but the SPEC never mentions (stage 2 of the blindspot loop; stage 1 was the elicitor's code-blind pass)
- List 5-10 key files to read

After agents return:
1. **Save findings to `findings.md`** (2-Action Rule: save after every 2 research ops)
2. Read all key files they identified to build deep understanding
3. Present the feature understanding summary to the user
4. Present any remaining open questions (the SPEC should have closed most)
5. **Present the analysts' Blindspot findings as decide-or-defer questions.** If a round yields new decisions, re-check for surfaces those decisions open and loop — **max 2 loops** — until a round yields no new decisions. Record every outcome into the SPEC's `## 7. Blindspots considered` appendix: Decided → fold into the relevant SPEC section; Deferred → list as out of scope (exempt from Phase 8.6 tracing).
6. **ASK USER** to clarify any ambiguities the SPEC didn't cover
7. Update the todo list with all phases

---

## PHASE 2: Skill Discovery & Tech Stack Detection

**Role: Tooling Specialist**

Launch the **skill-scout** agent to:
- **Auto-detect the project's tech stack** from package.json files, config files, and project structure
- Build a Tech Stack Profile (runtime, frameworks, ORMs, databases, testing, messaging, containerization)
- Map detected technologies to installed skills using the detection table
- Audit currently installed plugins and skills
- Identify which are relevant to this task
- Recommend any missing skills that would help
- Flag unmatched technologies with Context7 fallback strategy

Present findings including:
1. **Tech Stack Profile** — what was detected
2. **Recommended Skills** — which skills to activate for this task (with HIGH/MEDIUM/LOW relevance)
3. **Best-Practice Sources** — the stack-matched sources resolved by Phase 0's detect (pinned in `.claude/project-context.json` → `bestPracticeSources[]`, per the mapping in `skills/skill-router/SKILL.md`), each marked installed/missing with its fallback
4. **Unmatched Technologies** — what needs Context7 on-demand docs

**Store the Recommended Skills list** — it will be used in Phase 4 (architecture) and Phase 7 (implementation).

Present findings. **Save to `findings.md`.**

If gaps found, **ASK USER** if they want to install recommended skills before continuing.

---

## PHASE 3: UI Design (EXECUTED — never "go run it yourself")

**Role: Design Lead**

This phase RUNS the design work in-pipeline. The old behavior — pausing and
telling the user to run `/ui-ux-pro-max` + `/web-design-guidelines` manually —
is retired: those may not even be installed, and a paused pipeline is a
dropped pipeline.

**3.1 Gate.** Launch the **design-checker** agent to evaluate whether UI/UX
design is required. Backend-only, config, tooling, pure-logic, and
bug-fix-restoring-intended-behavior work returns **NO** → skip 3.2–3.5
ENTIRELY and proceed to Phase 4 at zero design cost — the executed design
work below is for UI-touching features only, never a mandatory toll on
every pipeline run. If designs for this
feature already exist (`docs/<slug>/ui-design.md` or `design/`) → confirm
they still match the SPEC, then proceed to Phase 4.

**3.2 Design foundation (DESIGN.md).** If the repo has NO root `DESIGN.md`
(or equivalent pinned design-system doc): create one BEFORE any feature
design — tokens (color/type/spacing/radii/shadows), primitives inventory,
composition rules, per-surface mix rules — derived from the existing UI if
one exists, or from the design skill's output for greenfield. Every later
design artifact must cite tokens from this file, and new tokens/patterns land
as a DESIGN.md edit in the same PR (the CoachFlow convention).

**3.3 Feature design spec.** Produce `docs/<slug>/ui-design.md` by invoking,
in priority order, the first available (skill-router → "Design-phase
routing" decides; never ask the user which):
1. A provided design asset (Stitch/Figma MCP, image) — translate it.
2. `ui-ux-pro-max` (if installed) — generate the design system/spec for the
   surfaces this feature touches.
3. `frontend-design` (claude-plugins-official — installed default) —
   generate the per-surface spec: layout, states (loading/error/empty/
   success), responsive behavior, DESIGN.md token references.

**3.4 Design audit.** Audit the spec (and any existing UI code it touches)
before implementation: run `web-design-guidelines` if installed; otherwise
apply its checklist areas inline — accessibility (WCAG AA: contrast, focus,
labels, touch targets ≥40px), states completeness, responsive breakpoints,
copy tone. Record findings + resolutions in the spec's "Audit" section.

**3.5 Design gate (G2.5).** Present the spec summary (surfaces, states,
tokens used, audit outcome). **ASK USER** to approve before Phase 4 —
architecture consumes the approved spec, and Phase 8.2 (verify-visual)
compares the shipped pixels against it.

---

## PHASE 4: Technical Design

**Role: Senior Architect**

Invoke `@writing-plans` for structured plan decomposition methodology.

Launch the **technical-architect** agent with:
- Requirements from Phase 1
- CLAUDE.md rules
- Key files and patterns found

The architect verifies every third-party surface the design depends on via context7 + (if installed) the package's own types (CLAUDE.md Rule 22) BEFORE finalizing — not satisfied by "I recall how this SDK works."

Present the architecture design to the user, INCLUDING the "Third-Party Surfaces Verified" table:
- Component design with file paths
- Data flow
- Trade-offs considered

**Surface the pinned best-practice sources as part of this gate** (one block, from `bestPracticeSources[]`):

```
Stack detected: [signals] → these best-practice sources will be active in
implement / review / validate / fix: [installed sources]. Missing (Context7
fallback): [missing sources]. Confirm, or override (drop/add a source).
```

An override here is recorded back into the pin — the later phases read the pin, they never re-decide.

**ASK USER** to approve the architecture before proceeding.

---

## PHASE 5: Module & Task Breakdown

**Role: Tech Lead**

Continue using `@writing-plans` for chunk-based decomposition.

Launch the **tech-lead** agent with the approved architecture to:
- Break into logical modules
- Create ordered MIU list
- Define dependencies and success criteria

Present the MIU plan. **ASK USER** to approve the implementation plan.

---

## PHASE 6: Test Planning

**Role: QA Lead**

Launch the **test-planner** agent to enumerate ALL test scenarios for the MIUs:
- Unit tests (happy path, errors, edge cases, locales, statuses)
- E2E tests (user journeys)
- Multi-tenancy isolation tests

Present test scenarios. User reviews and approves.

---

## PHASE 7: Implementation

**Role: Senior/Staff Engineer (YOU — not an agent)**

Invoke `@test-driven-development` for Iron Law enforcement (red-green-refactor).
Invoke `@planning-with-files` to update `progress.md` after each MIU.

For each MIU in order:

1. **Think aloud** — "I'm working on MIU N: [name]. This is needed because..."
2. **Write failing tests first** — from test-planner's scenarios. Tests MUST fail before implementation.
3. **Implement the code** — make tests pass
4. **Launch validator agent** — verify lint + tsc + unit tests + build
5. **If FAIL** — fix immediately, re-launch validator, loop until clean
6. **Launch code-simplifier agent** — refine code for clarity and consistency
7. **Update progress** — log MIU result to `progress.md`
8. **Mark MIU complete** — transition to next

**Important during implementation:**
- **Activate skills from Phase 2 Recommended Skills list.** For HIGH relevance skills, invoke via Skill tool before implementation. For unmatched technologies, use Context7 MCP (`resolve-library-id` + `query-docs`) for on-demand docs.
- **Consult the pinned best-practice sources** (`bestPracticeSources[]` in `.claude/project-context.json`, confirmed at the Phase 4 gate): before writing code in an MIU, load each `installed` source whose signal matches the files the MIU touches (phase weights in `skills/skill-router/SKILL.md` → "Best-Practice Source Routing"). A `missing` source → annotate and use its recorded fallback; never block on it.
- Installed skills (nestjs-best-practices, mastering-typescript, websocket-engineer, vercel-react-best-practices, vercel-composition-patterns, nodejs-architecture, nodejs-error-handling, nodejs-testing, nodejs-security, nodejs-database-orm, nodejs-docker-production, nodejs-caching-redis) will auto-activate when their descriptions match the task context
- Follow established codebase patterns found in Phase 1
- Honor any project-specific safety rules in `.claude/CLAUDE.md` and `AGENTS.md` (e.g. multi-tenancy, concurrency invariants, i18n) — those are app-specific and live in the project, not here
- No `as any` casts on mock objects — use typed factory functions

---

## PHASE 7.5: API Contract Check (NEW)

Run `/dev-pipeline:verify-contract` if the diff touches both frontend and backend.

This catches the class of bug where the frontend sends fields the backend's
`forbidNonWhitelisted: true` validation rejects → silent 400s. Cheap to run, catches a real category of failure that unit tests miss.

If contract drift is detected, the verify-contract command will report it. Fix before Phase 8.

---

## PHASE 8: Final Validation

Invoke `@verification-before-completion` — fresh evidence before claiming done.

Launch the **validator** agent for the FULL project:
- lint (all apps)
- tsc (all apps)
- unit tests (all apps)
- e2e tests (if configured)
- build (all apps)

**ALL must PASS** before proceeding. If any fail, fix and re-validate.
Do not trust cached results — run commands yourself and read the output.

### PHASE 8.1: Blast-Radius Check (NEW)

Run `/dev-pipeline:verify-blast-radius`. Identifies dependent modules touched indirectly by this change and runs their tests too. Catches the class of bug where a refactor breaks a sibling feature whose tests were never re-run.

### PHASE 8.2: Visual Verification (NEW, when UI changed)

Run `/dev-pipeline:verify-visual` if the diff touches a UI surface. Captures headed-browser screenshots at each meaningful state and compares against the design spec from Phase 3. Catches the class of bug where E2E click-throughs pass but layout/component composition silently drifted.

### PHASE 8.6: Requirements Traceability (NEW)

Run `/dev-pipeline:verify-traceability`. Re-reads Phase 1 requirements + Phase 5 MIU "done when" criteria and asserts each one has a corresponding test or visible code change. Catches the class of bug where a requirement silently drops between design and implementation.

**G5 (NEW): Final ship-confidence gate.** All four verify-* commands must report green before Phase 9. If any return findings, fix in place — do not push.

---

## PHASE 9: Commit & PR

Stage only the files related to this feature (never `git add -A`):
- List changed files with `git status`
- Stage only relevant files
- Exclude any unrelated changes, env files, or credentials

Delegate to `/commit-push-pr` to:
- Create a well-formatted commit
- Push to remote
- Create a pull request

---

## PHASE 10: Code Review

Delegate to `/code-review` to review the PR.

Wait for results. If the review finds issues, proceed to Phase 11. If clean, proceed to Phase 12.

---

## PHASE 11: Fix Cycle

**Role: Senior/Staff Engineer (again)**

Launch the **review-analyzer** agent to parse and prioritize review issues.

For each issue (in priority order):
1. Analyze the issue
2. Fix using MIU methodology (think → test → implement → validate)
3. Launch **validator** agent after each fix
4. Loop until validator passes

After all fixes:
- Stage only fix-related files
- Delegate to `/commit` for the fix commit
- Delegate to `/code-review` for re-review
- **Repeat Phase 11** until review is clean

---

## PHASE 12: Summary & Learning

Present final summary:
- What was built (features, components, files)
- Key architecture decisions made
- Test coverage (scenarios covered)
- Files modified (full list)
- Link to the PR
- Any follow-up items or known limitations

Mark all todos complete.
Update `task_plan.md` with all phases marked complete.

Suggest: "Run `/dev-pipeline:learn` to capture learnings from this session."

---

## Ground Rules (apply to ALL phases)

1. **One MIU at a time** — never batch
2. **Verify after every change** — never assume it works
3. **Ask before proceeding** — at every gate (architecture approval, MIU plan approval, etc.)
4. **Explain the why** — every decision has a reason
5. **No shortcuts** — follow the process even for "simple" changes
6. **Tenant safety** — every query includes tenantId
7. **Track progress** — use TodoWrite throughout
