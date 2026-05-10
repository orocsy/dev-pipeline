# Zero → Running: Design for "PRD → Ready-to-Run Repo"

> Status: design draft, 2026-05-06
> Goal: hand the system a PRD, get a deployed, CI-passing, locally-runnable
> repo back, **without the human pre-provisioning API keys for development**.

---

## 0. The user story

```
input:  prd.md (any reasonable shape — features, integrations, deploy hint)
output: github.com/<user>/<repo>
        ├─ runs locally with one command
        ├─ has CI green on first push
        ├─ has preview deploys per PR
        ├─ has prod deploy slot ready
        ├─ all dev API keys are sandbox/test (no human action required)
        ├─ prod keys are flagged TODO with the exact env var names + provider links
        └─ first feature MIU is already drafted from the PRD
```

The human's first manual action is reading the first PR, not creating accounts.

---

## 1. What we already have (audit)

| Layer | Asset | Status |
|-------|-------|--------|
| Workflow | dev-pipeline plugin (16 commands, 8 agents, 6 skills) | ✅ Solid |
| Workflow | 4 new verify-* phases (contract, blast-radius, visual, traceability) | ✅ Just added |
| Code | nodejs-fullstack-starter (Next.js 15 + Prisma 6 + Tailwind + Jest + Playwright) | ✅ Just built, minimal |
| Code | LuxeBook itself (real reference of: Turborepo, NestJS, multi-app, i18n, Docker, nginx) | ✅ Live codebase |
| Skills | 12 Node.js skills (architecture, testing, security, db, docker, caching, ts, websocket, react×2, nestjs) | ✅ User-installed |
| Skills | vercel-* family (next-forge, ai-sdk, deployment, env-vars, vercel-storage, etc.) | ✅ Installed |
| Skills | stripe-best-practices, stripe-webhooks | ✅ Installed |
| MCP | github, stripe, vercel, context7, anthropic-skills | ✅ Connected |
| Hooks | pre-commit (lint/tsc/unit), pre-push (build/blessed-SHA/doc-tick) — in starter | ✅ Just built |
| Hooks | session-start (branch staleness, MIU progress) | ✅ Just built |
| Memory | promoted learnings (8 user-level + per-project) | ✅ Active |

## 2. What's missing — the gap to "PRD in, repo out"

| Missing piece | Why we need it |
|---------------|---------------|
| **PRD parser** | Translates a markdown PRD into a structured `project-spec.json` |
| **Stack-decision engine** | Maps PRD signals → tech choices (auth lib, db, deploy target, etc.) |
| **Integration registry** | Catalog of integrations (auth/pay/email/etc) — each with code stubs, env vars, dev sandboxes, docker services, MCP/API hooks |
| **Bootstrap CLI / command** | One entrypoint: `claudeforge init <prd>` (or `/dev-pipeline:bootstrap-from-prd`) |
| **Secret-management orchestrator** | Decides per-key: provide test default vs prompt user vs skip-with-TODO |
| **Dev orchestrator** | One command starts dev: app + db + redis + stripe-cli + mailpit + tunnel as needed |
| **CI/CD generator** | Stack-aware GitHub Actions: lint/tsc/test/build/e2e/preview-deploy |
| **Deploy adapter pack** | Vercel + Fly + Render + AWS + Cloudflare presets |
| **Monitoring/observability defaults** | Sentry + Vercel Analytics + structured logs pre-wired (off by default, one-flag-on) |
| **MCP integration registry** | Per-integration MCP setup (Stripe, GitHub, etc) auto-configured into the project's `.mcp.json` |

Five of these exist as isolated assets; none of them are wired into a single flow. The design below wires them.

---

