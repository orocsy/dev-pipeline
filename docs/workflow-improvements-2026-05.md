# Workflow Improvements — 2026-05

> Generic distillation of failure modes seen across multiple real production projects, converted to dev-pipeline upgrades. The actual project history that surfaced these is intentionally NOT included here — this doc must travel with the plugin and stay app-agnostic.

## Why this doc exists

Across multiple real projects, recurring classes of bug kept costing fix commits:

- ~70% caught by code review or manual visual inspection
- ~10% caught by E2E tests
- ~10% reached production
- ~10% caught by unit tests

That distribution is the failure mode: review and visual inspection were doing work the pipeline should do automatically. This doc records the workflow upgrades that close those gaps.

## Recurring failure classes (process-level, app-agnostic)

| # | Class | What happens | What it costs |
|---|---|---|---|
| 1 | **Tests pass ≠ ships clean** | 185 unit tests green, but every controller endpoint returned 404 because of a route-prefix doubling. Caught only by review. | Whole feature broken at HTTP layer until reviewed |
| 2 | **Selector / DTO drift after refactor** | Component renamed; tests using old selectors silently passed because they no longer matched any element. Or: backend DTO field renamed; frontend still sends old name; `forbidNonWhitelisted` rejects with 400 at runtime. | Silent regressions that ship |
| 3 | **Environment-dependent code passes on dev's UTC machine, breaks on user's TZ** | `parseISO` assumed UTC; broke in non-UTC user environments. | Production incidents |
| 4 | **Library reinvented as regex** | Hand-rolled hex-color / URL-host / date-string regex when `class-validator @IsHexColor()`, `new URL()`, and `date-fns-tz` already exist. | Multiple review rounds, all same root cause |
| 5 | **Design says A, implementation does B** | Phone component spec'd as country-prefix dropdown + national number; shipped as single text input. Click-throughs pass; visual inspection caught it. | Silent requirement drop |
| 6 | **Codegen at install-time forgotten in Docker** | `prisma generate` runs in `pnpm install` postinstall locally, but Dockerfile copied schema AFTER `pnpm install` so codegen failed silently. | Failed deploys |
| 7 | **Headless E2E gives false confidence** | Tests pass headless, but a real human watching headed would have seen the layout broken or a button missing. | Visual bugs ship |
| 8 | **Test name describes intent that doesn't match assertion** | E2E "expired token returns 410" actually exercised the unknown-token (404) path. Test passed. | False confidence |

## Workflow upgrades shipped

### 1. Four new verify-* commands (already added)

| Command | Catches |
|---|---|
| `/dev-pipeline:verify-contract` | Frontend payload shape vs backend DTO drift (class 2) |
| `/dev-pipeline:verify-blast-radius` | Refactors that break sibling features whose tests weren't re-run (class 2) |
| `/dev-pipeline:verify-visual` | Design-implementation drift (class 5, 7) |
| `/dev-pipeline:verify-traceability` | Requirements that silently disappeared between Phase 1 spec and Phase 7 code (class 5, 8) |

These are wired into `/dev-pipeline:pipeline` at Phase 7.5 and Phase 8 sub-steps. A new G5 ship-confidence gate requires all four green before Phase 9.

### 2. spec-forge sibling tool (NEW project bootstrap)

A new decoupled scaffolder lives at `~/Desktop/projects/spec-forge`. It encodes prevention for ~22 known classes of bug into integration manifests, with regression assertions. Used by the new `/dev-pipeline:scaffold-from-prd` command.

`spec-forge` is OPTIONAL — dev-pipeline works fine without it. Communicates only via `spec.json` files + CLI. Each tool versions independently.

### 3. Library-first reflex (now in PREFLIGHT_CHECKLIST.md)

When a class of bug is "I hand-rolled X instead of using lib Y," the answer is never the next regex. The answer is to revisit prior art. Concrete domains: hex / URL / date / phone / JSON. See `~/Desktop/projects/spec-forge/PREFLIGHT_CHECKLIST.md`.

### 4. Environment-invariance test pattern (now in spec-forge `vitest` integration)

Sample test ships with `vi.stubEnv('TZ', …) × 3 zones`. Catches class 3.

### 5. Headed-default Playwright (now in spec-forge `playwright-e2e` integration)

Local dev runs headed; CI runs headless via `PLAYWRIGHT_HEADLESS=1`. Plus a `step()` helper that attaches a screenshot per call so the trace viewer becomes a flip-book. Catches classes 5 and 7.

### 6. Doc-update guard (now in spec-forge `git-hooks` integration)

`pre-push` hook blocks pushes that ship substantive code without a `*.md` tick. Override is audit-logged. Class-cross-cutting — every recurring failure has a documentation gap upstream.

## What's NOT in scope for these upgrades

App-domain rules (multi-tenancy, concurrency invariants, business logic) belong in each project's own `.claude/CLAUDE.md` and `AGENTS.md`. The dev-pipeline plugin must stay general; project-specific safety rules travel with the project, not the plugin.

## How to use this doc

When a new class of bug shows up across multiple projects, add a row to the table above and propose the corresponding pipeline upgrade. If the upgrade is **process** (a new gate or verify command) it goes into dev-pipeline. If the upgrade is **scaffold** (a new integration shape or test pattern) it goes into spec-forge. If the upgrade is **app-domain** (specific to a stack or business logic) it goes into the project's own `CLAUDE.md`.

Three-way separation:

- **dev-pipeline** = methodology + commands (process)
- **spec-forge** = scaffold registry (mechanical prevention)
- **project repo** = app-domain rules (business invariants)

If a learning crosses categories, split it.
