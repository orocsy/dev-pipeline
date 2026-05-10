---
name: code-refactor
description: Analyze code and produce refactor PROPOSALS across TypeScript rigor, clean-code hygiene, performance, extensibility, and (gated) architecture. Auto-loads when /dev-pipeline:refactor runs or when a user request is classified as REFACTOR_PROPOSAL. Never rewrites working code silently — always outputs a triage document.
---

# Code Refactor Skill

## Activation Banner (print exactly once when this skill loads)

```
🔧 [dev-pipeline] skill: code-refactor — refactor analysis engine active
   Mode: PROPOSE ONLY — no source files will be modified
   Analyzers: typescript | clean-code | performance | extensibility | [architecture: gated]
```

---

This skill is the **analysis brain** behind `/dev-pipeline:refactor`. It defines what to look for, how to score findings, and how to write a proposal the user can triage with confidence.

**Non-negotiable:** This skill does NOT apply changes. It emits findings. The command writes the proposal doc; accepted items route through the normal MIU pipeline.

---

## When This Skill Fires

- `/dev-pipeline:refactor` invocation.
- User request classified as `REFACTOR_PROPOSAL` ("clean this up", "simplify", "modernize", "improve").
- Scheduled daily refactor task (see `schedule` skill).
- Post-delivery one-shot, if `/dev-pipeline:deliver` offered it and the user accepted.

Never fires mid-feature. Never fires on a dirty working tree.

---

## Analysis Dimensions

Five analyzers, run in parallel via the Agent tool. Each has its own rubric.

### 1. TypeScript Rigor (S1 issues block future features)

Look for:
- `any` / `unknown` without narrowing, especially at module boundaries.
- Implicit `any` via missing return types on exported functions.
- Type assertions (`as X`) where a user-defined type guard would be safer.
- Missing discriminated unions on "kind"/"type" field objects.
- Generics defined but never constrained (`<T>` instead of `<T extends ...>`).
- `Pick`/`Omit` used where a dedicated type would document intent better.
- Non-exhaustive `switch` without `never`-check default.
- Enum usage where a const object + union would be leaner.
- `Function` / `Object` / `{}` types leaking through.
- Non-readonly arrays/records passed across module boundaries.

Rubric: **S1** if it enables runtime-only bugs, **S2** if it reduces refactor safety, **S3** if purely stylistic.

### 2. Clean-Code Hygiene

Look for:
- Functions >50 lines or cyclomatic complexity >10.
- Nesting depth >4.
- Duplicated logic (>5 lines repeated in 2+ places).
- Dead code / unused exports (use `knip`, `ts-prune`).
- Comments that restate code or are stale vs. behavior.
- Boolean parameters that should be enums ("flag arguments").
- Primitive obsession (string IDs where branded types would help).
- Classes where a module of pure functions would be clearer.
- Unclear names (`data`, `info`, `handle`, `process`).

Rubric: **S1** for duplication causing divergent bug fixes, **S2** for readability-heavy items, **S3** for naming-only.

### 3. Performance

Look for (framework-aware — load the relevant tech skill first):
- React: missing `memo`/`useMemo`/`useCallback` where props cascade, state that could be derived, `useEffect` that should be an event handler, unstable keys in lists, unbatched setState calls.
- Node: synchronous fs in hot paths, unbounded Promise.all over user input, N+1 DB queries, JSON.parse on large payloads without streaming.
- Bundle: `lodash` full import vs `lodash-es`, `moment` → `date-fns`/`dayjs`, full-icon-library imports, duplicated polyfills.
- Algorithmic: O(n²) where O(n) is trivial, Array methods in hot loops creating garbage.

Quantify where possible: measured render count, bundle-size delta, request latency. Don't propose perf work without evidence.

Rubric: **S1** if user-visible (>100ms added latency or jank), **S2** if infra cost (unnecessary re-renders, extra DB queries), **S3** for micro-optimizations (skip unless clustered).

