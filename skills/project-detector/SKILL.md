---
name: project-detector
description: Detect project tech stack, structure, and deploy intent automatically at Phase 0 of every pipeline flow and at `/dev-pipeline:init`. Inspects `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `requirements.txt`, `composer.json`, `Gemfile`, `pom.xml`, `build.gradle`, framework config files, deploy config files (`vercel.json`, `netlify.toml`, `fly.toml`, `supabase/config.toml`, `wrangler.toml`, `railway.json`, `Dockerfile`, `docker-compose.yml`). Also parses Phase 1 natural-language for deploy intent ("I'll host on Vercel", "deploy to Supabase", "k8s cluster") and generates matching config-scaffolding MIUs. Trigger whenever pipeline starts, new project detected, or user mentions deploy target.
---

# Project Detector Skill

## Activation Banner (print exactly once when this skill loads)

```
🔧 [dev-pipeline] skill: project-detector — stack detection active (Phase 0)
   Scanning: package.json, deploy configs, framework fingerprints...
```

---

This skill runs at **Phase 0** of every pipeline flow and during `/dev-pipeline:init`. It removes ambiguity about project type so the pipeline never asks the user questions it can answer itself.

## Detection Order

1. **Language / runtime fingerprint** (run in parallel, highest-weight match wins):
   - `package.json` → Node.js. Inspect `dependencies` + `devDependencies`:
     - `next` → Next.js (App Router if `app/` exists, Pages Router if `pages/`)
     - `react` + no `next` → CRA / Vite / custom React
     - `@nestjs/core` → NestJS
     - `@remix-run/*` → Remix
     - `astro` → Astro
     - `fastify` / `express` / `hono` / `koa` → Node API server
     - `typescript` present → TS project; absent → JS project
   - `Cargo.toml` → Rust
   - `go.mod` → Go
   - `pyproject.toml` / `requirements.txt` / `setup.py` → Python (check for `fastapi`, `django`, `flask`)
   - `composer.json` → PHP (check for `laravel/framework`, `symfony/symfony`)
   - `Gemfile` → Ruby (check for `rails`)
   - `pom.xml` / `build.gradle` / `build.gradle.kts` → JVM (Java/Kotlin)
   - `*.csproj` / `*.sln` → .NET
   - `mix.exs` → Elixir
   - `Package.swift` → Swift

2. **Monorepo detection** (before narrowing stack):
   - `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `lerna.json`, root `package.json` with `workspaces` → monorepo
   - If monorepo, run detection per package in `apps/*` and `packages/*`.

3. **Framework narrowing** (per-package):
   - Check `next.config.{js,mjs,ts}`, `remix.config.js`, `astro.config.mjs`, `vite.config.{js,ts}`, `nest-cli.json`, `tsconfig.json` paths.

4. **Test framework**:
   - `vitest.config.*` → Vitest
   - `jest.config.*` → Jest
   - `playwright.config.*` → Playwright (E2E)
   - `cypress.config.*` → Cypress
   - Record whether each is present; MIU planner uses this.

5. **Linter / formatter**:
   - `.eslintrc*` / `eslint.config.*`, `biome.json`, `.prettierrc*`, `rustfmt.toml`, `.golangci.yml`

6. **Database / ORM** (for backend repos):
   - `prisma/schema.prisma` → Prisma
   - `drizzle.config.*` → Drizzle
   - `ormconfig.*`, `typeorm` dep → TypeORM
   - `supabase/` directory → Supabase client
   - `@planetscale/database`, `@neondatabase/serverless` → serverless Postgres
   - `mongoose` dep → MongoDB

## Deploy Target Detection

Run BOTH steps; a project can have multiple targets (e.g. frontend Vercel + backend Fly).

### Step A: Config-file sweep

| File present | Deploy target |
|---|---|
| `vercel.json` / `.vercel/` | Vercel |
| `netlify.toml` / `.netlify/` | Netlify |
| `fly.toml` | Fly.io |
| `railway.json` / `railway.toml` | Railway |
| `render.yaml` | Render |
| `wrangler.toml` / `wrangler.jsonc` | Cloudflare Workers/Pages |
| `supabase/config.toml` | Supabase |
| `firebase.json` | Firebase |
| `amplify.yml` | AWS Amplify |
| `Dockerfile` + no other marker | generic Docker (ask CI target) |
| `docker-compose.yml` | local Docker compose |
| `k8s/*.yaml`, `helm/` | Kubernetes |
| `serverless.yml` | Serverless Framework (AWS/GCP) |
| `sst.config.ts` | SST (AWS) |
| `.do/app.yaml` | DigitalOcean App Platform |

### Step B: Natural-language intent capture (Phase 1)

Scan user's Phase 1 requirements text for deploy keywords. Record intent even if no config file exists yet:

| Phrase | Target |
|---|---|
| "Vercel", "deploy to Vercel", "host on Vercel" | Vercel |
| "Supabase", "Supabase auth", "Supabase DB" | Supabase |
| "Fly", "Fly.io" | Fly |
| "Cloudflare", "Workers", "Pages" | Cloudflare |
| "Railway" | Railway |
| "Render" | Render |
| "Netlify" | Netlify |
| "Firebase" | Firebase |
| "AWS", "Lambda", "EC2", "ECS", "Fargate" | AWS (narrow in G3) |
| "k8s", "kubernetes", "helm" | Kubernetes |
| "self-host", "VPS", "bare metal" | self-hosted |

### Step C: Auto-generate scaffolding MIUs

If deploy intent is captured but config files are MISSING, the pipeline must add a scaffolding MIU BEFORE the implementation MIUs. Examples:

- Intent: Vercel, no `vercel.json` → add MIU `infra-001: Create vercel.json with build/output config and env var mapping`
- Intent: Supabase, no `supabase/` → add MIU `infra-002: Initialize supabase project (supabase init) and commit config.toml`
- Intent: Fly, no `fly.toml` → add MIU `infra-003: flyctl launch with scaled-to-zero defaults and healthcheck`
- Intent: Docker, no `Dockerfile` → add MIU `infra-004: Multi-stage Dockerfile + .dockerignore`

## Output Contract

Emit a structured summary to `.claude/docs/ARCHITECTURE.md` and `.claude/project-profile.json` with:

```json
{
  "language": "typescript",
  "runtime": "node",
  "framework": "next",
  "frameworkVersion": "15.x",
  "router": "app",
  "monorepo": false,
  "packages": [],
  "testFrameworks": ["vitest", "playwright"],
  "linter": "eslint",
  "formatter": "prettier",
  "orm": "prisma",
  "db": "postgres",
  "deployTargets": ["vercel", "supabase"],
  "scaffoldingMIUs": [],
  "detectedAt": "2026-04-14T00:00:00Z",
  "detectionSource": ["package.json", "next.config.mjs", "vercel.json", "prisma/schema.prisma"]
}
```

The pipeline MUST NOT ask the user for anything this skill already detected. If a field is genuinely ambiguous (e.g. Node version not pinned), emit a single question AFTER detection rather than a generic "what stack?" question.

## Activation Triggers

- `/dev-pipeline:init` — always
- Phase 0 of `/dev-pipeline:pipeline`, `/dev-pipeline:fix`, `/dev-pipeline:update`, `/dev-pipeline:hotfix` — always
- When `.claude/project-profile.json` is missing OR older than 7 days
- When new deploy config file detected in diff
