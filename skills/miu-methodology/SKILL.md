---
name: miu-methodology
description: Two-level work decomposition. Use whenever you are breaking down a product task into technical work units for implementation. Triggers on Phase 3-4 of /dev-pipeline:pipeline, and whenever a flow (fix/update/hotfix/pr-review) needs to plan technical work. Also triggers when an agent is about to report "done" and needs to verify the MIU output format.
---

# MIU Methodology — Two-Level Decomposition

## Activation Banner (print exactly once when this skill loads)

```
🔧 [dev-pipeline] skill: miu-methodology — MIU decomposition engine active (Phase 3-4)
   Two-level decomposition: Product Tasks → Technical MIUs
```

---

Work decomposes in two stages. Never confuse them.

## Level 1: Product Tasks (Phase 3 output)

User-visible work items written in product language:
- "Add cancellation outcome section to customer manage page"
- "Add deposit/policy detail to active bookings"
- "Show late-check-in warning on booking summary"

These are NOT directly implementable. They exist to align with the user/PM/designer. They MUST decompose into technical MIUs before any code is written.

## Level 2: Technical MIUs (Phase 4 output)

The smallest testable code change. Expressed in technical language, scoped to one or two files.

### What IS one MIU

- A backend API service: controller + service + DTOs + types + test (these only work together — don't split them)
- A frontend component with its hook and handler + test (component + hook are one cohesive thing)
- A single middleware or interceptor + test
- A Zustand/Redux/Jotai store slice + test
- A util function + test
- An infrastructure setup (TanStack Query provider, Prisma client, Redis connection) + test
- A single webhook event handler (distinct business logic per event) + test
- A database migration + verification

### What is NOT one MIU

- "DTO only" or "types only" — not independently functional, belongs with its service MIU
- Bundling unrelated concerns — "make cancelBooking atomic + add credit service + fix race condition" is 3 MIUs, not 1
- Mixing backend and frontend — always separate MIUs because tested differently
- A whole feature (e.g., "Build user profile backend") — that's a Level 1 product task, not an MIU

**The test:** Can I write a meaningful test for this? Does it deliver one complete thing? Does the project still compile after?

---

## Technical MIU Output Format (MANDATORY)

Every technical MIU MUST include ALL of these fields. A MIU without this detail is **rejected** — go deeper.

```
MIU [N]: [Technical name — component/hook/service/util, NOT product language]
  Block:        [BACKEND | FRONTEND | INFRASTRUCTURE | INTEGRATION | TESTING]
  Files:        [Exact file paths, 1-3 max]
  Type:         [new-file | modify-existing | new-test | refactor]
  Depends on:   [MIU numbers this depends on, or "none"]

  What it does:
    - [Specific implementation detail: props/params, return type, state shape]
    - [API contract if relevant: method, route, request/response DTO]
    - [UI detail if relevant: what renders, user interactions, conditional states]

  Build/Deploy/Runtime impact:   [REQUIRED — "none" is a valid answer, but you must STATE it]
    - [Does this change how anything BUILDS, DEPLOYS, or RUNS across environments?
       Not just "does the logic work" — the low-level design must cover infra.]
    - [New/changed dependency? Especially a workspace/monorepo package: which
       consumers build it, and HOW (bundler transpiles raw TS vs node runtime
       needs compiled JS)? Does every consumer's build context have it?]
    - [Touches Dockerfile / vercel.json buildCommand / CI workflow / package.json
       main·exports·files / next.config? Then name the build contexts affected
       (local, each app's prod build, container image, the node runtime) and how
       each is satisfied.]
    - [Any CI job that runs only on certain branches (e.g. on: push: main) and
       therefore WON'T run on the PR? Flag it — it must be verified locally.]

  Test plan (TDD — write FIRST):
    - [Failing test 1: exact assertion, e.g. "renders <ProfileForm> with user data from useProfile"]
    - [Failing test 2: edge case, e.g. "shows error banner when PATCH /profile returns 422"]
    - [Observable side effects (capture/emit/audit/external call) — assert they FIRE
       with the right payload, and DON'T fire on the negative branch. These are
       invisible to return-value tests; see test-planner "Observable Side Effects".]

  Done when:
    - [Specific exit criteria: "component renders with mock data, form submits, error state displays"]
    - [Project compiles, all existing tests pass]
    - [If Build/Deploy/Runtime impact ≠ none: the affected production build
       context(s) actually built + ran — container image / Vercel buildCommand /
       main-only CI — not just `turbo build`.]
```

### Required fields checklist (enforced by tech-lead)

Before approving an MIU for Phase 5 (test-writing), tech-lead checks:

- [ ] Name is TECHNICAL, not product-language (e.g. "CancellationOutcomeBanner component" not "cancellation section")
- [ ] Block is one of the 5 valid values
- [ ] Files are listed explicitly with full paths (1–3, never more)
- [ ] Type is one of the 4 valid values
- [ ] Dependencies are listed (or explicitly "none")
- [ ] "What it does" has at least 2 bullets with concrete technical detail
- [ ] "What it does" specifies props/return/DTO/API contract as applicable to the Block
- [ ] "Test plan" has ≥2 failing tests (happy + at least one edge case)
- [ ] Tests are written as assertions, not as "test X" prose
- [ ] **"Build/Deploy/Runtime impact" is STATED** (even if "none") — and if the MIU adds/changes a dependency, Dockerfile, vercel.json, CI workflow, package.json main/exports, or next.config, it enumerates the affected build contexts + how each is satisfied + any non-PR CI job to verify locally
- [ ] If the MIU has observable side effects (capture/emit/audit/external call), the test plan asserts they fire with the right payload (not just return value)
- [ ] "Done when" has ≥2 exit criteria
- [ ] Project compilation is part of "Done when"; if there's build/deploy/runtime impact, the affected production build context is part of "Done when" too
- [ ] **Contract-source rule:** MIUs that define first-party contracts (DTOs, shared types, zod schemas, API shapes) MUST precede their consumer MIUs in the DAG; every cross-boundary MIU names its contract file in "What it does"

If ANY box is unchecked → tech-lead rejects the MIU and requires deeper analysis. No exceptions.

**Why the Build/Deploy/Runtime field is mandatory (real incident):** an MIU shared a util into a workspace package — functionally correct, all unit tests green, one app's `next build` green. But the package shipped raw TS, and the design never asked "how does EACH consumer build/run this?" Result: a `tsc`+`node dist/main` service's isolated Docker build (TS2307) and runtime (can't `require` raw `.ts`) broke `main` — a build context that only runs on push to main, so it was invisible on the PR. Low-level MIU design is not just functional logic; it is also: does this build, deploy, and run in every environment that consumes it.

---

## Contract-source rule (ordering across interface boundaries)

When a feature's MIUs span an interface boundary — backend↔frontend, service↔service, app↔shared package — the MIU that DEFINES the first-party contract (DTO, shared type, zod schema, API request/response shape) is sequenced BEFORE every MIU that consumes it, and each consumer MIU:

- lists the contract MIU in `Depends on:` (or, when the consumer is on the other side of the boundary and only consumes the *shape*, states "uses API contract from MIU N" — see MIU 3 in the example below), and
- **names the contract file** (or the route + DTO pair) in its `What it does` bullets, so the dependency is checkable, not implied.

This does NOT create a "DTO only" unit where none is warranted — the contract usually ships inside its natural MIU (e.g. DTO + service, per "What IS one MIU"). The rule is about ORDER, not granularity: whichever MIU carries the contract comes first in the DAG, and consumers reference its output instead of re-declaring the shape. Tech-lead rejects a breakdown where a consumer MIU precedes the MIU that defines the contract it uses, or where a cross-boundary MIU never names its contract source.

**Granularity example (contract-first ordering, unchanged 8-field format):**

```
MIU 1: BookingSummaryDto + GET /bookings/:id/summary service method   ← defines the contract
MIU 2: BookingSummaryController route + integration test              ← Depends: MIU 1
MIU 3: useBookingSummary hook (TanStack Query)                        ← Depends: none
       What: consumes the API contract from MIU 1 — names
       src/booking/dto/booking-summary.dto.ts as its response shape
```

Wrong order (rejected): the hook MIU numbered before the DTO/service MIU it consumes — the consumer would be built against a guessed shape, and the guess becomes the de-facto contract.

---

## Granularity Examples

### WRONG — product-level, too coarse

These are Level 1 tasks, NOT MIUs:
```
MIU 1: Build user profile backend
MIU 2: Build user profile frontend
```

### RIGHT — technical, testable, 1–3 files each

```
MIU 1: GetProfileDto + UpdateProfileDto
  Block:    BACKEND
  Files:    src/profile/dto/get-profile.dto.ts, src/profile/dto/update-profile.dto.ts
  Type:     new-file
  Depends:  none
  What:     GetProfileDto { id, email, name, avatarUrl }, UpdateProfileDto { name?, avatarUrl? }
            with class-validator decorators
  Test:     validate rejects empty name, accepts partial update
  Done:     DTOs export correctly, validation decorators work, project compiles

MIU 2: ProfileService (getProfile + updateProfile)
  Block:    BACKEND
  Files:    src/profile/profile.service.ts, src/profile/profile.service.spec.ts
  Type:     new-file
  Depends:  MIU 1
  What:     getProfile(userId): Promise<GetProfileDto>
            updateProfile(userId, dto: UpdateProfileDto): Promise<GetProfileDto>
            uses Prisma; throws NotFoundException for missing user
  Test:     getProfile returns user data (mocked Prisma)
            updateProfile persists changes
            throws NotFoundException for missing user
  Done:     service methods work with mocked Prisma, tests pass, project compiles

MIU 3: useProfile hook (TanStack Query)
  Block:    FRONTEND
  Files:    src/hooks/useProfile.ts, src/hooks/useProfile.test.ts
  Type:     new-file
  Depends:  none (uses API contract from MIU 1)
  What:     useProfile() returns { data, isLoading, error } via useQuery
            useUpdateProfile() returns mutation with optimistic update
  Test:     hook returns loading then data
            mutation calls PATCH with correct payload
            optimistic update reflects immediately in cache
  Done:     hook works in test wrapper with msw mock, refetches on mutation success
```

---

## MIU Categories by Change Type

| Change Type | MIU Scope | Example |
|---|---|---|
| New component | JSX + styles + props types + local state + test | `ProfileForm` with validation |
| New hook | fetch logic + state + error handling + test | `useProfile` query + mutation |
| New backend endpoint | DTO → Service → Controller → Module → integration test | `GET /profile` endpoint chain |
| Modify existing component | isolated set of testable changes + updated test | Add error banner to `BookingCard` |
| New util function | function + types + unit test | `formatCurrency(amount, locale)` |
| Third-party integration | SDK setup → config → wrapper service → test | Stripe webhook signature verification |
| State management | store slice + selectors + actions + test | `useBookingStore` Zustand slice |
| Wiring/routing | import + render + route entry + integration test | Add `/profile` route to Next.js pages |
| Database migration | migration file + seed fixture + verification test | Add `profile_avatar_url` column |
| Configuration | config file + validation + docs | `vercel.json` with edge function routes |

---

## Rules

- **MIU names must be technical**: "CancellationOutcomeBanner component", not "add cancellation section."
- **Each MIU goes through Phases 5–9 individually**: test → implement → simplify → review → validate → commit.
- **If an MIU description fits in one line, it's not detailed enough.** Go deeper.
- **Max 3 files per MIU.** If you need more, split.
- **Never mix Blocks in a single MIU.** Backend/Frontend/Infrastructure each get their own.
- **Dependencies form a DAG.** No circular deps. Tech-lead refuses any MIU that depends on a later-numbered MIU.
- **Contracts before consumers.** The MIU defining a first-party contract (DTO/type/schema/API shape) precedes its consumer MIUs; consumers name the contract file in "What it does". See "Contract-source rule" above.

---

## When This Skill Activates

- `/dev-pipeline:pipeline` Phase 3 — Level 1 product-task decomposition
- `/dev-pipeline:pipeline` Phase 4 — Level 2 Technical MIU decomposition (MANDATORY)
- `/dev-pipeline:fix`, `/dev-pipeline:update`, `/dev-pipeline:hotfix` STEP 2 (spec phase)
- `/dev-pipeline:pr-review` when grouping review comments into fix spec sets
- Any time an agent is about to emit an MIU description
- Any time tech-lead is validating an MIU before Phase 5 start

## State & handoff model (where MIU records live)

Two tiers — never confuse them:

| | Source of truth | Pointer (cache) |
|---|---|---|
| **What** | per-MIU execution log + the MIU breakdown + architecture | "where am I" hint |
| **Where** | `docs/<feature>/` (`<feature>-execution.md`, `<feature>-miu-breakdown.md`, `architecture.md`) | `.claude/pipeline-state.json` |
| **Tracked?** | ✅ git-tracked — survives a fresh clone, portable handoff | ❌ local, gitignored, disposable |
| **Lifetime** | permanent | per-PR; rotates on merge |
| **Maintained by** | `doc-writer` agent at every MIU boundary + deliver | `doc-writer` (thin: branch/pr/phase/currentMiu/nextMiu/doc-refs) |

Rules:
- **The MIU breakdown lives in `docs/<feature>/`** (tracked), NOT `.claude/plans/` (local scratch). If a plan must survive a fresh clone or hand off to another engineer, it has to be tracked. `.claude/plans/` is fine for in-flight scratch only.
- **Per-MIU records go in the tracked execution doc**, written by `doc-writer` the moment each MIU completes — not reconstructed from memory, not dumped into local JSON.
- **`.claude/pipeline-state.json` is a ~10-line disposable pointer.** It rotates when its PR merges (the merged work is already in the tracked docs). A new PR — even in the same session — gets a fresh pointer. A stale pointer (branch merged/gone) is regenerated, never trusted. The DEPRECATED verbose `miu-progress.json` dump must not be recreated.
- **Handoff relies on the tracked docs + git + PR state, NEVER on local JSON.** A fresh clone has no `.claude/*.json` and must resume entirely from `docs/` + git.
- **Project-specific state/conventions go in the project `CLAUDE.md` or `docs/` — NEVER the user-level `~/.claude/CLAUDE.md`** (that's general routing only).

## When This Skill Activates

- `/dev-pipeline:pipeline` Phase 3 — Level 1 product-task decomposition
- `/dev-pipeline:pipeline` Phase 4 — Level 2 Technical MIU decomposition (MANDATORY)
- `/dev-pipeline:fix`, `/dev-pipeline:update`, `/dev-pipeline:hotfix` STEP 2 (spec phase)
- `/dev-pipeline:pr-review` when grouping review comments into fix spec sets
- Any time an agent is about to emit an MIU description
- Any time tech-lead is validating an MIU before Phase 5 start

## Upstream / Downstream

- **Upstream**: task-classifier skill (classifies request type before decomposition)
- **Downstream**: test-strategist agent (consumes MIU test plans), tech-lead quality gate enforcement, `doc-writer` agent (maintains the tracked execution doc + thin pointer)