### 4. Extensibility

Look for:
- `switch`/`if` ladders over a fixed enum that should be a lookup table.
- Hardcoded strings in logic that should be config/const.
- Modules with more than one axis of change (violates SRP).
- Cross-layer imports (UI reaching into DB layer, etc.).
- Missing seams where mocking is needed (hardcoded `new Foo()` instead of DI).
- Public API surface that leaks internals.

Rubric: **S1** if blocking a known upcoming feature, **S2** if likely to block within 1–2 sprints, **S3** speculative.

Speculative extensibility (S3) is NOT proposed unless user explicitly asked. "YAGNI" is a hard default.

### 5. Architecture (gated — only runs if user opted in)

Look for:
- Module boundaries that no longer match data flow.
- State duplicated across stores/contexts.
- Request path that fans out across too many layers (4+ hops).
- Framework-fighting patterns (e.g. manual routing on Next.js, custom state where server state belongs in React Query).
- Coupling preventing independent deploy/test of a domain.

Every finding here is tagged **Requires Architectural Review** and does NOT auto-queue even if accepted. The user must explicitly approve each one.

---

## Finding Format (strict — the command parses this)

```yaml
- id: R-<analyzer>-<n>      # e.g. R-typescript-1
  severity: S1 | S2 | S3
  title: <one line>
  location: <path:line>      # or path:line-line for ranges
  why: |
    1–3 lines. What breaks or what it costs without this change.
    Cite evidence (benchmark, type error, duplication count).
  sketch: |
    ```ts
    // 5–20 lines of the PROPOSED shape, not the current shape.
    ```
  risk: low | medium | high
  effort: XS | S | M | L
  routes_to: MIU-refactor-<n>  # filled by command, not analyzer
```

**Quality gate per finding:**
- If you cannot write a concrete sketch, the finding is not actionable — drop it.
- If the sketch is longer than 20 lines, the finding is too big — split it.
- If risk is `high` and effort is `L`, require architectural approval.

---

## Scoring & Selection

Score = `severity_weight / (risk_weight × effort_weight)`

| dimension | weight |
|---|---|
| S1 | 9 |
| S2 | 4 |
| S3 | 1 |
| low risk | 1 |
| medium risk | 2 |
| high risk | 4 |
| XS / S effort | 1 |
| M effort | 2 |
| L effort | 4 |

Include any finding with score ≥ 1. Cluster small S3 items of the same theme into one batched finding.

---

## Cross-Skill Coordination

Before emitting findings, consult:
- `skills/project-detector` — what stack? A React-specific memo proposal is invalid on a Vue project.
- `skills/skill-router` — does a tech-stack skill (e.g. `vercel-react`, `nestjs-best-practices`) already have a canonical pattern? Cite it.
- Existing ADRs in `.claude/docs/` — never propose reverting a decision the user explicitly made unless flagged as architectural review.

---

## Anti-Patterns (things this skill must NOT do)

- **Silent rewrites.** If you catch yourself using the Edit tool during refactor analysis, STOP.
- **Nit storms.** A proposal with 40 S3 style-only findings and zero S1/S2 is spam. Cap S3 findings at 10% of total or drop them.
- **Framework churn.** "Migrate from Zustand to Jotai" is not a refactor — it's a rewrite. Flag as architectural.
- **Test refactoring alongside code refactoring.** Test suite changes belong in their own proposal pass.
- **Cross-module refactors without boundary analysis.** If a proposal touches >3 modules, escalate to architectural review.

---

## Output Location

Findings are returned to `/dev-pipeline:refactor` which writes the proposal to:

```
.claude/refactor-proposals/<YYYY-MM-DD>-<slug>.md
```

Accepted findings become MIUs under the product task `refactor/<slug>` and run through the standard pipeline. Every accepted refactor is reviewed and tested exactly like a feature — no exceptions.
