---
description: Refactor proposal — analyzes a module/domain and produces a PROPOSAL document (never silently rewrites working code). Accepted proposals are queued into the normal pipeline flow (plan → MIU → review → test → deliver).
---

# Development Pipeline: Refactor (Propose-Only)

You are producing a **refactor proposal**, not a patch. Do NOT edit source files in this command. The output is a markdown document the user triages.

All steps are pre-approved. Run to completion.

---

## STEP 0: Scope

Ask ONCE (if not given):
- Target path (single module / directory / domain). Default: largest module in `src/` with recent churn.
- Focus tags (any subset): `style`, `typescript`, `performance`, `maintainability`, `extensibility`, `architecture`. Default: all except `architecture`.

Refuse whole-repo sweeps here — those route to the scheduled refactor task instead.

Load `skills/code-refactor/SKILL.md` for scoring rubrics and rewrite patterns.

---

## STEP 1: Read the Living Docs

Read `.claude/docs/ARCHITECTURE.md` + `RECENT_CHANGES.md` before any analysis. Never refactor blind — understand why the code is shaped the way it is.

---

## STEP 2: Parallel Analysis Sweep

Launch analyzers in parallel (use the Agent tool, 4 concurrent):

1. **TypeScript analyzer** — strictness gaps, `any` leaks, missing narrowing, weak generics, discriminated-union opportunities.
2. **Clean-code analyzer** — dead code, duplicated logic, long functions (>50 lines), deep nesting (>4), unclear naming, comment/code drift.
3. **Performance analyzer** — React re-render hotspots, unbatched state, N+1 calls, unnecessary useEffect, missing memoization where justified, bundle impact.
4. **Extensibility analyzer** — hardcoded branches that should be tables, closed-for-extension modules, coupling between layers, missing boundaries.

(Architecture analyzer runs ONLY if `architecture` was in focus tags and the user explicitly opted in.)

Each analyzer returns findings in this shape:
```
- id: R-<analyzer>-<n>
  severity: S1 | S2 | S3
  title: ...
  location: path:line
  why: (1–2 lines, what breaks or costs without this change)
  sketch: (5–20 line code snippet of the proposed shape)
  risk: low | medium | high
  effort: XS | S | M | L
```

---

## STEP 3: Aggregate + Rank

Merge findings, dedupe, rank by `(severity_weight × 1/risk × 1/effort)`.

Drop anything whose risk outweighs the benefit (e.g. rewriting a 200-line stable module to save 2 lines).

---

## STEP 4: Write the Proposal Document

Path: `.claude/refactor-proposals/<YYYY-MM-DD>-<target-slug>.md`

Structure:
```
# Refactor Proposal: <target>

Scope: <path>
Generated: <iso timestamp>
Head: <git sha>

## Summary
<3-bullet TL;DR>

## Accepted Risks
<what will NOT be refactored and why>

## Proposals

### R-typescript-1 — <title>  [S1 · low-risk · XS]
Location: `src/foo/bar.ts:42`
**Why:** ...
**Sketch:**
\`\`\`ts
...
\`\`\`
**Routes to:** MIU-refactor-<n>

(repeat for each proposal)

## Architectural Concerns (if any)
> Flagged — requires explicit user approval before queuing. Do NOT auto-route.

## How to Accept
Reply with the proposal IDs to queue, e.g. `accept R-typescript-1, R-clean-3`.
Accepted items become MIUs and run through the standard pipeline.
```

---

## STEP 5: Present + Wait

Print the proposal path and a one-screen summary table to the user. Then STOP.

Do NOT:
- Edit any source file.
- Create a branch.
- Commit anything.
- "Just fix the easy ones."

Wait for the user to respond with accept IDs.

---

## STEP 6: On Acceptance — Queue MIUs

When the user replies with accept IDs:
1. For each accepted proposal, create an MIU entry using the 8-field format from `skills/miu-methodology/SKILL.md`.
2. Append MIUs to `.claude/miu-progress.json` under a new product task `refactor/<target-slug>`.
3. Announce: *"N MIUs queued. Invoking `/dev-pipeline:pipeline` to execute."*
4. Invoke `/dev-pipeline:pipeline` — implementation, review, and delivery happen through the normal gates.

Architectural proposals, even if the user says "accept", require an explicit **"I approve the architectural change to X"** statement before queuing.

---

## Hard Rules (non-negotiable)

- Never refactor mid-feature. Run only on clean `main` or a dedicated refactor branch.
- Never bundle refactor changes with feature changes in the same PR.
- Every accepted refactor goes through review + tests. No "it's just a cleanup" skips.
- If the proposal document would be empty, say so and exit — don't invent work.