## 3. System architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User: prd.md                                 │
└────────────────────────────┬────────────────────────────────────────┘
                             ▼
                  ┌──────────────────────┐
                  │  /dev-pipeline:      │
                  │  bootstrap-from-prd  │   (new command)
                  └──────────┬───────────┘
                             ▼
        ┌────────────────────┴────────────────────┐
        │   Phase B0: PRD parse                   │
        │   skills/prd-parser/                    │   (new skill)
        │   → project-spec.json                   │
        └────────────────────┬────────────────────┘
                             ▼
        ┌────────────────────┴────────────────────┐
        │   Phase B1: Stack-decision engine       │
        │   agents/stack-decider.md               │   (new agent)
        │   reads spec → chooses integrations     │
        │   → stack-decision.md                   │
        └────────────────────┬────────────────────┘
                             ▼
                Gate G0 — user approves stack/integrations
                             │ [Y]
                             ▼
        ┌────────────────────┴────────────────────┐
        │   Phase B2: Scaffold from starter       │
        │   git clone nodejs-fullstack-starter    │
        │   apply integration patches             │
        │   apply stack-specific overrides        │
        └────────────────────┬────────────────────┘
                             ▼
        ┌────────────────────┴────────────────────┐
        │   Phase B3: Secret bootstrapping        │
        │   per integration: choose strategy      │
        │   write .env.local + .env.ci-template   │
        │   create GitHub secrets via gh CLI      │
        │   create Vercel env vars via vercel CLI │
        └────────────────────┬────────────────────┘
                             ▼
        ┌────────────────────┴────────────────────┐
        │   Phase B4: Local dev orchestrator      │
        │   docker compose up                     │
        │   verify pnpm dev boots clean           │
        │   ping every controller + a 1-route smoke│  (PR-#25 doubled-prefix lesson)
        └────────────────────┬────────────────────┘
                             ▼
        ┌────────────────────┴────────────────────┐
        │   Phase B5: CI/CD generator             │
        │   .github/workflows/ci.yml              │
        │   .github/workflows/deploy.yml          │
        │   preview-on-PR + prod-on-main          │
        └────────────────────┬────────────────────┘
                             ▼
        ┌────────────────────┴────────────────────┐
        │   Phase B6: First MIU draft from PRD    │
        │   feeds straight into /dev-pipeline:plan│
        │   → ready for human to start G1/G3/G4   │
        └────────────────────┬────────────────────┘
                             ▼
                       Repo ready ✅
                       First PR ready
                       Human reviews
```

The only **manual** human step in the bootstrap path is **G0 — approve the stack decision**. Everything else is automated.

---

## 4. Component designs

### 4.1 PRD parser (skill)

**Location:** `~/.claude/plugins/marketplaces/local/plugins/dev-pipeline/skills/prd-parser/SKILL.md`

**Input contract:** any reasonable PRD. Examples we should handle:
- Long Notion-style doc with Goals/Users/Features/Constraints
- Short bullet list ("auth, payments, dashboard, blog")
- Spec-style ("we need a multi-tenant SaaS for…")

**Output: `project-spec.json`**

```json
{
  "name": "luxebook",
  "summary": "Multi-tenant booking SaaS for nail salons",
  "users": ["salon owner", "salon staff", "end customer"],
  "features": [
    { "id": "F1", "title": "Customer books a service", "needs": ["scheduling", "auth-customer"] },
    { "id": "F2", "title": "Salon owner manages calendar", "needs": ["auth-staff", "rbac"] },
    { "id": "F3", "title": "Payments + cancellation policy", "needs": ["payments", "subscriptions"] }
  ],
  "non_functional": {
    "multi_tenant": true,
    "i18n": ["en", "zh-HK"],
    "regions": ["hong-kong"],
    "scale_target": "10-100 tenants, ~10k bookings/month"
  },
  "integrations_implied": ["auth", "database", "payments", "email"],
  "deploy_target_hint": "vercel",
  "data_sensitivity": "PII + payment metadata (PCI-via-stripe)",
  "compliance": ["GDPR-light"]
}
```

Heuristics (language-model assisted, not regex):
- "multi-tenant", "salon for…", "platform for X to Y" → multi_tenant: true
- "subscription", "billing", "checkout" → payments
- "notify", "email confirmation", "send a link" → email
- "Hong Kong", "Asia", "中文" → i18n + region hint
- "image upload", "photo", "media" → file storage
- "real-time", "live", "presence" → websockets/Pusher

If parser is unsure on any field, output `null` and the bootstrap command surfaces a single clarifying question.

---

### 4.2 Stack-decision engine (agent)

**Location:** `agents/stack-decider.md` (within dev-pipeline plugin)

**Input:** `project-spec.json` + user's installed skill inventory + user's existing project preferences (read from `~/.claude/CLAUDE.md`).

**Output: `stack-decision.md`** with decisions + rationale per layer:

```markdown
## Stack decision for luxebook

| Layer | Choice | Alternatives considered | Rationale |
|-------|--------|------------------------|-----------|
| Frontend | Next.js 15 App Router | Remix, SvelteKit | Skill `vercel-react-best-practices` already installed; team uses Next |
| Backend | Next.js API routes | NestJS | Single-app simplicity; if scale demands it later, split |
| Database | Postgres via Prisma 6 | MongoDB, Drizzle | Skill `nodejs-database-orm` has Prisma rules; multi-tenant patterns mature |
| Auth | Clerk | NextAuth, Lucia | PRD says "salon owner" + "customer" — multi-role; Clerk has Vercel integration |
| Payments | Stripe Checkout + Subscriptions | Lemon Squeezy | Skill `stripe-best-practices` available; SaaS subscriptions implied |
| Email | Resend | SendGrid | Free tier covers dev; React Email DX matches Next.js |
| File storage | UploadThing | S3 direct, Cloudflare R2 | Vercel-native; PRD doesn't imply heavy media |
| i18n | next-intl | next-i18next | App Router compat; team uses this in LuxeBook |
| Testing | Jest + Playwright | Vitest | Already in starter |
| Deploy (web) | Vercel | Render, Fly | PRD hint + skills bias |
| Deploy (db) | Vercel Postgres | Supabase, Neon | Marketplace integration; one-click |
| CI | GitHub Actions | CircleCI | Default; deploys auto via Vercel |
| Observability | Sentry + Vercel Analytics | DataDog | Stripe-tier project doesn't need DataDog |

**Stack-cost preview (monthly):**
- Vercel Pro: $20 (free tier OK for dev)
- Vercel Postgres: $20 hobby
- Clerk: free (10k MAU)
- Stripe: usage-based
- Resend: free 3k/mo
- Sentry: free 5k events/mo
**Estimated dev-month cost: $0–40**

**Approve this stack? [Y]**
```

The user accepts at G0 or asks for swaps ("use NextAuth instead of Clerk"). On any edit the engine re-runs and re-displays.

---

### 4.3 Integration registry

**Location:** `~/.claude/plugins/marketplaces/local/plugins/dev-pipeline/integrations/`

```
integrations/
├── auth/
│   ├── clerk/
│   │   ├── manifest.json          # name, version, env vars, dev-sandbox info
│   │   ├── patch/                 # files to copy into the new project
│   │   │   ├── src/middleware.ts
│   │   │   ├── src/app/sign-in/page.tsx
│   │   │   └── src/lib/auth.ts
│   │   ├── env.template            # CLERK_PUBLISHABLE_KEY=pk_test_…
│   │   ├── dev-defaults.json       # if available, public sandbox keys
│   │   └── README.md               # what this gives you, how to upgrade to prod
│   ├── nextauth/
│   └── lucia/
├── payments/
│   ├── stripe/
│   │   ├── manifest.json
│   │   ├── patch/
│   │   │   ├── src/lib/stripe.ts
│   │   │   ├── src/app/api/webhooks/stripe/route.ts
│   │   │   └── prisma/migrations/<ts>_add_stripe_columns/migration.sql
│   │   ├── env.template
│   │   ├── dev-defaults.json       # Stripe test keys (publishable test key safe to commit)
│   │   ├── compose-fragment.yml    # adds stripe-cli service for webhook forwarding
│   │   └── mcp.json                # registers @stripe MCP for the project
│   └── lemon-squeezy/
├── database/
│   ├── postgres-prisma/
│   ├── mongodb/
│   └── supabase/
├── email/
│   ├── resend/
│   ├── sendgrid/
│   └── mailpit-dev/                # local-only mock, no API needed
├── storage/
│   ├── uploadthing/
│   ├── s3/
│   └── r2/
├── observability/
│   ├── sentry/
│   ├── vercel-analytics/
│   └── posthog/
└── realtime/
    ├── pusher/
    ├── ably/
    └── supabase-realtime/
```

Each `manifest.json` shape:

```json
{
  "name": "stripe",
  "category": "payments",
  "version": "1.0.0",
  "depends_on_integrations": ["auth", "database"],
  "depends_on_packages": {
    "stripe": "^17.0.0",
    "@stripe/stripe-js": "^4.0.0"
  },
  "env_vars": {
    "STRIPE_SECRET_KEY": {
      "scope": "server",
      "required": true,
      "dev_strategy": "use_test_default",
      "dev_default": "sk_test_51M…<a public test key, safe>",
      "prod_strategy": "prompt_user",
      "prod_doc_link": "https://dashboard.stripe.com/apikeys"
    },
    "STRIPE_WEBHOOK_SECRET": {
      "scope": "server",
      "required": true,
      "dev_strategy": "stripe_cli_listen",
      "prod_strategy": "create_endpoint_then_prompt"
    },
    "NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY": {
      "scope": "client",
      "required": true,
      "dev_strategy": "use_test_default",
      "dev_default": "pk_test_…<safe>"
    }
  },
  "compose_services": ["stripe-cli"],
  "mcp_servers": ["@stripe/mcp"],
  "skills": ["stripe-best-practices", "stripe-webhooks"],
  "post_install_steps": [
    "stripe listen --forward-to localhost:3000/api/webhooks/stripe &",
    "extract STRIPE_WEBHOOK_SECRET from listen output, write to .env.local"
  ],
  "verification": {
    "dev": "curl -X POST localhost:3000/api/webhooks/stripe -d '{}' returns 400 (signature missing) not 404",
    "ci": "test/payments/webhook-signature.spec.ts must exist"
  }
}
```

Adding a new integration to the registry = `claudeforge integration scaffold <name>` produces the folder skeleton.

---

### 4.4 Secret-management orchestrator

**Three modes per env var, chosen by the integration manifest:**

| Strategy | Behavior in dev | Behavior in CI | Behavior in prod |
|----------|----------------|----------------|------------------|
| `use_test_default` | Write public sandbox key into `.env.local` automatically | Write same key as a GitHub secret via `gh secret set` | Block with TODO until human provides |
| `stripe_cli_listen` (or similar) | Run sidecar process on `pnpm dev`; capture key from stdout | Skip in CI (don't need); use a fake one for build-only | Prompt human |
| `prompt_user` | Prompt once during `bootstrap-from-prd`; never commit | Same key sent to GitHub via `gh secret set` | Same key sent to Vercel via `vercel env add` |
| `skip_with_todo` | Leave blank; surface in `.claude/docs/SECRETS_TODO.md` | Skip | Skip |
| `generate_random` | Run `openssl rand -base64 32`, write to `.env.local` + secret stores | Same | Same |

**Key insight: most dev keys are publishable / sandbox / forwarder keys that are SAFE to bake into the registry as `dev_default`.** Stripe test keys, Clerk dev instance keys, Resend dev mode, Vercel preview URLs — all safe in the open. The few that aren't (production Stripe webhook signing secret, Sentry DSN for prod project) are clearly marked `prod_strategy: prompt_user` and surfaced AFTER first deploy not before.

**Secret storage flow:**

```
.env.local                   ← dev (gitignored, populated by bootstrap)
.env.ci-template             ← committed, lists var names with TODO values
GitHub Actions secrets       ← populated via `gh secret set` during bootstrap
Vercel env vars              ← populated via `vercel env add` during bootstrap
.claude/docs/SECRETS.md      ← committed, documents which vars came from where
.claude/docs/SECRETS_TODO.md ← committed, lists vars human still needs to provide
```

The `.claude/docs/SECRETS.md` doc is regenerated whenever the integration set changes — sync hook keeps it fresh.

---

### 4.5 Dev orchestrator

**One entrypoint:** `pnpm dev`

```
package.json scripts:
  "dev": "concurrently -n web,db,workers,stripe \\
            'next dev' \\
            'docker compose up -d --wait postgres redis' \\
            'tsx scripts/dev-workers.ts' \\
            'stripe listen --forward-to localhost:3000/api/webhooks/stripe'"
```

`concurrently` (or `tsx scripts/dev.ts` for richer control) launches:
- Next.js dev
- Docker compose for stateful services (postgres, redis, mailpit if email integration)
- App-specific workers (queue runners, schedulers — only if integrations call for them)
- Stripe CLI listener (only if stripe integration enabled)
- Tunnel (ngrok/cloudflared) only if integration declares webhook callback need (e.g. payment refund webhook, OAuth callback)

The script reads `integrations.installed.json` (written at bootstrap) and decides which services to start. Adding/removing an integration updates the manifest → next `pnpm dev` picks it up.

**Health check:** before declaring ready, the orchestrator pings:
- `localhost:3000/api/health`
- every `@Controller`/route declared in code (see PR-#25 doubled-prefix lesson)
- DB connection via Prisma `$queryRaw` smoke
- Redis ping if installed

If any fail, `pnpm dev` exits with the specific failing service surfaced.

---

### 4.6 CI/CD generator

Generates `.github/workflows/`:

| File | What it does | Triggers |
|------|--------------|----------|
| `ci.yml` | lint → tsc → unit → build → e2e (against preview) → traceability | `pull_request`, `push` to `main` |
| `deploy-preview.yml` | Vercel preview deploy + smoke test | `pull_request` |
| `deploy-prod.yml` | Vercel prod deploy + post-deploy smoke + Sentry release marker | `push` to `main` (only if CI green) |
| `secret-rotate.yml` | (optional) periodic check that production secrets aren't expired | weekly cron |
| `dependency-update.yml` | dependabot config + auto-merge for patch-level deps | weekly |

The generator chooses these based on `stack-decision.md`. Vercel-deployed projects skip the AWS-ECS workflow; Fly-deployed projects skip Vercel.

---

### 4.7 Deploy adapter pack

```
plugins/dev-pipeline/deploy-adapters/
├── vercel/
│   ├── adapter.md              # how to detect, what files to write
│   ├── config-template.json    # vercel.json with framework presets
│   └── env-sync.sh             # vercel env pull/push helpers
├── fly/
│   ├── adapter.md
│   └── config-template.toml
├── render/
├── aws-ecs/
├── cloudflare-workers/
└── self-hosted-docker/
```

The bootstrap picks the adapter based on `deploy_target_hint` from PRD or `stack-decision.md`. Already partially exists — `/dev-pipeline:deploy` is the adapter dispatcher.

---

### 4.8 MCP integration registry

For each installed integration, the bootstrap also writes its `mcp_servers` list into the project's `.mcp.json`:

```json
{
  "mcpServers": {
    "stripe": { "command": "npx", "args": ["@stripe/mcp"], "env": { "STRIPE_API_KEY": "$STRIPE_SECRET_KEY" } },
    "github": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"], "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "$GITHUB_TOKEN" } },
    "vercel": { "command": "npx", "args": ["-y", "@vercel/mcp"] },
    "context7": { "command": "npx", "args": ["-y", "@upstash/context7-mcp"] },
    "filesystem": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "$PWD"] }
  }
}
```

Future Claude Code sessions on the project auto-load these. No manual MCP wiring per project.

---

## 5. Concrete artifacts (build-list)

### Tier 1 — minimum viable PRD→running (build first)

| Artifact | Type | Where it lives | Effort |
|----------|------|----------------|--------|
| `prd-parser` skill | Skill | dev-pipeline plugin | 1 day |
| `stack-decider` agent | Agent | dev-pipeline plugin | 1 day |
| `bootstrap-from-prd` command | Command | dev-pipeline plugin | 1 day |
| Integration registry: 5 base integrations (postgres-prisma, clerk, stripe, resend, sentry) | Each integration folder + manifest + patch | dev-pipeline plugin | 3 days |
| Secret orchestrator | Code lib + command | dev-pipeline plugin | 2 days |
| Vercel + Fly deploy adapters | Already partially there | dev-pipeline plugin | 1 day finish |
| nodejs-fullstack-starter v0.2 with integration-patch slots | Update existing starter | starter repo | 1 day |
| GitHub workflow templates | Templates | dev-pipeline plugin `templates/.github/workflows/` | 1 day |

**Tier 1 total: ~11 days of focused work.**

### Tier 2 — production polish

- `boot+smoke every controller route` check (lesson from PR #25)
- Visual baseline registry per project (lesson from phone-component bug)
- MCP servers per integration auto-wired
- Auto-create execution doc shells at MIU 1
- Numbered scenario tables in test-planner output
- Migration idempotency lint
- 8 more integrations (lucia, drizzle, supabase, mongodb, lemon-squeezy, ably, posthog, uploadthing)

**Tier 2 total: ~8 days.**

### Tier 3 — autonomous polish

- AI-driven PRD clarification dialog (single Q at a time)
- Cost preview per stack (real Vercel/Stripe pricing API queries)
- Auto-add observability tier scaling (Sentry plan recommendations)
- One-command rotation of all keys at expiry
- "What changed since last release" doc generator

---

## 6. The CLI surface

Two equally valid front doors:

**Front door A — slash command (preferred, no install):**
```
/dev-pipeline:bootstrap-from-prd ./my-prd.md
```
Runs entirely inside Claude Code. The plugin already loads. Zero new CLI to install.

**Front door B — standalone CLI (for non-Claude users / scripts):**
```bash
npx claudeforge init my-prd.md
npx claudeforge integration add stripe
npx claudeforge secrets pull
npx claudeforge deploy preview
```

`claudeforge` is a thin wrapper over the plugin's command surface — same logic, different invocation. Build only after Tier 1 lands.

---

## 7. PRD → first MIU example (end-to-end walk-through)

Imagine you give it this 6-line PRD:

> *"A booking platform for small dental clinics. Each clinic has staff and patients. Patients book appointments online with a deposit; if they cancel >24h before, refund 50%. Staff sees a calendar dashboard. Bilingual EN+zh-HK."*

What happens:

1. `prd-parser` → spec.json:
   - multi_tenant: true (clinics)
   - i18n: ['en', 'zh-HK']
   - features: book_appt, deposit, cancel_policy, calendar_dashboard, staff_login, patient_login
   - integrations_implied: auth, payments, database, email
   - deploy hint: vercel (default)

2. `stack-decider` → stack-decision.md:
   - Next.js 15 + Postgres+Prisma + Clerk (multi-role) + Stripe + Resend + next-intl + Vercel
   - Cost: $0–40/mo
   - **G0 — approve? [Y]**

3. `bootstrap-from-prd` runs:
   - Clones `nodejs-fullstack-starter`
   - Applies clerk patch (middleware, sign-in page, role types)
   - Applies stripe patch (webhook route, lib, prisma migration)
   - Applies prisma patch (schema with Clinic, Staff, Patient, Appointment models seeded from the spec)
   - Applies next-intl patch (locales config, en.json + zh.json with feature labels stubbed)
   - Writes `.env.local` with: Clerk dev keys (from registry), Stripe test keys, Resend free-tier key (or mailpit local), Postgres URL pointing at docker-compose
   - Writes `.github/workflows/{ci,deploy-preview,deploy-prod}.yml`
   - Writes `.claude/docs/{PROJECT_STATUS,ARCHITECTURE,RECENT_CHANGES,SECRETS,SECRETS_TODO}.md`
   - Sets up `.mcp.json` with stripe + github + vercel + context7

4. `secrets bootstrap`:
   - All Tier-A "use_test_default" keys: written to `.env.local`, also pushed to GitHub Actions secrets via `gh secret set` (so CI works on first push)
   - Vercel env: pushed via `vercel env add ... preview` and `... production` for dev keys; prod-key slots created with placeholder + clear TODO

5. `dev orchestrator validates`:
   - `docker compose up -d --wait`
   - `pnpm dev` boots
   - smokes: `/api/health` 200, every controller pings, prisma `SELECT 1` works
   - all green → emit "ready"

6. `first-MIU draft`:
   - Pulls F1 from spec.json ("Patient books appointment")
   - Runs `/dev-pipeline:plan` against it
   - Generates G1 questions, MIU breakdown, test plan
   - **G1 — approve? [Y]** ← **first place a human is needed**

The human's first decision is on a feature plan, not on a Docker config or an env var.

---

## 8. What doesn't go in this system (deliberate)

- **Domain logic.** No "booking-concurrency-pattern" or "tenant-isolation-audit" in the registry. Those are LuxeBook-specific. The starter+plugin stay generic. Domain skills can be **added per project** as side-loaded skills in `.claude/skills/`.
- **Visual design system.** Each project picks its own (shadcn, Park UI, Mantine, hand-rolled). Starter uses Tailwind + bare components.
- **Auth strategy.** Multiple options in the registry; PRD signals choose. Not opinionated.
- **State management.** Server Components first; client state lib added per-PRD signal.
- **Auto-scale infra.** Vercel/Fly handle this automatically; we don't generate Terraform.

---

## 9. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Test default keys in registry leak / get abused | Use ONLY publishable/sandbox keys in registry. Document strictly. Audit on every integration PR. |
| Stack-decider picks badly | Always go through G0 with rationale + alternatives. User can swap any choice. |
| PRD parser hallucinates | Output `null` on uncertain fields; bootstrap surfaces clarifying Q. |
| Integration patches go stale | Each integration has a `version` + a smoke test in CI. Stale integrations are flagged. |
| Bootstrap creates broken project on edge cases | Bootstrap ends with verify-* phases (contract / blast-radius / visual / traceability) — same gates LuxeBook now has. If verify fails, bootstrap rolls back the unstaged changes. |
| Vercel / GitHub CLI not authenticated | Detect at start, prompt to `gh auth login` / `vercel login` once, then proceed. |

---

## 10. Build sequence (recommended order)

### Week 1 — minimum-viable bootstrap
- [ ] `prd-parser` skill
- [ ] `stack-decider` agent
- [ ] `bootstrap-from-prd` command (skeleton — read PRD, write skeleton)
- [ ] Integration registry shape + manifest schema
- [ ] First integration: postgres-prisma (least surprising, validates the registry shape)

### Week 2 — payments + auth path
- [ ] Integration: clerk
- [ ] Integration: stripe
- [ ] Secret orchestrator (test_default + prompt_user strategies only)
- [ ] CI workflow templates (ci.yml only)

### Week 3 — full happy path
- [ ] Integration: resend, sentry
- [ ] Vercel deploy adapter
- [ ] Dev orchestrator with health-smoke check
- [ ] Update nodejs-fullstack-starter to v0.2 with integration-patch slots

### Week 4 — polish + docs
- [ ] All G0/G1 gate UX polish (`[Y]` prompts, scenario tables)
- [ ] First end-to-end run on a real PRD
- [ ] Self-host the design (this doc) inside the dev-pipeline plugin so future Claude sessions know the system exists

After Week 4: hand it a PRD, see what comes out, iterate.

---

## 11. The "minus zero" check

What can a human still need to do AFTER `bootstrap-from-prd` finishes?

| Action | Required? | When |
|--------|-----------|------|
| Approve stack at G0 | Yes | Once |
| Approve first MIU plan at G1 | Yes | Once per feature |
| Provide production Stripe keys | Yes | Before first prod deploy |
| Provide Sentry prod DSN | Yes | Before first prod deploy |
| Choose a domain | Yes | Before first prod deploy (Vercel free `*.vercel.app` works for dev) |
| Set up local Postgres | NO | docker-compose handles it |
| Set up Stripe webhook URL | NO | stripe CLI listen handles it for dev |
| Generate JWT secret | NO | bootstrap generates with `openssl rand` |
| Wire env vars to Vercel | NO | bootstrap pushes via vercel CLI |
| Wire CI secrets | NO | bootstrap pushes via gh CLI |
| Configure GitHub Actions | NO | templates copied in |
| Pick Tailwind config | NO | starter ships with sensible default |
| Set up Prisma migrations | NO | initial migration generated from spec model section |

So: **G0 + first feature G1 + 3 prod-only key slots are the entire human surface.** That's the design target.

---

## 12. Where the LuxeBook lessons land in this design

Every workflow lesson from the retrospective lands somewhere here:

| LuxeBook lesson | Lands as |
|-----------------|----------|
| "Tests green ≠ correct" (PR #25 doubled prefix) | Health check pings every controller route in step B4 |
| "Local validation ≠ CI" (PR #58 timezone) | Verify-blast-radius + env-invariance test template in starter |
| "Replace_all leaves stragglers" | Post-edit grep hook (already in starter) |
| "Hooks shipped as no-ops" | Adversarial test of hooks on first install |
| "Auto-merge violation" | `gh pr merge` is hard-denied in `.claude/settings.json` |
| "Hand-rolled regex" | Library-first directive in user CLAUDE.md + skill router |
| "Branched off stale main" | session-start.sh staleness check (already in starter) |
| "Self-review skipped" | pre-push blessed-SHA gate (already in starter) |
| "E2E faked/skipped" | Headed-by-default e2e in starter; verify-visual phase mandatory for UI MIUs |
| "Compaction destroys task state" | progress.md writes after every MIU; first 3 user instructions snapshotted at PreCompact |
| **Y-gate language** | bootstrap mirrors LuxeBook G1/G3/G4 phrasing exactly |
| **MIU vocabulary** | dev-pipeline plugin (already does this) |
| **Per-MIU execution doc** | bootstrap creates `docs/<feature>/execution.md` shell at MIU 1 |
| **Numbered scenario tables** | test-planner agent's mandatory output format |
| **Best-effort post-commit** | Generic side-effect helper added to starter |
| **Idempotent migration declaration** | Pre-commit lint on migration files |

---

## 13. Open questions (need a call before building)

1. **Plugin or standalone CLI?** I lean plugin-first (`/dev-pipeline:bootstrap-from-prd`) because no install. CLI later. **You okay with that?**
2. **Integration count for v1.** Is 5 (postgres+clerk+stripe+resend+sentry) the right Tier 1 set, or do you want different ones (e.g. supabase instead of clerk+postgres)?
3. **Where does this design doc live long-term?** It's in `nodejs-fullstack-starter/docs/` now. Could move to the dev-pipeline plugin so future sessions auto-load it.
4. **Naming.** "claudeforge"? "stackforge"? "kit"? I'm easy.
5. **Test-default key registry maintenance.** Who owns rotating test sandbox keys when providers update them? I'd say: maintain an `integrations/_health.yml` checked monthly via cron-skill.

---

## 14. What I'd ship this week (smallest useful slice)

If you bless Tier 1 scope:
- **Day 1**: prd-parser + stack-decider + bootstrap-from-prd skeleton, single integration (postgres-prisma), end-to-end demoable on a 1-page PRD that produces a runnable Next.js app with a working DB
- **Day 2**: add stripe integration with test-default keys + stripe CLI sidecar, demo a payment-flow PRD
- **Day 3**: GitHub Actions CI template + Vercel deploy adapter, demo a PR with green CI + preview URL
- **Day 4**: clerk + resend integrations, demo full-stack auth + email PRD
- **Day 5**: polish, docs, write Tier-2 backlog

End-of-week demo: feed it the dental-clinic PRD from §7, push the first commit, click the Vercel preview link.

---

*Status: design only. No code written for this system yet. The four `verify-*` commands and the `nodejs-fullstack-starter` are downstream prerequisites that already exist.*

---
---

# Part II — Advanced design (2026-05-07 update)

After feedback: drop the brand-naming question, drop the test-key maintenance,
restate Tier 1 in free-tier terms, and design the agent-internal CLI properly.

---

## 15. Decisions locked from feedback

| Question | Decision |
|----------|----------|
| 1. Plugin or CLI? | **Both, layered.** Core lib in TS, agents call via CLI binary OR MCP server OR slash command. See §17. |
| 2. Tier 1 integrations | **Free-tier-only.** Re-specced in §16. |
| 3. Long-term home of the design | **dev-pipeline plugin.** This doc gets symlinked into `~/.claude/plugins/marketplaces/local/plugins/dev-pipeline/docs/` so future sessions auto-load it. |
| 4. Naming | **No brand.** It's the dev-pipeline plugin's bootstrap subsystem. Folders: `bootstrap/`, `integrations/`, `deploy-adapters/`. CLI binary (if needed) is `dev-pipeline-cli`. Saves us trademark/marketing noise; the artifacts are what matter. |
| 5. Test-key maintenance | **None.** If a baked-in sandbox key fails, the integration is re-set up by the next bootstrap. No cron, no health-watcher. |

---

## 16. Free-tier-only integration matrix (replaces §4.3 stack)

Every Tier 1 integration must be **provably free for dev + small prod usage**, with documented limits and a clear paid-tier upgrade path.

### Tier 1 free-tier matrix

| Layer | Choice | Free tier | Why this over alternatives |
|-------|--------|-----------|---------------------------|
| Hosting (web) | **Vercel Hobby** | 100GB bandwidth, 100k function exec/mo, custom domains, preview URLs | Tightest Next.js integration; deploys are zero-config |
| Database | **Neon (Postgres)** | 0.5GB storage, 1 compute, **PR DB branching free**, 100h compute time/mo | Branching gives per-PR isolated DBs (huge for E2E); Vercel marketplace 1-click |
| Auth | **Clerk** | 10k MAU, social login, MFA, sessions | Multi-role from day 1 (PRD often implies it); Vercel marketplace 1-click |
| Payments | **Stripe (test mode)** | Free; only pay on real txn | No alternative for serious payments at this maturity |
| Email | **Resend** | 100/day, 3k/month, custom domain (verified) | React Email DX, Vercel marketplace, 30-line setup |
| File storage | **Cloudflare R2** | 10GB storage, 1M Class-A ops/mo, 10M Class-B ops/mo, **zero egress fees** | Better free tier than UploadThing/S3/Vercel Blob; egress is the killer everywhere else |
| Background jobs | **Inngest** | 50k steps/mo, retries, observability dashboard | Vercel marketplace; type-safe; works with Next.js out of box |
| Caching / rate limit | **Upstash Redis** | 10k commands/day, REST API, durable | Edge-compatible; works in Vercel functions; 1-click marketplace |
| Feature flags | **Vercel Edge Config** | 50KB store, free reads, edge-cached | Already Vercel-native; alternative is PostHog free flags |
| Error tracking | **Sentry** | 5k errors, 10k traces, 50 replays per month | Industry standard; Next.js plugin handles SSR/edge cleanly |
| Web analytics | **Google Analytics 4** | Free, unlimited events | User explicitly chose; non-Vercel-locked; can add Vercel Analytics later as overlay |
| AI / LLM (optional) | **Vercel AI Gateway** | Free; pay providers directly | Single API across providers; built-in caching cuts cost; only enabled if PRD implies AI |
| Search (optional) | **Meilisearch self-hosted** | Free in docker-compose; or Meilisearch Cloud free 10MB | Free both ways; self-hosted is unlimited |
| CI | **GitHub Actions** | 2k mins/mo private, unlimited public | Default everywhere |
| Component library | **shadcn/ui** | Free; copies into your repo (no dependency) | No vendor lock; user owns the code; widely adopted |
| Visual regression | **`/dev-pipeline:verify-visual` (self-hosted)** | Free; uses Playwright headed + screenshot diff | Already built in Phase 8.2 |

**Estimated dev-month cost: $0.** Production cost only when scale exceeds free tiers.

### Free-tier graceful upgrade signals

The bootstrap surfaces a `.claude/docs/SCALE_THRESHOLDS.md` showing where each integration tips into paid:

```
Cloudflare R2:   alert at 8GB stored / 800k Class-A / 8M Class-B
Neon Postgres:   alert at 80h compute / 0.4GB storage
Clerk:           alert at 8k MAU
Resend:          alert at 80/day or 2.5k/month
Upstash:         alert at 8k commands/day
Sentry:          alert at 4k errors/month
Inngest:         alert at 40k steps/month
```

A weekly Vercel cron job (free) reads provider APIs and posts a Slack/email digest if any threshold is crossed. Wired to the integration's manifest, so adding a new integration auto-includes its threshold.

---

## 17. Layered architecture: agent-internal CLI design

The user clarified: the CLI is **for agents to invoke**, not for humans to type. That changes the design — it's an internal automation surface, not a UX. Best practice:

```
┌──────────────────────────────────────────────────────────────┐
│ Layer 4 — Surfaces (agent-callable, thin)                    │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌───────┐ │
│ │ Slash command│ │ MCP server   │ │ CLI binary   │ │ HTTP  │ │
│ │ /dp:bootstrap│ │ tools.json   │ │ dev-pipeline │ │ (opt) │ │
│ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └───┬───┘ │
└────────┼────────────────┼────────────────┼─────────────┼─────┘
         │                │                │             │
         └────────────────┴────────┬───────┴─────────────┘
                                   │  (all delegate to)
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│ Layer 3 — Orchestration (workflow, ~200-400 LOC)             │
│ • runs phases B0..B6 in order                                 │
│ • manages rollback journal                                    │
│ • emits events to .claude/agent-events.jsonl                  │
└──────────────────────────────────┬───────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│ Layer 2 — Domain modules (testable, pure, ~1500 LOC total)   │
│ • prd-parser     • stack-decider   • integration-applier      │
│ • secret-broker  • ci-generator    • dev-orchestrator         │
└──────────────────────────────────┬───────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│ Layer 1 — Primitives (~500 LOC)                              │
│ • file ops (idempotent write/patch)                           │
│ • shell exec with audit                                       │
│ • git ops (branch, commit, push)                              │
│ • Zod schemas for every contract                              │
│ • integration-manifest validator                              │
└──────────────────────────────────────────────────────────────┘
```

### Why four surfaces

| Surface | When the agent picks it | Trade-off |
|---------|------------------------|-----------|
| Slash command | Inside Claude Code, zero install | Locked to Claude Code |
| MCP server | Any LLM agent runtime (Claude API, OpenAI, etc.) | Standard tool-calling protocol; auto-discovered |
| CLI binary | Headless / cron / shell scripts | Most portable; works in any subprocess context |
| HTTP (optional) | Cross-machine / GitHub Action runner | Only if needed for cloud-side bootstrap |

All four are <100-line wrappers over Layer 3. **Don't duplicate logic across surfaces.** Tests live at Layer 2; surfaces only add I/O glue.

### Implementation contract per surface

```ts
// Layer 4 (slash command implementation)
async function bootstrapFromPrd(prdPath: string): Promise<BootstrapResult> {
  return Orchestrator.bootstrap({ prdPath, mode: 'interactive' });
}

