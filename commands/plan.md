---
description: Plan and design a feature with multi-agent requirements analysis, architecture, and MIU breakdown
argument-hint: [feature-description]
---

# Development Pipeline: Plan Phase

You are running the **planning phases** (1-6) of the development pipeline. This produces an approved architecture + MIU breakdown WITHOUT writing code.

Feature request: $ARGUMENTS

---

## PHASE 1: Requirements Analysis

**Role: Product Owner / BA**

Before starting, invoke `@planning-with-files` to initialize persistent planning files:
- Create `task_plan.md` with feature phases and checkboxes
- Create `findings.md` for research discoveries
- Create `progress.md` for session logging

### PHASE 1.0: Spec Elicitation (NEW — gates Phase 1 entry)

**Check first**: did the user provide a structured SPEC, PRD, or design doc with the request — or just a one-line idea?

- If `$ARGUMENTS` is a path to an existing SPEC/PRD file, or contains a multi-paragraph structured spec → SKIP to Phase 1.1.
- If `docs/<feature-slug>/SPEC.md` already exists for this feature → READ it and SKIP to Phase 1.1.
- If the request is a **self-evident technical fault** — a stack trace, `TypeError`, compile/lint/test failure, a crash, a 500 with an obvious cause (per the business-vs-technical test in `skills/spec-elicitor/SKILL.md` → "When to run me") — → SKIP elicitation, but write a minimal `docs/<slug>/ISSUE.md` (3 lines — **Symptom**, **Repro** if known, **Done when**) as the traceability anchor. Phase 1.1 uses it as primary input and Phase 8.6 traces against it in place of a SPEC.
- Otherwise (raw sentence / vague idea / "I want to build…" / "我要做…" / a business-behavioural report whose correct behaviour is itself undecided) → invoke the **`dev-pipeline:spec-elicitor`** skill via the Skill tool BEFORE anything else. It walks the user Socratically through six sections (Problem / Solution / Constraints / Non-goals / Success Criteria / Quality Criteria) and writes `docs/<slug>/SPEC.md`. Wait for that to complete. Once written, use it as the input to Phase 1.1.

Do NOT skip the elicitor for "small" features — the SPEC is what makes Phase 8.6 traceability work. A 4-turn elicitation is cheaper than a wrong implementation.

> *Whether* a request needs clarification at all is governed by the canonical business-vs-technical test in `skills/spec-elicitor/SKILL.md` → "When to run me" (and `CLAUDE.md` Rule 23). A brand-new feature almost always does (Mode A — full SPEC); the test mainly gates the lighter `fix` / `update` flows, which use Scope-Lock (Mode B).

### PHASE 1.1: Codebase Analysis

Launch 1-2 **requirements-analyst** agents (with the SPEC.md as their primary input, not the raw user sentence) to:
- Explore the codebase for related features and patterns
- Read all CLAUDE.md files for applicable rules
- Identify open questions and ambiguities NOT covered by the SPEC
- List 5-10 key files to read

After agents return:
1. **Save findings to `findings.md`** (2-Action Rule: save after every 2 research ops)
2. Read all key files they identified
3. Present feature understanding summary
4. Present any remaining open questions (the SPEC should have closed most)
5. **ASK USER** to clarify any ambiguities the SPEC didn't cover

---

## PHASE 2: Skill Discovery & Tech Stack Detection

**Role: Tooling Specialist**

Launch the **skill-scout** agent to:
- Auto-detect tech stack from package.json, configs, project structure
- Build Tech Stack Profile
- Map detected technologies to installed skills
- Identify gaps and recommend Context7 fallback

Present findings. **Save to `findings.md`.**

If gaps found, **ASK USER** if they want to install recommended skills.

---

## PHASE 3: Design Check

**Role: Design Gatekeeper**

Launch the **design-checker** agent.

- If **YES** and no designs exist: Tell the user to run `/ui-ux-pro-max` + `/web-design-guidelines`. **PAUSE.**
- If **NO** or designs exist: proceed.

---

## PHASE 4: Technical Design

**Role: Senior Architect**

Invoke `@writing-plans` for structured plan decomposition methodology.

Launch the **technical-architect** agent with:
- Requirements from Phase 1
- CLAUDE.md rules
- Key files and patterns found

The architect verifies every third-party surface the design depends on via context7 + (if installed) the package's own types (CLAUDE.md Rule 22) BEFORE finalizing — not satisfied by "I recall how this SDK works."

Present architecture design, INCLUDING the "Third-Party Surfaces Verified" table:
- Component design with file paths
- Data flow
- Trade-offs considered

**ASK USER** to approve architecture.

---

## PHASE 5: Module & Task Breakdown

**Role: Tech Lead**

Continue using `@writing-plans` for chunk-based decomposition.

Launch the **tech-lead** agent with approved architecture to:
- Break into logical modules
- Create ordered MIU list
- Define dependencies and success criteria

Present MIU plan. **ASK USER** to approve.

---

## PHASE 6: Test Planning

**Role: QA Lead**

Launch the **test-planner** agent to enumerate ALL test scenarios:
- Unit tests (happy path, errors, edge cases, locales, statuses)
- E2E tests (user journeys)
- Multi-tenancy isolation tests

Present test scenarios. User reviews and approves.

---

## OUTPUT

Save the approved plan to `.claude/plans/current-feature.md` containing:
1. Feature requirements (from Phase 1)
2. Tech stack profile + recommended skills (from Phase 2)
3. Architecture design (from Phase 4)
4. MIU breakdown with dependencies (from Phase 5)
5. Test scenarios per MIU (from Phase 6)

Update `task_plan.md` with all phases marked complete.

Tell the user: "Plan complete. Run `/dev-pipeline:implement` to start TDD implementation."

---

## Ground Rules

1. **Ask before proceeding** at every gate
2. **Save findings to disk** after every 2 research operations
3. **No code writing** — this command is planning only
4. **Track progress** with TodoWrite throughout
5. **Tenant safety** — verify all queries include tenantId in architecture
