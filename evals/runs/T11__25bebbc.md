# Run: T11 · plugin SHA 25bebbc · 2026-07-07

**Task:** User message — *"Add CSV import for customer lists."*
**Fixture:** Multi-tenant SaaS salon-booking monorepo (NestJS API + tenant-scoped Prisma, Next.js frontend with next-intl en/zh-HK, @nestjs/throttler rate limiting, customer records carry PII). No existing SPEC. Tests green on main.
**Scope of run:** Through end of Phase 6 / G4 (planning complete). Phases 7–12 summarized in planned wording only.

---

## TURN 0 — Classification & routing

Per plugin `CLAUDE.md` → ROUTING (check every turn that involves code):

- "Add CSV import" matches **"Add/Build/Create [new]"** → **NEW_FEATURE** → `/dev-pipeline:pipeline`.
- Trivial-change bypass check: NOT applicable — this touches multiple files, a new API endpoint, PII, and rate-limiting surface. Route.
- No classification ambiguity → no classification question needed. (Business-intent ambiguity exists — the one-liner specifies nothing — but per Rule 23 that is handled by the routed command's Socratic gate, Phase 1.0, not by a routing question.)

> **Assistant:** Classified as NEW_FEATURE → `/dev-pipeline:pipeline`

`commands/pipeline.md` is an alias — delegates immediately to `/dev-pipeline:dev-pipeline "Add CSV import for customer lists"`. All gates G1–G4 apply. No code before G3.

---

## PHASE 0 — Smart Detection (silent, automatic)

Runs `/dev-pipeline:detect`:

- **STEP 0** (engineering-craft bootstrap): `~/.claude/skills/engineering-craft/categories` present, `.last-skill-sync` < 24h → no-op.
- **STEP 1**: root `package.json` + workspaces; `apps/api/package.json` has `@nestjs/core`, `apps/web/package.json` has `next` → **FULLSTACK** (`next+nestjs`).
- **STEP 2**: `vercel.json` present for web; API deploys via Dockerfile in CI → deploy confirmed.
- **STEP 3**: skill map — HIGH: `nestjs-best-practices`, `mastering-typescript`, `vercel-react-best-practices`; MEDIUM: `nodejs-database-orm` (prisma), `nodejs-testing` (jest), `nodejs-caching-redis` (ioredis), `nodejs-docker-production`; CONTEXT7: (none yet — CSV lib TBD in Phase 2).
- **STEP 4**: no design assets in conversation; UI feature with visual needs → `DESIGN_SOURCE=needs_stitch` (Phase 3 will adjudicate).
- **STEP 4b**: TS check/lint/test/build commands written.
- **STEP 5**: `.git/hooks/pre-commit` exists → hooks_installed=true.

Writes `.claude/project-context.json` (`taskType: "NEW_FEATURE"`, `pipelinePhases: [0..12]`, `gates: ["G1","G2","G3","G4"]`).

> **Assistant (one-line summary, then continues):**
> `[detect] FULLSTACK | deploy: vercel(✓) + api-docker(✓) | skills: 3 HIGH / 4 MEDIUM | design: needs check`

---

## PHASE 1 — Requirements Analysis

`@planning-with-files` invoked → creates persistent planning files:
- `task_plan.md` (phases 0–12 with checkboxes)
- `findings.md` (research log)
- `progress.md` (session log)

### PHASE 1.0 — Spec Elicitation (gates Phase 1 entry)

Checks, in order:
- `$ARGUMENTS` is a raw one-liner, not a SPEC/PRD path or structured spec → not skipped.
- `docs/customer-csv-import/SPEC.md` does not exist → not skipped.
- Business-vs-technical test (`skills/spec-elicitor/SKILL.md` → "When to run me"): this is not a self-evident technical fault — the *correct behaviour* (dedupe rules, file limits, error semantics, who imports, PII handling) is itself the thing in question → **RUN the elicitor, Mode A (full SPEC)**.

**Skill invoked:** `dev-pipeline:spec-elicitor` (Mode A). Activation banner printed exactly once:

```
🔧 [dev-pipeline] skill: spec-elicitor — Socratic intent elicitation active
   One question per turn → numbered options.
   Mode A (full SPEC): write SPEC.md when all 6 sections are filled · Mode B (Scope-Lock): 2–4 Qs → 🔒 Intent Lock, no file.
```

#### Elicitation dialogue (one question per turn; acknowledge → tracker → question with numbered options)

**Turn 1**

> Got it — CSV import for customer lists. Let's start with the problem.
>
> 📋 SPEC progress: [◐ Problem] [ ] Solution [ ] Constraints [ ] Non-goals [ ] Success [ ] Quality
>
> **Q1 — Who needs this import most, and when?**
>
> 1. New salons onboarding — they arrive with an existing customer list (spreadsheet / old system) and today must re-type every customer
> 2. Existing salons doing ongoing bulk sync from another system
> 3. Both, equally
> 4. Other (please describe)

**User:** `1`

**Turn 2**

> Understood — this is an onboarding pain: manual re-entry of an existing list, row by row.
>
> 📋 SPEC progress: [◐ Problem] [ ] Solution [ ] Constraints [ ] Non-goals [ ] Success [ ] Quality
>
> **Q2 — How big is a typical incoming list?**
>
> 1. Under 500 rows
> 2. 500–5,000 rows
> 3. 5,000+ rows (large chains)
> 4. Other (please describe)

**User:** `2`

**Turn 3**

> Good — hundreds to a few thousand rows. That sizes the problem (and later, the limits). Moving to the solution shape.
>
> 📋 SPEC progress: [✓ Problem] [◐ Solution] [ ] Constraints [ ] Non-goals [ ] Success [ ] Quality
>
> **Q3 — What's the entry point?**
>
> 1. An "Import CSV" action on the admin Customers page (staff-facing UI)
> 2. API-only endpoint (for integrators / scripts)
> 3. Both UI and documented public API
> 4. Other (please describe)

**User:** `1`

**Turn 4**

> Admin UI it is — an upload flow on the Customers page.
>
> 📋 SPEC progress: [✓ Problem] [◐ Solution] [ ] Constraints [ ] Non-goals [ ] Success [ ] Quality
>
> **Q4 — When an incoming row matches an existing customer (same phone or email), what should happen?**
>
> 1. Skip it — never touch existing records; report skipped rows
> 2. Update the existing record with the CSV values
> 3. Show a preview and let the operator choose per file
> 4. Other (please describe)

**User:** `1 — skip and report; updates are too risky for v1`

**Turn 5**

> Locked: duplicates are skipped and reported, never mutated. Now constraints.
>
> 📋 SPEC progress: [✓ Problem] [✓ Solution] [◐ Constraints] [ ] Non-goals [ ] Success [ ] Quality
>
> **Q5 — Column handling: fixed template or flexible mapping?**
>
> 1. Fixed CSV template we publish (download a template, exact headers required)
> 2. Interactive column-mapping step in the UI
> 3. Auto-detect headers with best-effort matching
> 4. Other (please describe)

**User:** `1`

**Turn 6**

> Fixed template — simplest and most predictable. One more constraint: these rows are PII (names, phones, emails).
>
> 📋 SPEC progress: [✓ Problem] [✓ Solution] [◐ Constraints] [ ] Non-goals [ ] Success [ ] Quality
>
> **Q6 — How strict should PII handling be for the uploaded file and its contents?**
>
> 1. Strict: process in-memory only, never persist the file, never log raw row values
> 2. Keep uploaded files for 30 days for troubleshooting
> 3. No special handling this round
> 4. Other (please describe)

**User:** `1`

**Turn 7**

> Strict PII handling — in-memory processing, no file retention, no raw values in logs. Now the explicit scope cuts.
>
> 📋 SPEC progress: [✓ Problem] [✓ Solution] [✓ Constraints] [◐ Non-goals] [ ] Success [ ] Quality
>
> **Q7 — Which of these are OUT for this round? (pick all that apply, e.g. "1,2,4")**
>
> 1. CSV *export* of customers
> 2. Excel/XLSX support
> 3. Scheduled/recurring imports
> 4. Update-existing-customers via import
> 5. Other (please describe)

**User:** `1,2,3,4 — all out`

**Turn 8**

> Clean cut: import-only, CSV-only, one-shot, create-only. Success criteria next.
>
> 📋 SPEC progress: [✓ Problem] [✓ Solution] [✓ Constraints] [✓ Non-goals] [◐ Success] [ ] Quality
>
> **Q8 — When some rows are invalid (bad email, missing name), what does "it worked" look like?**
>
> 1. All-or-nothing: any invalid row rejects the whole file
> 2. Partial: valid rows import; invalid rows are reported per-row with reasons
> 3. Dry-run first, then commit
> 4. Other (please describe)

**User:** `2`

**Turn 9**

> Partial import with a per-row error report — the operator fixes the stragglers and re-uploads. Last section: quality goals.
>
> 📋 SPEC progress: [✓ Problem] [✓ Solution] [✓ Constraints] [✓ Non-goals] [✓ Success] [◐ Quality]
>
> **Q9 — Operational limits and audit: which posture?**
>
> 1. Cap 5,000 rows / 5 MB, synchronous processing, rate-limit imports per tenant, audit-log every import (counts only, no PII)
> 2. No caps — background job queue handles any size
> 3. Caps only, no audit/rate-limit this round
> 4. Other (please describe)

**User:** `1`

#### Termination — Mode A, single turn: confirm → write → hand off

> We've covered all six sections. Here's the draft SPEC:
>
> *[full SPEC content — identical to the file below]*
>
> Type:
> 1. Approve — write to docs/customer-csv-import/SPEC.md and proceed
> 2. Tweak — tell me what to change
> 3. Add more — there's a corner we haven't covered
>
> Which?

**User:** `1`

**File written: `docs/customer-csv-import/SPEC.md` — IN FULL:**

```markdown
# Customer CSV Import — SPEC

> Authored via `dev-pipeline:spec-elicitor` on 2026-07-07.
> This is the contract for downstream phases. Every MIU must trace to a line below.

## 1. Problem Statement (问题陈述)

New salons onboarding onto the platform arrive with an existing customer list —
typically 500–5,000 rows in a spreadsheet or exported from a previous system.
Today the only path is manual re-entry through the admin "New customer" form, one
record at a time. The cost of doing nothing: hours of data entry per new tenant,
abandoned onboarding, and incomplete customer records (staff give up partway).

## 2. Proposed Solution (方案描述)

An "Import CSV" action on the admin Customers page. The operator downloads a fixed
CSV template (exact headers), fills it from their existing list, and uploads it.
The system validates each row, creates customers inside the operator's tenant,
skips duplicates (existing customer with the same email or phone), and shows a
summary: created / skipped / failed counts with per-row failure reasons. Valid rows
import even when other rows fail (partial import). Synchronous, single file, one shot.

## 3. Technical Constraints (技术约束)

- **Apps touched**: api (new import endpoint), web (admin Customers page UI)
- **Stack constraints**: stay within current stack; one new server-side CSV-parsing
  dependency is acceptable
- **Performance**: up to 5,000 rows / 5 MB per file, processed synchronously
- **Multi-tenancy**: every created customer carries the requesting operator's
  `tenantId`; dedupe lookups are tenant-scoped; an import can never read or write
  another tenant's data
- **Locales**: UI in en + zh-HK (translation keys, no hardcoded strings). CSV
  template headers are English-only this round
- **Compliance / security**: rows are PII (names, phones, emails). Process the file
  in memory only; never persist the uploaded file; never write raw row values to
  application logs. Endpoint requires an authenticated admin session
- **Integration boundaries**: none — no external services

## 4. Non-goals (明确不做的事)

- **CSV export** of customers — separate feature, separate round
- **Excel/XLSX support** — template is CSV-only; XLSX users export to CSV first
- **Scheduled/recurring imports** — this is a one-shot onboarding tool, not a sync
- **Update-existing via import** — duplicates are skipped, never mutated (v1 risk cut)
- **Interactive column mapping** — fixed template only; mapping UI is a follow-up if
  template friction proves real

## 5. Success Criteria (成功标准)

- [ ] An admin can upload a valid template CSV of ≤5,000 rows and the reported
      "created" count equals the number of new, valid rows; the customers appear in
      the tenant's customer list
- [ ] Rows matching an existing customer in the same tenant (same email OR same
      phone) are skipped and reported with their row numbers and reason "duplicate"
- [ ] Invalid rows (missing required name; malformed email; malformed phone) are
      rejected per-row with a row number + reason, while remaining valid rows still
      import
- [ ] A file over 5 MB or over 5,000 data rows is rejected up front with a clear
      error and nothing is imported
- [ ] The CSV template is downloadable from the import UI
- [ ] Every user-facing string in the flow resolves in both en and zh-HK

## 6. Quality Criteria (质量标准)

- [ ] A 5,000-row import completes synchronously in < 30s p95 (asserted by an
      integration test against a seeded 5,000-row fixture)
- [ ] Import endpoint is rate-limited to 5 requests per hour per tenant via the
      existing @nestjs/throttler setup; the 6th request within the window returns 429
- [ ] Every import writes exactly one audit-log entry: { tenantId, actorUserId,
      filename, rowsTotal, created, skipped, failed } — and NO raw row values (PII)
      appear in any log line
- [ ] Simplicity trade-off (explicit): synchronous request handling, no job queue —
      acceptable because the hard cap is 5,000 rows / 5 MB

---

## Elicitation Trace

- Asked who needs this and when → user chose "new salons onboarding with an
  existing list" → captured in Problem.
- Asked typical list size → user chose 500–5,000 rows → captured in Problem +
  sized the caps in Constraints/Quality.
- Asked entry point → user chose admin Customers page UI → captured in Solution.
- Asked duplicate handling → user chose skip-and-report (updates "too risky for
  v1") → captured in Solution + Non-goals.
- Asked column handling → user chose fixed published template → captured in
  Constraints + Non-goals (no mapping UI).
- Asked PII posture → user chose strict (in-memory only, no retention, no raw
  values in logs) → captured in Constraints + Quality.
- Asked scope cuts → user cut export, XLSX, scheduled sync, update-via-import →
  captured in Non-goals.
- Asked invalid-row semantics → user chose partial import with per-row report →
  captured in Solution + Success.
- Asked limits/audit posture → user chose caps + sync + tenant rate limit +
  PII-free audit log → captured in Quality.
```

> ✓ SPEC written to docs/customer-csv-import/SPEC.md

(Elicitor hands back; because we are inside `/dev-pipeline:dev-pipeline` Phase 1.0, the pipeline continues to Phase 1.1 with the SPEC as primary input.)

### PHASE 1.1 — Codebase Analysis

**Agent launched:** `requirements-analyst` (input: `docs/customer-csv-import/SPEC.md`, not the raw sentence).

**Agent output (sketch):**

- **Feature understanding:** create-only, tenant-scoped bulk ingest of customers from a fixed-template CSV, surfaced on the admin Customers page; partial-import semantics with per-row reporting; strict PII posture.
- **Relevant CLAUDE.md rules:** every query/create tenant-scoped (`tenantId` on all Prisma ops; controllers use the tenant decorator); i18n keys required in both `messages/en.json` and `messages/zh-HK.json`; global `ValidationPipe` runs `forbidNonWhitelisted: true` — response/request DTOs must whitelist exactly what's sent.
- **Existing patterns found:**
  - `apps/api/src/modules/customer/customer.service.ts` — `create()` is tenant-scoped; unique-per-tenant checks on email/phone already exist (`findFirst({ where: { tenantId, OR: [{email},{phone}] } })`).
  - `apps/api/src/modules/customer/dto/create-customer.dto.ts` — class-validator conventions (name required; `@IsEmail()`; phone regex).
  - `apps/api/src/common/middleware/tenant-resolution.middleware.ts` + `@TenantId()` decorator — how tenant reaches controllers.
  - `apps/api/src/app.module.ts` — `ThrottlerModule.forRoot` already configured; per-route overrides via `@Throttle` used in auth module.
  - `apps/api/src/common/audit/audit.service.ts` — existing audit-log writer (`record(tenantId, actorUserId, action, meta)`).
  - `apps/web/app/[locale]/admin/customers/page.tsx` + `apps/web/hooks/useCustomers.ts` — TanStack Query conventions; `useTranslations('customers')`.
  - Jest on API, Testing Library + Playwright on web; msw for hook tests.
- **Open questions (framed Socratically, numbered options)** — most were closed by the SPEC; two remain:
  1. Phone dedupe: match on exact string after trim, or normalize (e.g. strip spaces/dashes) before comparing? (a) exact-after-trim (b) digits-only normalization (c) other
  2. Template columns: minimum viable set is `name,email,phone,notes` — is `notes` in the template? (a) yes (b) no
- **Key files to read:** the seven above + `apps/api/prisma/schema.prisma` (Customer model: `@@unique([tenantId, email])`? — no; uniqueness is enforced in service layer) + `apps/web/messages/en.json`.

Findings saved to `findings.md` (2-Action Rule). Orchestrator reads the key files, then presents the understanding summary + the two remaining questions.

**User answers:** "1 → (b) digits-only normalization for comparison, store as entered. 2 → (a) yes, notes optional."

### 🚦 GATE G1

> **Assistant:** Requirements ready. SPEC at `docs/customer-csv-import/SPEC.md`; two residual ambiguities resolved (phone dedupe = digits-only comparison, store-as-entered; template = `name,email,phone,notes` with notes optional). Continue? [Y]

**User:** `Y`

---

## PHASE 2 — Skill Discovery & Tech Stack Detection

**Agent launched:** `skill-scout`.

**Output (sketch):**

1. **Tech Stack Profile** — runtime: Node 20 / pnpm monorepo (turbo); backend: NestJS 10 + Prisma + PostgreSQL + ioredis; frontend: Next.js 14 App Router + next-intl + TanStack Query; testing: Jest (api), Testing Library + Playwright (web); rate limiting: `@nestjs/throttler`; containerization: api Dockerfile.
2. **Recommended Skills** — HIGH: `nestjs-best-practices`, `mastering-typescript`, `vercel-react-best-practices` · MEDIUM: `nodejs-database-orm`, `nodejs-testing`, `nodejs-security` (`@nestjs/jwt` detected) · LOW: `nodejs-caching-redis`, `nodejs-docker-production`.
3. **Unmatched Technologies** — CSV parsing: no installed lib and no matching skill → **Context7 fallback** for the chosen library (candidate: `csv-parse`); `multer` (file upload via `@nestjs/platform-express`) → Context7 on demand.

Recommended Skills list stored for Phase 4 + Phase 7. Findings saved to `findings.md`. No skill gaps requiring installation → no user ask.

---

## PHASE 3 — Design Check

**Agent launched:** `design-checker`.

**Output:**

```
## Design Check

**DESIGN_REQUIRED: YES**

**Reason:** New component + modified interaction on an existing page — an import
modal/flow with distinct states (idle, file-selected, uploading, partial-success
summary with error table, hard-failure). Matches "new components or modified
interactions (modals, forms, flows)" and "existing pages with new states".

**Category:** new components / new states

**Existing designs found:** None found (design/ has no customer-import artifacts)

**If YES — next steps:**
1. Run /ui-ux-pro-max to generate mockups
2. Run /web-design-guidelines to audit the design
3. Save artifacts to design/customer-import/
```

> **Assistant:** This feature requires UI design. Please run:
> 1. `/ui-ux-pro-max` to generate mockups
> 2. `/web-design-guidelines` to audit the design
> Then tell me to continue.
>
> **PAUSED** — waiting for user.

**User (simulated, after running the design flow):** "Done — mockups + audited spec saved to `design/customer-import/` (modal: dropzone → validating → result summary with per-row error table; template download link in the modal header). Continue."

### 🚦 GATE G2

> **Assistant:** Design reviewed — `design/customer-import/` artifacts cover all five modal states and both locales. Continue? [Y]

**User:** `Y`

---

## PHASE 4 — Technical Design

`@writing-plans` invoked for structured plan decomposition.

**Agent launched:** `technical-architect` (inputs: SPEC, Phase 1 findings + key files, CLAUDE.md rules, Phase 2 skill list).

Per CLAUDE.md Rule 22, the architect verifies every third-party surface the design depends on BEFORE finalizing — context7 for docs, plus installed `node_modules/**/*.d.ts` where the package is already present.

**Architect output (as presented to user):**

```
## Architecture Decision

Synchronous, tenant-scoped bulk-create behind one new POST endpoint. A pure parsing/
validation layer (no I/O) turns the uploaded buffer into typed row results; the
service layer does tenant-scoped dedupe + batched creates inside a transaction per
chunk; the controller owns upload limits and throttling. Frontend: a self-contained
import modal on the existing Customers page, driven by one mutation hook posting
multipart FormData. No schema change — the existing Customer model + service-layer
uniqueness convention already support this. No queue (SPEC Quality: simplicity wins
at ≤5k rows).

## Third-Party Surfaces Verified
| Library/Service | Behavior depended on | Evidence | Installed? |
|---|---|---|---|
| csv-parse | `parse(buffer, { columns: true, skip_empty_lines: true, bom: true, to: 5001 })` from `csv-parse/sync` returns array of header-keyed records; throws `CsvError` with `code` on malformed input | context7 `/adaltas/node-csv` sync-API page — "context7 only — not yet installed"; re-verify against installed .d.ts at Phase 7.6 (verify-sdk-surface) | no |
| @nestjs/platform-express (multer) | `FileInterceptor('file', { limits: { fileSize } })` populates `file: Express.Multer.File` with in-memory `buffer` when no storage engine is set (memory storage default) | context7 NestJS file-upload docs + node_modules/@nestjs/platform-express/multer/interceptors/file.interceptor.d.ts:1 + node_modules/@types/multer/index.d.ts (File.buffer) | yes |
| @nestjs/throttler v5 | Per-route override is `@Throttle({ default: { limit: 5, ttl: 3600000 } })` — the v4 positional form `@Throttle(5, 3600)` no longer type-checks | node_modules/@nestjs/throttler/dist/throttler.decorator.d.ts:‹Resolvable<ThrottlerOptions>› + context7 v5 migration notes | yes |
| prisma (@prisma/client) | `createMany({ data, skipDuplicates: true })` unsupported semantics NOT relied on — dedupe is done by explicit tenant-scoped findMany + set diff, creates via `createMany({ data })` inside `$transaction` | node_modules/.prisma/client/index.d.ts (CustomerCreateManyArgs) | yes |

## Patterns to Follow
- Tenant-scoped service ops: apps/api/src/modules/customer/customer.service.ts:41 — reuse dedupe query shape
- Controller tenant extraction: @TenantId() decorator per tenant-resolution.middleware.ts
- Validation conventions: apps/api/src/modules/customer/dto/create-customer.dto.ts:12 (@IsEmail, phone regex)
- Audit writes: apps/api/src/common/audit/audit.service.ts:18 record(tenantId, actor, action, meta)
- Admin data hooks: apps/web/hooks/useCustomers.ts:9 (TanStack Query + api client conventions)

## Component Design

### Backend
| Component | File Path | Responsibility |
|-----------|-----------|---------------|
| customer-import.types.ts | apps/api/src/modules/customer/import/customer-import.types.ts | CustomerImportRow, RowError, ImportResult — the first-party contract |
| customer-csv-parser.ts | apps/api/src/modules/customer/import/customer-csv-parser.ts | buffer → { validRows, rowErrors }; header check; per-row validation; row cap |
| customer-import.service.ts | apps/api/src/modules/customer/import/customer-import.service.ts | tenant-scoped dedupe (digits-only phone compare), chunked createMany in tx, audit write, ImportResult |
| customer-import.controller.ts (route added to customer module) | apps/api/src/modules/customer/import/customer-import.controller.ts | POST /customers/import — FileInterceptor (5MB), @Throttle, @TenantId, maps service result to ImportResultDto |

### Frontend
| Component | File Path | Responsibility |
|-----------|-----------|---------------|
| useImportCustomers | apps/web/hooks/useImportCustomers.ts | mutation posting FormData to /customers/import; invalidates customers query on success |
| CsvImportModal | apps/web/components/customers/CsvImportModal.tsx | dropzone → uploading → result summary states; per-row error table; template download link |
| Customers page wiring | apps/web/app/[locale]/admin/customers/page.tsx | "Import CSV" button; renders modal; static template asset link |

## Data Flow
Admin picks file → CsvImportModal → useImportCustomers (multipart POST /customers/import)
→ controller (size/type gate, throttle, tenant) → parser (headers, row cap, row validation)
→ service (tenant-scoped dedupe → chunked createMany in $transaction → audit.record)
→ ImportResult { created, skipped[], failed[] } → modal summary + customers list refetch

## Files to Create
1. apps/api/src/modules/customer/import/customer-import.types.ts — contract
2. apps/api/src/modules/customer/import/customer-csv-parser.ts (+spec) — pure parse/validate
3. apps/api/src/modules/customer/import/customer-import.service.ts (+spec) — dedupe/create/audit
4. apps/api/src/modules/customer/import/customer-import.controller.ts (+ e2e spec) — route
5. apps/web/hooks/useImportCustomers.ts (+test) — mutation hook
6. apps/web/components/customers/CsvImportModal.tsx (+test) — UI
7. apps/web/public/templates/customer-import-template.csv — the published template

## Files to Modify
1. apps/api/src/modules/customer/customer.module.ts — register controller+service
2. apps/api/package.json — add csv-parse
3. apps/web/app/[locale]/admin/customers/page.tsx — button + modal wiring
4. apps/web/messages/en.json, apps/web/messages/zh-HK.json — customersImport.* keys

## Data Model Changes
None. Existing Customer model suffices; uniqueness stays a service-layer, tenant-scoped concern (matches current convention).

## Trade-offs
- Chose synchronous processing over a BullMQ job: SPEC Quality criterion explicitly
  trades simplicity at the 5k-row cap; a queue adds infra + polling UI for no v1 gain.
- Chose explicit dedupe query + set-diff over createMany skipDuplicates: there is no
  DB unique constraint on (tenantId,email/phone), and we must REPORT skips per row —
  skipDuplicates would silently drop and can't say which rows.
- Chose csv-parse (sync API) over hand-rolled split(','): quoted fields, BOM, embedded
  commas/newlines are exactly the hand-rolling trap; `to:` gives a cheap row cap.
- Known limitation: 5k-row import holds one request ~seconds — mitigated by the row/size
  cap + throttle; revisit queue only if the cap rises.
```

> **Assistant:** Architecture above, including the Third-Party Surfaces Verified table (note the throttler v5 decorator signature — the v4 positional form from training memory would not compile). Approve the architecture before I proceed to task breakdown?

**User:** "Approved — proceed."

---

## PHASE 5 — Module & Task Breakdown

`@writing-plans` continues (chunk-based decomposition). Skill auto-activated:

```
🔧 [dev-pipeline] skill: miu-methodology — MIU decomposition engine active (Phase 3-4)
   Two-level decomposition: Product Tasks → Technical MIUs
```

**Agent launched:** `tech-lead` (input: approved architecture).

### Level 1 — Product Tasks

- PT1: Admin can bulk-import customers from a template CSV (partial import, per-row report)
- PT2: Duplicates and invalid rows are safely skipped/reported, tenant-scoped
- PT3: Import is capped, rate-limited, audited, and PII-safe
- PT4: Import UI on the Customers page in en + zh-HK, with template download

### Level 2 — Technical MIU breakdown (MANDATORY format) — IN FULL

```
## Module Breakdown

### Module 1: API import core (BACKEND)
Contract types, pure CSV parsing/validation, tenant-scoped import service, HTTP route.

### Module 2: Admin import UI (FRONTEND)
i18n keys, mutation hook, import modal, Customers-page wiring, template asset.

### Module 3: End-to-end proof (TESTING)
Playwright journey against the running stack.

## Implementation Order (MIUs)

MIU 1: customer-import contract types + parseCustomerCsv util
  Block:        BACKEND
  Files:        apps/api/src/modules/customer/import/customer-import.types.ts,
                apps/api/src/modules/customer/import/customer-csv-parser.ts,
                apps/api/src/modules/customer/import/customer-csv-parser.spec.ts
  Type:         new-file
  Depends on:   none

  What it does:
    - DEFINES THE FIRST-PARTY CONTRACT (contract-source rule): CustomerImportRow
      { name: string; email?: string; phone?: string; notes?: string; rowNumber: number },
      RowError { rowNumber: number; reason: 'missing_name'|'invalid_email'|'invalid_phone'|'duplicate' },
      ImportResult { rowsTotal: number; created: number; skipped: RowError[]; failed: RowError[] }
      — in customer-import.types.ts; every later MIU names this file
    - parseCustomerCsv(buffer: Buffer): { validRows: CustomerImportRow[]; rowErrors: RowError[] } —
      csv-parse/sync with { columns: true, skip_empty_lines: true, bom: true, to: 5001 };
      throws ImportFileError('bad_headers') on header mismatch vs name,email,phone,notes;
      throws ImportFileError('too_many_rows') past 5,000 data rows;
      per-row validation mirrors create-customer.dto.ts rules (name required, @IsEmail-equivalent
      regex, phone regex); pure function, no I/O, no tenant awareness

  Build/Deploy/Runtime impact:
    - Adds dependency `csv-parse` to apps/api (pnpm add --filter api). Affected build
      contexts: (1) local api build, (2) API Docker image — its pnpm install step picks the
      lockfile change up automatically, (3) CI api job — same. No raw-TS workspace-package
      hazard: csv-parse ships compiled JS. No Dockerfile/vercel.json/CI edits needed.
    - No CI job is branch-gated for the api unit path → nothing to reproduce locally.

  Test plan (TDD — write FIRST):
    - "parses a valid 3-row template CSV into 3 validRows with correct field mapping and
      rowNumber 2..4 (header = row 1)"
    - "returns rowError { rowNumber, reason: 'invalid_email' } for a malformed email and
      still yields the other rows as validRows (partial semantics)"
    - "returns rowError 'missing_name' when name cell is empty/whitespace"
    - "throws ImportFileError('bad_headers') when headers ≠ name,email,phone,notes"
    - "throws ImportFileError('too_many_rows') for 5,001 data rows"
    - "handles quoted fields with embedded commas and a UTF-8 BOM (fixture file)"
    - Observable side effects: N/A — pure function, and asserts NO logging of row values
      (logger spy not called)

  Done when:
    - All parser specs pass; error taxonomy matches the contract enums
    - Project compiles (turbo type-check green); apps/api builds with csv-parse resolved
    - Build/Deploy impact ≠ none → `docker build` of the api image succeeds locally with
      the new dependency

MIU 2: CustomerImportService (tenant-scoped dedupe + chunked create + audit)
  Block:        BACKEND
  Files:        apps/api/src/modules/customer/import/customer-import.service.ts,
                apps/api/src/modules/customer/import/customer-import.service.spec.ts
  Type:         new-file
  Depends on:   MIU 1

  What it does:
    - importCustomers(tenantId: string, actorUserId: string, filename: string,
      buffer: Buffer): Promise<ImportResult> — consumes the contract from MIU 1
      (customer-import.types.ts)
    - Calls parseCustomerCsv; dedupe: ONE tenant-scoped query
      prisma.customer.findMany({ where: { tenantId }, select: { email, phone } }) →
      in-memory match on lowercased email OR digits-only-normalized phone (store-as-entered,
      compare-normalized per G1 decision); intra-file duplicates also skipped
    - Creates remaining rows in chunks of 500 via prisma.$transaction →
      createMany({ data: rows.map(r => ({ ...r, tenantId })) })
    - Writes exactly one audit entry via AuditService.record(tenantId, actorUserId,
      'customer.import', { filename, rowsTotal, created, skipped, failed }) — counts only,
      never row contents

  Build/Deploy/Runtime impact:
    - none (stated) — no new deps, no build-context change

  Test plan (TDD — write FIRST):
    - "creates all valid rows with the caller's tenantId on every record (assert
      createMany payload includes tenantId per row)" (mocked Prisma)
    - "skips a row whose email matches an existing tenant customer; ImportResult.skipped
      contains { rowNumber, reason: 'duplicate' }"
    - "skips on phone match where CSV has '9123-4567' and DB has '91234567'
      (digits-only normalization)"
    - "does NOT match a duplicate that exists only in ANOTHER tenant (cross-tenant
      isolation: same email under tenantB is created for tenantA)"
    - "second occurrence of the same email within one file is skipped as duplicate"
    - "empty valid set (all rows invalid) → created: 0, no createMany call, audit still fires"
    - Observable side effects: "audit.record called ONCE with
      ('t1','u1','customer.import',{filename,rowsTotal:5,created:3,skipped:1,failed:1})
      — payload asserted With(...), not bare toHaveBeenCalled()"; negative: "audit meta
      contains no name/email/phone values"; "no logger call includes row field values"

  Done when:
    - Service specs pass incl. cross-tenant isolation + audit payload assertions
    - Project compiles; existing customer module tests still green

MIU 3: POST /customers/import controller route + ImportResultDto
  Block:        BACKEND
  Files:        apps/api/src/modules/customer/import/customer-import.controller.ts,
                apps/api/src/modules/customer/import/customer-import.controller.spec.ts,
                apps/api/src/modules/customer/customer.module.ts
  Type:         new-file (controller) + modify-existing (module registration)
  Depends on:   MIU 2

  What it does:
    - POST /customers/import — @UseInterceptors(FileInterceptor('file',
      { limits: { fileSize: 5 * 1024 * 1024 } })) (memory storage → file.buffer),
      @Throttle({ default: { limit: 5, ttl: 3600000 } }) (v5 object signature — verified
      Phase 4), admin-guarded, tenant via @TenantId()
    - Response: ImportResultDto mirroring ImportResult from MIU 1
      (customer-import.types.ts named as the contract source); maps
      ImportFileError('bad_headers'|'too_many_rows') → 422 with i18n-stable error code;
      missing/oversize file → 400/413
    - Registers controller + service in customer.module.ts

  Build/Deploy/Runtime impact:
    - none (stated) — route only; throttler + multer already installed and configured

  Test plan (TDD — write FIRST):
    - "multipart upload of valid fixture returns 201 with { rowsTotal, created, skipped,
      failed } shape exactly matching ImportResultDto (forbidNonWhitelisted-safe)"
    - "bad headers fixture → 422 { code: 'bad_headers' }"
    - "no file part → 400; 6MB file → 413 (interceptor limit)"
    - "6th request within an hour from same tenant → 429 (throttler override active)"
    - "request without admin auth → 401/403 (guard)"
    - Multi-tenancy: "tenantId reaching the service comes from @TenantId(), not from any
      body/query field (attempt to spoof tenantId in form fields is ignored/400)"
    - Observable side effects: covered at service layer (MIU 2); controller spec asserts
      service called with (tenantId from context, actor from session, originalname, buffer)

  Done when:
    - Controller integration specs pass against the Nest testing module
    - Project compiles; route visible in module; existing e2e smoke unaffected

MIU 4: customersImport i18n message keys (en + zh-HK)
  Block:        FRONTEND
  Files:        apps/web/messages/en.json,
                apps/web/messages/zh-HK.json
  Type:         modify-existing
  Depends on:   none

  What it does:
    - Adds the customersImport.* namespace to BOTH locale files: title, dropzoneIdle,
      uploading, downloadTemplate, resultSummary ({created}/{skipped}/{failed} ICU
      params), errorTable headers (row/reason), reason codes (missing_name,
      invalid_email, invalid_phone, duplicate, bad_headers, too_many_rows,
      file_too_large, rate_limited), close/retry actions
    - Reason-code keys deliberately mirror the MIU 1 contract enums (named:
      customer-import.types.ts) so the UI maps API codes → localized strings with no
      switch drift

  Build/Deploy/Runtime impact:
    - none (stated) — message JSON only; next-intl loads at build/runtime as today

  Test plan (TDD — write FIRST):
    - "locale parity spec: every key added under customersImport exists in BOTH en.json
      and zh-HK.json (extends the existing messages-parity test)"
    - "ICU arguments in resultSummary are identical across locales ({created},{skipped},{failed})"

  Done when:
    - Parity spec green in both locales; project compiles
    - No hardcoded-English fallback needed by later MIUs

MIU 5: useImportCustomers mutation hook
  Block:        FRONTEND
  Files:        apps/web/hooks/useImportCustomers.ts,
                apps/web/hooks/useImportCustomers.test.tsx
  Type:         new-file
  Depends on:   MIU 4 (uses API contract from MIU 3 — names
                apps/api/src/modules/customer/import/customer-import.types.ts /
                ImportResultDto as its response shape)

  What it does:
    - useImportCustomers(): TanStack Query useMutation<ImportResult, ApiError, File> —
      builds FormData { file }, POST /customers/import via the shared api client
      (no manual Content-Type; browser sets the multipart boundary)
    - onSuccess: invalidateQueries(['customers']) so the list refetches
    - Maps 413/422/429 into typed error codes the modal can localize

  Build/Deploy/Runtime impact:
    - none (stated)

  Test plan (TDD — write FIRST):
    - "posts multipart FormData containing the file to /customers/import (msw intercept
      asserts field name 'file')"
    - "resolves with ImportResult and invalidates the customers query key (spy on
      queryClient.invalidateQueries)"
    - "maps a 429 response to error code 'rate_limited'; 422 body code passes through"

  Done when:
    - Hook tests pass under msw wrapper; project compiles

MIU 6: CsvImportModal component
  Block:        FRONTEND
  Files:        apps/web/components/customers/CsvImportModal.tsx,
                apps/web/components/customers/CsvImportModal.test.tsx
  Type:         new-file
  Depends on:   MIU 4, MIU 5

  What it does:
    - Modal per design/customer-import/ spec: states idle(dropzone + template download
      link) → file-selected → uploading(disabled controls, spinner) → result(summary
      counts + per-row error table) → hard-failure(bad_headers/too_many_rows/
      file_too_large/rate_limited banner)
    - Props: { open: boolean; onClose(): void }; uses useImportCustomers (MIU 5) and
      useTranslations('customersImport') (MIU 4); accepts .csv only (input accept +
      client-side 5MB pre-check mirroring the server limit)
    - Template link points at /templates/customer-import-template.csv (shipped in MIU 7)

  Build/Deploy/Runtime impact:
    - none (stated)

  Test plan (TDD — write FIRST):
    - "renders dropzone + localized template link when open (en fixture messages)"
    - "on successful upload shows created/skipped/failed counts and rows table with
      localized reason for reason code 'duplicate'"
    - "shows hard-failure banner for error code 'bad_headers' (nothing imported copy)"
    - "shows rate-limit banner on 'rate_limited' with retry disabled"
    - "client-side rejects a 6MB file before any network call (msw handler NOT hit)"
    - Accessibility: "modal traps focus, has aria-labelledby on title; error table has
      column headers; dropzone reachable by keyboard (Enter opens file dialog)"

  Done when:
    - Component tests pass incl. a11y assertions; project compiles
    - All strings come from customersImport.* keys (no literal English in JSX)

MIU 7: Customers page wiring + published template asset
  Block:        FRONTEND
  Files:        apps/web/app/[locale]/admin/customers/page.tsx,
                apps/web/public/templates/customer-import-template.csv,
                apps/web/app/[locale]/admin/customers/page.test.tsx
  Type:         modify-existing (+ new static asset)
  Depends on:   MIU 6

  What it does:
    - Adds "Import CSV" button (localized) beside "New customer"; opens CsvImportModal;
      list refresh is free via MIU 5's invalidation
    - Ships the canonical template file with exact headers name,email,phone,notes and
      one example row (fake data, clearly non-real)

  Build/Deploy/Runtime impact:
    - none (stated) — static asset under public/ is served by the existing Next build;
      no next.config/vercel.json change

  Test plan (TDD — write FIRST):
    - "renders the localized Import CSV button and opens the modal on click"
    - "template asset exists and its header row is exactly name,email,phone,notes
      (fs read in test — guards template/parser drift against MIU 1)"

  Done when:
    - Page test green; project compiles; modal reachable from the page in dev

MIU 8: E2E import journey (Playwright)
  Block:        TESTING
  Files:        apps/web/e2e/customer-csv-import.spec.ts,
                apps/web/e2e/fixtures/customers-mixed.csv
  Type:         new-test
  Depends on:   MIU 7

  What it does:
    - Full journey vs the running stack: login as admin → Customers → Import CSV →
      upload fixture (6 rows: 3 valid, 1 duplicate-of-seeded, 1 bad email, 1 missing
      name) → assert summary 3/1/2 → close → 3 new names visible in the list
    - Second scenario: bad-headers fixture → hard-failure banner, list unchanged
    - Runs in both locales via the existing Playwright locale project matrix

  Build/Deploy/Runtime impact:
    - none (stated) — uses existing e2e harness/config

  Test plan (TDD — write FIRST):
    - "mixed fixture yields summary created=3 skipped=1 failed=2 and the 3 customers
      appear in the tenant's list"
    - "bad-headers file shows failure banner and creates nothing (list count unchanged)"

  Done when:
    - Both e2e scenarios green locally against the docker-compose stack in en and zh-HK
    - Full suite (unit + e2e) green

## Dependency Graph

MIU 1 → MIU 2 → MIU 3 ─────────────┐
MIU 4 → MIU 5 → MIU 6 → MIU 7 → MIU 8
        (MIU 5 uses API contract from MIU 3 / types from MIU 1 — contract-source rule:
         contract defined in MIU 1, all consumers higher-numbered ✓)

Estimated effort: MIU 1 M · MIU 2 M · MIU 3 M · MIU 4 S · MIU 5 S · MIU 6 M · MIU 7 S · MIU 8 M
```

**Tech-lead required-fields checklist (from `skills/miu-methodology`)** — applied to all 8 MIUs before presenting: technical names ✓ · valid Block enums ✓ · ≤3 files each ✓ · Type enums ✓ · deps explicit/DAG, no forward refs ✓ · ≥2 concrete "What it does" bullets with contracts ✓ · ≥2 assertion-style failing tests each ✓ · Build/Deploy/Runtime STATED on every MIU (csv-parse contexts enumerated on MIU 1) ✓ · side-effect assertions present (audit payload With(...), negatives) ✓ · ≥2 done-when incl. compile; Docker build in MIU 1 done-when ✓ · contract-source rule ✓. **PASS** — no MIU rejected. (The mechanical validator `tools/validate-miu-breakdown.sh` re-checks this at Phase 7 / implement STEP 0.)

**doc-writer** persists the tracked artifacts (source of truth in `docs/`, thin pointer local):
- `docs/customer-csv-import/architecture.md` (Phase 4 output)
- `docs/customer-csv-import/customer-csv-import-miu-breakdown.md` (the breakdown above)
- `.claude/pipeline-state.json` → `{ branch: -, phase: 5, currentMiu: null, nextMiu: 1, docRefs: docs/customer-csv-import/ }`

### 🚦 GATE G3

> **Assistant:** **APPROVE ARCHITECTURE** — architecture (Phase 4) + the 8-MIU implementation plan above. No code until confirmed.

**User:** "Approved."

---

## PHASE 6 — Test Planning

**Agent launched:** `test-planner` (inputs: MIU breakdown, SPEC, existing test conventions).

**Output (consolidated across MIUs; per mandated format):**

```
## Test Scenarios for: Customer CSV Import

### Test File: apps/api/src/modules/customer/import/customer-csv-parser.spec.ts

#### Happy Path
1. Valid 3-row template parses to 3 validRows, fields mapped, rowNumbers 2–4 — header row excluded
2. notes column optional — row without notes parses with notes undefined

#### Error States
3. Header mismatch (missing 'phone') — throws ImportFileError('bad_headers'), no rows returned
4. 5,001 data rows — throws ImportFileError('too_many_rows') without full materialization (to: cap)
5. Malformed email 'not-an-email' — rowError { rowNumber, reason: 'invalid_email' }; sibling rows still valid
6. Whitespace-only name — rowError 'missing_name'

#### Edge Cases
7. Empty file / header-only file — validRows: [], rowErrors: [] (created will be 0)
8. Quoted field with embedded comma ("Tan, Mei Ling") — parses as one name value
9. UTF-8 BOM prefix — first header still recognized (bom: true)
10. CRLF vs LF line endings — identical results
11. Exactly 5,000 rows — accepted (boundary)

#### Locale Variants
12. zh-HK names / CJK characters in name and notes survive parsing byte-exact

#### Multi-Tenancy
N/A — pure function, no tenant awareness by design (enforced at service layer)

#### Observable Side Effects / Instrumentation
13. Logger spy: NO log call contains any row field value (PII negative assertion)

### Test File: apps/api/src/modules/customer/import/customer-import.service.spec.ts

#### Happy Path
14. 5 valid rows → createMany payloads all carry caller's tenantId; ImportResult { rowsTotal:5, created:5 }
15. 1,200 valid rows → chunked: three $transaction/createMany calls (500/500/200)

#### Error States
16. Parser ImportFileError propagates untouched (controller owns HTTP mapping)

#### Edge Cases
17. Email dedupe is case-insensitive (DB 'A@x.com' vs CSV 'a@x.com' → skipped 'duplicate')
18. Phone dedupe digits-only: DB '91234567' vs CSV '9123-4567' → skipped; stored values never rewritten
19. Intra-file duplicate (same email twice) — first created, second skipped
20. All rows invalid — created: 0, createMany never called, audit still records the attempt

#### Multi-Tenancy
21. Same email exists under tenantB only → row IS created for tenantA (dedupe query filtered by tenantId)
22. Every created record's tenantId equals the caller's — asserted per element of createMany data

#### Observable Side Effects / Instrumentation
23. audit.record called exactly once With('t1','u1','customer.import',{filename,rowsTotal,created,skipped,failed}) — full payload asserted
24. Negative: audit meta and all log output contain zero name/email/phone values

### Test File: apps/api/src/modules/customer/import/customer-import.controller.spec.ts

#### Happy Path
25. Multipart upload of valid fixture → 201, body exactly ImportResultDto shape (whitelist-safe)

#### Error States
26. No file part → 400; 6MB body → 413; bad headers → 422 { code: 'bad_headers' }; >5,000 rows → 422 { code: 'too_many_rows' }
27. Unauthenticated → 401; authenticated non-admin role → 403
28. 6th request in 3600s window per tenant → 429 (@Throttle v5 override)

#### Edge Cases
29. Wrong field name in multipart ('csv' not 'file') → 400

#### Multi-Tenancy
30. tenantId spoofed in form field is ignored — service receives @TenantId() context value only

#### Observable Side Effects / Instrumentation
31. Service invoked With(tenant-from-context, actor-from-session, originalname, buffer)

### Test File: apps/web (hook/component/page tests — MIU 5–7)

#### Happy Path
32. Hook posts FormData field 'file'; resolves ImportResult; invalidates ['customers']
33. Modal result state renders localized created/skipped/failed counts + per-row reason table
34. Page button opens modal; template link resolves; template header row === name,email,phone,notes (drift guard)

#### Error States
35. 'rate_limited' → localized banner, retry disabled; 'bad_headers' → hard-failure copy "nothing imported"

#### Edge Cases
36. 6MB file rejected client-side — msw handler never hit

#### Locale Variants
37. Parity spec: every customersImport.* key exists in en.json AND zh-HK.json with identical ICU params
38. Modal renders fully in zh-HK fixture (no missing-key fallback text)

#### Multi-Tenancy
N/A — frontend has no tenant selector; tenant is ambient in the session (asserted server-side, #21/22/30)

#### Observable Side Effects / Instrumentation
39. Query invalidation asserted (spy WITH key ['customers']); no analytics events in scope this feature — N/A beyond that

#### Accessibility
40. Modal: focus trap, aria-labelledby, Esc closes; error table has header cells; dropzone keyboard-operable

### E2E Scenarios
#### File: apps/web/e2e/customer-csv-import.spec.ts
1. Admin logs in → Customers → Import → uploads mixed fixture (3 valid / 1 dup / 2 invalid) → summary 3/1/2 → 3 new customers visible in list — run in en AND zh-HK
2. Bad-headers fixture → failure banner, customer count unchanged

**Total: 40 unit/integration scenarios + 2 e2e scenarios (×2 locales)**
```

Scenarios map onto MIUs 1–8; SPEC Success Criteria 1–6 and Quality Criteria 1–4 each have ≥1 covering scenario (perf criterion → seeded 5,000-row integration timing test attached to scenario 15's fixture; traced again mechanically at Phase 8.6 verify-traceability, including the `quality` category).

### 🚦 GATE G4

> **Assistant:** Test plan above — 40 unit/integration + 2 e2e scenarios covering every SPEC success/quality criterion. **FINAL APPROVAL** — after this I run autonomously (Phases 7–12: implement → validate → deliver, no further gates).

**User:** `Y — go.`

---

## PHASES 7–12 (not executed in this run — planned path only)

- Phase 7 **would run** per-MIU TDD (failing tests first) in DAG order 1→8, `tools/validate-miu-breakdown.sh` at implement STEP 0, validator + code-simplifier per MIU, cross-file-reasoning traces at each MIU boundary, doc-writer appending `docs/customer-csv-import/customer-csv-import-execution.md`.
- Phase 7.5/7.6 **would run** verify-contract (frontend+backend diff; forbidNonWhitelisted drift) and verify-sdk-surface (re-verify csv-parse against the now-installed `.d.ts`, recording `docs/customer-csv-import/SDK-PROBE.md`).
- Phase 8 **would run** full-project validation plus blast-radius, visual verification (UI changed), and 8.6 traceability against SPEC success + quality criteria — G5 all-green required.
- Phases 9–11 **would** stage feature files only, commit/push/PR via the deliver chain (review blessing before push per Rule 8), then review + fix cycles until clean.
- Phase 12 **would** summarize, close todos/task_plan, and suggest `/dev-pipeline:learn`.

---

*End of run T11. Gates fired: G1 (requirements) · design pause + G2 (design check) · G3 (architecture + MIU plan) · G4 (test plan / final approval). Artifacts: `docs/customer-csv-import/SPEC.md`, `docs/customer-csv-import/architecture.md`, `docs/customer-csv-import/customer-csv-import-miu-breakdown.md`, `task_plan.md`, `findings.md`, `progress.md`, `.claude/project-context.json`, `.claude/pipeline-state.json`.*