// Layer 4 (MCP server tool)
{
  name: 'bootstrap_from_prd',
  description: '...',
  inputSchema: BootstrapInputSchema, // Zod -> JSON Schema
  handler: async (args) => Orchestrator.bootstrap({ ...args, mode: 'mcp' })
}

// Layer 4 (CLI binary)
program.command('init <prd>').action(async (prd) =>
  Orchestrator.bootstrap({ prdPath: prd, mode: 'cli' })
);
```

The `mode` flag tells the orchestrator how to surface clarifying questions:
- `interactive` (slash) — pauses for user input via the chat
- `mcp` — returns a `needs_input` response that the calling agent re-invokes after gathering
- `cli` — exits with non-zero + JSON to stderr if input is needed
- `headless` — fails fast if any decision is ambiguous

### Why this beats "just slash commands"

1. **Replay / batch / cron** — CI can run `dev-pipeline init my.prd.md --mode headless` to scaffold a project automatically when a PRD is committed.
2. **Multi-agent** — one orchestrator, many caller agents (Claude, Codex, custom). Same audit trail.
3. **Local testability** — Layer 2 is pure. Each module testable without Claude Code.
4. **Drift safety** — surfaces are thin enough that bugs concentrate in Layer 2/3 where tests live.

---

## 18. Spec as single source of truth (SSOT)

Every artifact in the project derives from `project-spec.json`. Re-running the bootstrap with an updated spec re-applies the diff — no manual sync.

```
project-spec.json (the only file humans edit)
  ├── data_model[]         → prisma/schema.prisma
  ├── api_routes[]         → src/app/api/**/*.ts (handler stubs + tests)
  ├── features[]           → docs/<feature>/execution.md (per-MIU shells)
  ├── integrations[]       → patches applied
  ├── secrets[]            → .env.local + GitHub + Vercel pushed
  ├── ci_workflows[]       → .github/workflows/*.yml
  ├── deploy_target        → adapter config files
  └── observability[]      → instrumentation.ts + sentry.client.ts etc.
```

Each derived artifact has a header comment:
```ts
// AUTO-GENERATED from project-spec.json (#data_model.User)
// Edit project-spec.json + re-run `/dev-pipeline:sync-spec` to regenerate.
// Manual edits below the fence are preserved.
//
// — fence —
```

`/dev-pipeline:sync-spec` regenerates only the **above-fence** portion. Everything below the fence is human-owned and never touched. This pattern is the same one shadcn/ui uses for its CLI — makes the codegen non-destructive.

### Why SSOT > convention-only generation

- **No ambiguity** about which way changes flow (spec → code, never reverse)
- **Reviewable diffs**: re-sync produces a normal git diff
- **Spec is testable**: schema validation catches typos / impossible states before any code is generated
- **AI-friendly**: agents have a structured target instead of guessing project conventions

### Spec format (Zod schema)

```ts
const ProjectSpec = z.object({
  meta: z.object({
    name: z.string().regex(/^[a-z][a-z0-9-]*$/),
    description: z.string().min(10),
    version: z.string().default('0.0.1'),
  }),
  data_model: z.array(EntitySpec),
  api_routes: z.array(RouteSpec),
  features: z.array(FeatureSpec),
  integrations: z.array(IntegrationRef),
  deploy: DeploySpec,
  observability: ObservabilitySpec,
  // …
});
```

Versioned schema. Spec migrations between versions are auto-applied like Prisma migrations.

---

## 19. Per-PR isolated preview environments

Free-tier-friendly per-PR isolation using Neon DB branching + Vercel preview deploys + Clerk preview instance:

```
PR opened
  ├── GH Action calls Neon API: create branch from main DB → returns DATABASE_URL_pr_42
  ├── GH Action calls Clerk API: create preview instance → returns CLERK_PREVIEW_KEYS
  ├── Vercel preview deploy with DATABASE_URL_pr_42 + CLERK_PREVIEW_KEYS injected
  ├── Playwright e2e against preview URL (real DB, real auth)
  └── On PR close: tear down branch + Clerk instance (free again)
```

Why this matters:
- Bug-cause #4 ("Local green ≠ live green") goes away — every PR has its own real environment
- E2E tests run against production-like infra, not localhost mocks
- Multiple devs / agents can work concurrently without DB contention

Wired into the registry — Neon manifest includes the workflow YAML; Clerk manifest includes its preview-instance script.

---

## 20. AI-native defaults (optional integration tier — portable, free-OSS first)

When PRD implies AI features ("chatbot", "summarize", "generate", "agent"), bootstrap pre-wires a stack with **no Vercel-specific service** and a clear migration path off Vercel hosting itself:

| Layer | Choice | License / Free? | Why this not Vercel AI Gateway |
|-------|--------|----------------|-------------------------------|
| LLM library | `ai` npm SDK (Vercel) | **MIT, free** | The SDK itself is open source and provider-agnostic — runs anywhere Node runs, talks to any LLM directly. *Different product* from Vercel AI Gateway (the paid hosted proxy). |
| Default provider | **Google Gemini Flash** via `@ai-sdk/google` | Free tier: 1500 RPD, no card | Most generous free LLM tier on the market right now |
| Alternative providers (one env var swap) | OpenRouter (pay-as-you-go, no monthly), Groq (free fast inference), Cloudflare Workers AI (generous free; same vendor as R2 in our matrix) | All free or no-monthly | Bootstrap writes adapters for all four; switching is `MODEL_PROVIDER=groq` |
| Optional gateway (provider failover + routing) | **LiteLLM self-hosted** | MIT, free | Drop-in proxy across 100+ providers; replaces Vercel AI Gateway exactly |
| Optional observability | **Langfuse** (self-host or free cloud 50k traces/mo) OR **Helicone** (self-host or free cloud) | MIT / Apache 2.0 | Replaces Vercel AI Gateway's observability |
| Caching | Upstash Redis (already in our base matrix) | Free 10k cmds/day | Replaces Vercel AI Gateway's cache |
| Agent runtime | Native Next.js route + AI SDK streaming OR **Inngest** (already in our matrix) for durable workflows | Free | Replaces "Vercel Workflow" need |
| Chat UI components | **assistant-ui** (MIT, purpose-built) OR shadcn-based custom | MIT, free | No lock |
| Local dev / privacy fallback | **Ollama** | MIT, free | Run Llama 3 / Mistral locally — $0 inference |

**Default config when AI integration is enabled:**

```ts
// src/lib/ai.ts (auto-generated)
import { google } from '@ai-sdk/google';
import { generateText, streamText } from 'ai';

export const model = google(process.env.AI_MODEL ?? 'gemini-2.0-flash-exp');

// To swap: change MODEL_PROVIDER env var.
// Adapters wired by bootstrap: google | openrouter | groq | cloudflare | ollama
```

Project owners get free inference + zero vendor lock-in. If they later want Vercel AI Gateway, it's still a drop-in (the `ai` SDK supports it). If they want to leave Vercel hosting entirely, the AI stack moves with them — see §29.

### Pattern: project as MCP host (unchanged from earlier draft)

The bootstrap can wire the project's own domain logic as MCP tools accessible to the AI feature. Example:
```
src/lib/mcp-server.ts  ← exposes "lookup_user", "create_booking" etc as MCP tools
src/app/api/agent/route.ts ← AI feature route uses ai SDK,
                              tools = mcp-server.tools
```

Same architecture the Anthropic Agent SDK + Vercel AI SDK both encourage — the project IS its own tool surface.

---

### Pattern: project as MCP host

The bootstrap can wire the project's own domain logic as MCP tools accessible to the AI feature. Example:
```
src/lib/mcp-server.ts  ← exposes "lookup_user", "create_booking" etc as MCP tools
src/app/api/agent/route.ts ← AI feature route uses Vercel AI SDK + Vercel AI Gateway,
                              tools = mcp-server.tools
```

This is exactly the architecture the Anthropic Agent SDK + Vercel AI SDK both encourage — the project IS its own tool surface.

---

## 21. Reproducibility, idempotency, rollback

Three properties the bootstrap must satisfy:

### 21.1 Reproducibility

Same `project-spec.json` + same registry version + same starter version = same output (modulo timestamps and randoms).

How:
- Pin starter to a commit SHA in `bootstrap-config.json`
- Pin every integration manifest version
- Pin Node.js + pnpm version via `.nvmrc` + `packageManager` field
- Use `pnpm install --frozen-lockfile` in CI
- Generated files include `Generated-By: dev-pipeline@vX.Y.Z` header
- A `bootstrap.lock` file records every decision (chosen integrations, generated values, package versions resolved)

Why: rebuilding identical projects is a debug superpower. "It worked yesterday" → diff `bootstrap.lock` against today's run.

### 21.2 Idempotency

Re-running `bootstrap-from-prd` on an existing project should be safe — only apply diffs.

How:
- Each integration patch declares which files it owns + a content hash
- Re-apply checks: `if hash matches, skip; if no hash recorded, apply; if hash changed (human edited), prompt 3-way merge`
- Generated files use the fence pattern from §18 — only above-fence regenerates
- Migration files are append-only; never edited

### 21.3 Rollback

If step B5 fails, undo B0..B4 cleanly.

How:
- Phase steps emit events to `.claude/.bootstrap-journal.jsonl`
- Each event has its inverse declared in the integration manifest:
  - `applied_patch: stripe/v1` → inverse: `git apply -R stripe/v1.patch`
  - `pushed_secret: STRIPE_SECRET_KEY → vercel` → inverse: `vercel env rm STRIPE_SECRET_KEY`
  - `pushed_secret: → github` → inverse: `gh secret remove`
- On failure: replay journal in reverse, executing inverses
- Bootstrap exits with exit code + a markdown rollback summary

Same pattern as DB migrations: every up has a down. Forces integration authors to think about uninstall.

---

## 22. Composable patches + conflict detection

Integrations must be orthogonal. Two integrations should never edit the same line.

How:
- Each integration declares the **files it owns** (exclusive) and the **files it appends to** (shared, with a marker comment)
- Pre-flight runs over all chosen integrations: detect file-ownership conflicts → fail fast with a clear message
- Shared files (e.g. `prisma/schema.prisma`, `src/middleware.ts`) use a marker-comment system:

```ts
// src/middleware.ts (auto-managed by dev-pipeline)
// === @clerk/middleware === 
import { clerkMiddleware } from '@clerk/nextjs/server';
// === /@clerk/middleware ===

// === @upstash/ratelimit === 
import { ratelimit } from '@/lib/ratelimit';
// === /@upstash/ratelimit ===

export default clerkMiddleware(async (auth, req) => {
  // === @upstash/ratelimit:body === 
  const { success } = await ratelimit.limit(req.ip ?? 'anonymous');
  if (!success) return Response.json({ error: 'Rate limited' }, { status: 429 });
  // === /@upstash/ratelimit:body ===
  // ... auth logic from clerk
});
```

- `dev-pipeline integration add upstash-ratelimit` inserts only inside its own marker block
- `dev-pipeline integration remove upstash-ratelimit` removes only inside its own marker block
- Manual edits between markers are preserved across re-runs

Same pattern as VS Code workspace files / GitHub workflows. Mature, debuggable.

---

## 23. Devcontainer + Codespaces (cloud dev env)

The starter ships a `.devcontainer/devcontainer.json` so the user doesn't need local docker:

```json
{
  "name": "fullstack-dev",
  "image": "mcr.microsoft.com/devcontainers/typescript-node:20",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
  "postCreateCommand": "pnpm install && pnpm db:generate && pnpm db:migrate",
  "postStartCommand": "docker compose up -d --wait && pnpm dev",
  "forwardPorts": [3000, 5432, 6379],
  "secrets": {
    "STRIPE_SECRET_KEY": { "description": "Stripe test key (will use registry default if empty)" },
    "..."
  }
}
```

GitHub Codespaces reads this and gives a ready-to-code environment in <30s, with all secrets pulled from Codespaces secrets store. No local install of docker / node / postgres needed.

For agents running on cloud workers: they get the same experience — bootstrap a Codespace via API, attach to it, code, commit.

---

## 24. Drift detection + re-sync

Projects evolve. After 6 months, the project may have diverged from registry expectations. `/dev-pipeline:health` (already exists) is upgraded to detect drift:

| Drift signal | Detection | Auto-fix? |
|--------------|-----------|-----------|
| Integration patch hash changed | `git hash-file` vs manifest's `expected_hash` | Prompt 3-way merge |
| Spec → code divergence | Re-run codegen in dry-run; show diff | Show diff, ask user |
| Dep versions behind registry | Compare package.json vs manifest's `depends_on_packages` | Bump via Renovate PR |
| Free-tier scale threshold crossed | Provider API check | Send alert; suggest upgrade |
| .env.example missing keys present in code | Grep `process.env.X` not in `.env.example` | Add to .env.example |
| Generated file edited in fenced section | Hash check on fenced region | Refuse re-sync; show conflict |

Run via cron (Vercel free) weekly. Outputs to `.claude/docs/HEALTH.md`. PR auto-opened if any auto-fix is safe.

---

## 25. Bootstrap telemetry + audit trail

Every decision the orchestrator makes is logged to `.claude/agent-events.jsonl`:

```jsonl
{"ts":"...","phase":"B0","event":"prd_parsed","outcome":"ok","summary":"6 features, 4 integrations implied"}
{"ts":"...","phase":"B1","event":"stack_decided","outcome":"ok","integrations":["postgres-prisma","clerk","stripe","resend","sentry"]}
{"ts":"...","phase":"B1","event":"alternatives_considered","outcome":"ok","data":{"auth":["clerk","nextauth","lucia"]}}
{"ts":"...","phase":"B1","event":"user_approved_at_g0"}
{"ts":"...","phase":"B2","event":"patch_applied","integration":"clerk","files":3}
{"ts":"...","phase":"B3","event":"secret_provisioned","key":"CLERK_PUBLISHABLE_KEY","strategy":"use_test_default","stores":["env.local","github","vercel"]}
{"ts":"...","phase":"B4","event":"smoke_passed","routes_pinged":12}
{"ts":"...","phase":"B5","event":"ci_workflow_written","files":["ci.yml","deploy-preview.yml","deploy-prod.yml"]}
{"ts":"...","phase":"B6","event":"first_miu_drafted","feature_id":"F1"}
{"ts":"...","phase":"DONE","duration_ms":143000,"errors":0}
```

The audit trail is the source-of-truth for:
- "Why was this integration chosen?" — `git grep stack_decided .claude/agent-events.jsonl`
- "Was this secret rotated?" — `git grep secret_provisioned`
- Replay via `dev-pipeline replay --journal .claude/agent-events.jsonl` for debugging

Bonus: opt-in anonymous telemetry to a self-hosted endpoint helps the registry author see which PRDs fail to parse, which integrations 404 on patch apply, etc. Off by default; project owner enables in `.claude/settings.json`.

---

## 26. Updated Tier 1 build plan (all free-tier)

**Day 1**
- Layer 1 primitives (file ops, shell exec, git ops, Zod schemas) — ~500 LOC
- Layer 2 modules: prd-parser + stack-decider — ~400 LOC
- Layer 4: slash command thin wrapper

**Day 2**
- Layer 2: integration-applier with marker-comment system
- Layer 1: rollback journal + idempotency hash check
- First integration: `postgres-neon-prisma` (because Neon branching is the most differentiated free feature)

**Day 3**
- Integration: `clerk` (auth)
- Layer 2: secret-broker with the 5 strategies
- Devcontainer template baked into starter

**Day 4**
- Integration: `stripe` (test mode + stripe-cli sidecar)
- Layer 2: dev-orchestrator with concurrent service launcher + smoke check
- CLI binary surface (Layer 4)

**Day 5**
- Integration: `resend` + `r2-cloudflare` + `sentry` + `google-analytics`
- Layer 4: MCP server surface
- CI workflow templates: ci.yml + deploy-preview.yml + deploy-prod.yml

**Day 6**
- End-to-end demo on the dental-clinic PRD from §7
- Per-PR isolated env (Neon branching + Clerk preview)
- HEALTH.md drift detector

**Day 7**
- Polish, fence-marker validation, error messages, docs
- Inngest integration (background jobs, free tier)
- Upstash Redis integration (rate limit, free tier)

End of Week 1: working `bootstrap-from-prd` against a real PRD, all dev infra free tier.

**Tier 2 (Week 2)**: Vercel Edge Config (feature flags), Meilisearch (search), AI integration (Vercel AI SDK + Gateway), Codespaces config, scale-threshold cron.

---

## 27. The "minus zero" check, restated

After Week 1 ships, what does the human still do?

| Action | Required? | When |
|--------|-----------|------|
| Approve stack at G0 | Yes | Once at bootstrap |
| Approve first feature plan at G1 | Yes | Once per feature |
| `gh auth login` if not authed | Yes | Once per machine |
| `vercel login` if not authed | Yes | Once per machine |
| Provide prod-only Stripe keys | Yes | Before first prod deploy |
| Provide prod-only Sentry DSN | Yes | Before first prod deploy |
| Verify Resend domain | Yes | Before sending real emails (one-time DNS) |
| Choose a domain | Yes | Before first prod deploy (or skip — `*.vercel.app` works) |
| Set up local Postgres | NO | Neon branch + connection string from registry |
| Set up Stripe webhook URL | NO | stripe-cli sidecar handles it for dev |
| Generate JWT secret | NO | bootstrap generates with `openssl rand` |
| Wire env vars to Vercel | NO | bootstrap pushes via vercel CLI |
| Wire CI secrets | NO | bootstrap pushes via gh CLI |
| Configure GitHub Actions | NO | templates copied in |
| Set up Postgres branching for PRs | NO | Neon manifest + GH Action |
| Set up Clerk preview instance per PR | NO | Clerk manifest + GH Action |
| Pick Tailwind config | NO | starter ships sensible default |
| Set up Prisma migrations | NO | initial migration generated from spec |
| Pick a component library | NO | shadcn/ui pre-installed |
| Configure error tracking | NO | Sentry wired by manifest |
| Configure analytics | NO | GA4 stub wired |
| Configure rate limit | NO | Upstash auto-wired if integration on |
| Configure background jobs | NO | Inngest auto-wired if integration on |

**Summary: G0, G1, two prod-only secrets, one domain choice, one DNS record. ~10 minutes of human attention to get from PRD to production.**

---

## 28. What this design buys you over alternatives

vs. **`create-next-app`**: gives you the workflow + integrations + CI + observability, not just an empty `app/` folder.

vs. **next-forge by Vercel**: opinionated about choices but in the same direction; we're more flexible (any Next.js stack, swap any integration), free-tier-first, and PRD-driven.

vs. **t3-stack create command**: t3 picks one stack; we pick a stack PER PRD with rationale.

vs. **rolling your own each time**: every win from the LuxeBook retrospective is encoded once and applies forever.

vs. **manual stack assembly via skills + plugins alone**: skills tell the agent HOW to do things; integrations + bootstrap GIVE the agent the things to work on. Skills + scaffold = explanation; this design = generation.

---

*Status: Part II adds advanced patterns. The Tier 1 plan now goes from feedback-locked decisions in §15 directly to a 7-day buildable plan in §26. Ready to start Day 1 on your call.*

---

## 29. Portability: every Vercel-specific service has a free escape hatch

The matrix is mostly portable already (Neon, Cloudflare R2, Clerk, Stripe, Resend, Sentry, Upstash, Inngest, GA4 — none are Vercel-locked). The remaining touch points + their migrations:

| Vercel service we use | Free? | What we'd lose if we leave Vercel hosting | Free OSS escape | Effort to migrate |
|----------------------|-------|--------------------------------------------|-----------------|-------------------|
| Vercel Hobby (web hosting) | Yes (100GB bandwidth) | Auto preview URLs, instant deploys | **Cloudflare Pages** (100k req/day free, unlimited bandwidth) OR **Netlify** (free) OR **Render** (free web service) OR self-host with **OpenNext** (MIT, runs Next.js anywhere — Docker, AWS, Cloudflare Workers) | 1-2 days |
| Vercel Edge Config (feature flags) | Yes (50KB store) | Edge-cached config | **Cloudflare KV** (free 100k reads/day) OR Upstash Redis (already in matrix) | <1 day |
| Vercel Postgres | Yes (256MB) | Vercel marketplace UX | **Neon** is already what we use (better free tier) | None — already portable |
| Vercel KV | Yes (30k cmds/mo) | Edge-compatible Redis | **Upstash Redis** already in matrix (better free tier) | None — already portable |
| Vercel Blob | Yes (1GB, but $0.15/GB egress) | Vercel-hosted blob | **Cloudflare R2** already in matrix (10GB free, **zero egress fees**) | None — already portable |
| Vercel Analytics | Yes (2.5k events) | Real User Monitoring | **GA4** already in matrix (unlimited free) + **Plausible** ($9/mo, EU-friendly) if needed | None — already portable |
| Vercel Image Optimization | Yes (1k images/mo on Hobby) | Built-in `next/image` resizing | **next/image** still works on any Node host; or use **Cloudflare Images** ($5/mo unlimited) OR self-host with `sharp` | <1 day |
| Vercel Functions | Yes (100k/mo) | Serverless API routes | **OpenNext** runs the same routes on Cloudflare Workers (free 100k req/day) or as a long-lived Node server (free anywhere) | <1 day |
| Vercel ISR cache | Yes | Incremental static regen | OpenNext supports ISR on Cloudflare Workers + Cloudflare KV | 1 day |

**OpenNext** (https://opennext.js.org) is the load-bearing escape hatch — open-source MIT runtime that takes a Next.js build and runs it on:
- Cloudflare Workers (free 100k req/day, unlimited bandwidth)
- AWS Lambda + S3 + CloudFront
- Plain Node.js Docker container (Fly.io free, Render free, your own VPS)

So the migration path off Vercel hosting is: `npx open-next build && deploy-to-target` — typically 1-2 days of validation.

**The bootstrap writes a `MIGRATION.md`** to every generated project documenting:
- Which services are Vercel-locked (none in Tier 1 — the matrix is intentionally portable)
- Which services need the matrix's free alternatives (none — same)
- The exact OpenNext command to leave Vercel hosting
- Where each prod secret would need to move

This is the "minus zero lock-in" property: free dev, free first-year prod, **and** the door is unlocked.

### Why we still recommend Vercel as the *default*

For Tier 1, Vercel Hobby is:
- Fastest first deploy (zero-config Next.js)
- Best free preview URL flow per PR
- Marketplace integrations 1-click (Neon, Clerk, Stripe, Resend, Upstash, Inngest, Sentry — all in our matrix)
- Generous free tier for MVP-stage usage

The recommendation stops being right when you cross thresholds (covered in §16's `SCALE_THRESHOLDS.md`) — at that point, OpenNext + Cloudflare or self-host is a clean exit.

---

## 30. Updated Tier 1 build plan, AI portion clarified

(Replaces §26 Day 5 + §26 AI subset)

**Day 5** (revised):
- Integration: `resend` + `r2-cloudflare` + `sentry` + `google-analytics`
- AI integration (optional, only if PRD signals): `ai-sdk` + `google-gemini-flash` adapter (default), `groq` + `openrouter` + `cloudflare-workers-ai` + `ollama` adapters as alts, `assistant-ui` chat components, `langfuse` observability stub (off by default)
- Layer 4: MCP server surface
- CI workflow templates: ci.yml + deploy-preview.yml + deploy-prod.yml

The AI integration ships with **all 5 provider adapters wired** so swapping is `MODEL_PROVIDER=<name>`. The default is Gemini Flash (highest free quota).
