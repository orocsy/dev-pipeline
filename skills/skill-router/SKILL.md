---
name: skill-router
description: Auto-select the correct skills and MCP tools for each pipeline phase based on detected tech stack and task type. Covers design-phase routing (Stitch MCP → Figma MCP → image → ui-ux-pro-max → design-checker → skip), tech-stack skill routing (next → vercel-react + vercel-composition, nestjs → nestjs-best-practices, rust → rust-idioms, go → go-idioms, etc.), and deploy-adapter selection (vercel.json → vercel-adapter, supabase/ → supabase-adapter, fly.toml → fly-adapter). Trigger at start of design phase, architecture phase, implementation phase, and before delivery. Never ask the user which skill to use — the router decides from `project-profile.json`.
---

# Skill Router

## Activation Banner (print exactly once when this skill loads)

```
🔧 [dev-pipeline] skill: skill-router — routing engine active
   Reading project-profile.json → selecting skills for current phase...
```

---

This skill is the single decision point for "which skill / MCP / adapter do I use right now?" Agents MUST consult this router before reaching for any tool; the router reads `project-profile.json` (from `project-detector`) and emits a decision.

## Design Phase Routing

Applies during Phase 2 (HLD) and Phase 3 (design spec) of `/dev-pipeline:pipeline` and `/dev-pipeline:update`.

### Phase 2 — High-Level Design (HLD): Fixed sequence, always runs in this order

**Step 1 (mandatory first hit): `cloud-design-patterns` skill**
```
🔧 [dev-pipeline] skill: cloud-design-patterns — architecture audit (Phase 2, Step 1)
```
Evaluates proposed architecture against 42 industry patterns. Produces an ADR. Blocks G2 if hard constraints are violated. Runs for ALL features — backend, frontend, infra. No exceptions.

**Step 2 (mandatory): `excalidraw-diagram-generator` skill — HLD diagrams**
```
🔧 [dev-pipeline] skill: excalidraw-diagram-generator — HLD diagrams (Phase 2, Step 2)
```
Generates 3 mandatory diagrams and saves to `.claude/diagrams/`:
- `hld-context-<slug>.excalidraw` — System context (C4 L1)
- `hld-services-<slug>.excalidraw` — Container/service architecture
- `hld-deployment-<slug>.excalidraw` — Infrastructure/deployment

Print each diagram path as it's generated:
```
📄 [dev-pipeline] diagram: hld-context-<slug>.excalidraw → saved
📄 [dev-pipeline] diagram: hld-services-<slug>.excalidraw → saved
📄 [dev-pipeline] diagram: hld-deployment-<slug>.excalidraw → saved
```

If excalidraw MCP is connected, also render + screenshot each diagram for visual verification.

**Step 3 (conditional): UI/UX design spec — evaluate top-down, take FIRST match:**

| Condition | Skill / MCP used |
|---|---|
| Stitch MCP is connected AND task mentions UI/UX | `stitch-mcp` (generate + iterate on component mockups) |
| Figma MCP is connected AND user provided a Figma URL or file key | `figma-mcp` (pull frames, export assets) |
| User attached an image (PNG/JPG) of a design | `image-to-component` (visual-diff driven implementation) |
| Stack is React/Next/Remix AND no design asset provided | `ui-ux-pro-max` (generate Tailwind/shadcn-compatible design spec) |
| Stack is React/Next/Remix AND design spec already exists | `design-checker` (verify implementation matches spec) |
| Task is backend-only (no UI surface) | **skip Step 3** — Steps 1 + 2 still run |
| Task is a pure infra / config change | **skip Step 3** — Steps 1 + 2 still run |

If multiple MCPs are connected (Stitch + Figma), prefer the one referenced by the user in Phase 1. If neither is referenced, ask ONE question: "Stitch or Figma?" Do not ask a generic "what design tool?"

### Phase 5 — Low-Level Design (LLD): Technical diagrams MANDATORY

**`excalidraw-diagram-generator` skill — LLD diagrams**
```
🔧 [dev-pipeline] skill: excalidraw-diagram-generator — LLD diagrams (Phase 5)
```

Generate these diagrams based on what the feature touches (check each):

| Feature touches | Diagram type | File |
|---|---|---|
| Any multi-service interaction | Sequence diagram (per key flow) | `lld-sequence-<flow>.excalidraw` |
| Schema migration / new entity | ER / data model | `lld-er-<domain>.excalidraw` |
| Cross-module changes (2+ modules) | Component dependency | `lld-components-<module>.excalidraw` |
| New status field / multi-step state | State machine | `lld-state-<entity>.excalidraw` |
| New API endpoint | API request flow | `lld-api-<endpoint>.excalidraw` |

Minimum: every feature with 3+ MIUs must have at least 2 LLD diagrams. If the feature is contained in a single module with no schema or API changes, 1 diagram is acceptable.

Print each diagram path as it's generated:
```
📄 [dev-pipeline] diagram: lld-sequence-<slug>.excalidraw → saved
```

## Tech-Stack Skill Routing (Implementation Phase)

Read `project-profile.json`. Load the matching skill(s). Multiple may load per project (monorepo or full-stack).

| Detected stack | Skill(s) to load |
|---|---|
| `framework: next` | `vercel-react`, `vercel-composition`, `react-server-components` |
| `framework: remix` | `remix-idioms`, `vercel-react` |
| `framework: astro` | `astro-idioms` |
| `framework: react` (no next/remix/astro) | `vercel-react` |
| `framework: nestjs` | `nestjs-best-practices`, `nestjs-modules` |
| `framework: fastify` / `express` / `hono` / `koa` | `node-api-idioms` |
| `runtime: node` + `orm: prisma` | `prisma-patterns` |
| `runtime: node` + `orm: drizzle` | `drizzle-patterns` |
| `db: postgres` | `postgres-best-practices` |
| `db: mongodb` | `mongodb-patterns` |
| `language: rust` | `rust-idioms`, `rust-errors` |
| `language: go` | `go-idioms`, `go-concurrency` |
| `language: python` + `fastapi` | `fastapi-patterns` |
| `language: python` + `django` | `django-idioms` |
| `language: typescript` | `typescript-strict` (always, for any TS project) |
| `testFrameworks: [vitest]` | `vitest-patterns` |
| `testFrameworks: [jest]` | `jest-patterns` |
| `testFrameworks: [playwright]` | `playwright-e2e` |

## Deploy Adapter Routing (Delivery Phase)

`/dev-pipeline:deliver` Step 3 (env validation) and Step 9 (merge) use deploy adapters. Pick based on `deployTargets` array:

| Target | Adapter |
|---|---|
| `vercel` | `vercel-adapter` — checks `vercel.json`, `.vercel/project.json`, env var parity with Vercel dashboard |
| `netlify` | `netlify-adapter` — `netlify.toml` env context (production/deploy-preview/branch) |
| `fly` | `fly-adapter` — `fly.toml` secrets via `flyctl secrets list` |
| `railway` | `railway-adapter` — `railway variables` |
| `render` | `render-adapter` — `render.yaml` envVars section |
| `supabase` | `supabase-adapter` — `supabase/config.toml` + `.env` alignment, RLS policy diff check |
| `cloudflare` | `cloudflare-adapter` — `wrangler.toml` vars + secrets |
| `firebase` | `firebase-adapter` — `firebase.json` hosting + functions config |
| `kubernetes` | `k8s-adapter` — Helm values / ConfigMap / Secret diff |
| `docker` (generic) | `docker-adapter` — Dockerfile best-practices + image-size audit |
| `aws` (Lambda/ECS) | `aws-adapter` — SST or serverless framework config |

If multiple targets are present (e.g. Vercel frontend + Supabase backend), run ALL matching adapters in parallel. Do not pick one.

## Always-On Cross-Cutting Skills (Implementation + Review)

These skills load REGARDLESS of detected stack — they enforce reasoning discipline that applies to every project. The implementation flow loads them at the start of every MIU; the review flow loads them before the parallel reviewers spawn.

| Skill | When it loads | What it enforces |
|---|---|---|
| `cross-file-reasoning` | `/dev-pipeline:implement` STEP 4.5 (per-MIU) AND `/dev-pipeline:review` STEP 2 (cross-file-reviewer A0.5) | Seven cross-file traces (env-var producer→consumer, route URL composition, SDK option vs type defs, event lifecycle vs tx boundary, mock vs real interface, conditional coupling, wrapper lifecycle). See `skills/cross-file-reasoning/SKILL.md` + `FAILURE_MODES.md` catalog. |

If a future "always-on" skill emerges (e.g. accessibility checks, dependency-freshness audit), add it here so it loads via the router rather than being hard-coded inside individual commands.

## Review-Phase Skill Routing (Self-Review)

After every commit, the post-commit hook triggers self-review. Which reviewers run is decided by diff contents:

| Diff touches | Reviewer | Skill(s) it loads |
|---|---|---|
| Any non-doc-only file | `cross-file-reviewer` (always — runs alongside deep-reviewer) | `cross-file-reasoning` |
| Any file | `deep-reviewer` (always) | (none; uses cross-file lens via prompt instructions) |
| `.ts` / `.tsx` | `typescript-reviewer` | `typescript-strict` |
| Auth / crypto / `process.env.*` / `.env*` | `security-reviewer` | (none; uses cross-file env-var trace via prompt) |
| SQL / migrations / `schema.prisma` | `db-reviewer` | `postgres-best-practices` / `prisma-patterns` |
| `*.test.*` / `*.spec.*` | `test-reviewer` | `vitest-patterns` / `jest-patterns` |
| `Dockerfile` / `k8s/` / `helm/` | `infra-reviewer` | `docker-adapter` / `k8s-adapter` |

## MCP Connection Detection

Before deciding to use a Stitch / Figma / Supabase MCP, verify the connection is live:

1. Check `~/.claude/settings.json` `mcpServers` for the server block
2. Run the MCP's health-check tool (each MCP exposes one)
3. If unhealthy, fall back to the next rule in this document — do NOT ask user to "connect Figma" during Phase 2

## Activation Triggers

- Start of Phase 2 (design) in any flow
- Start of Phase 5 (architecture / skill selection)
- Start of Phase 7 (implementation)
- Delivery Step 3 and Step 9
- Post-commit self-review

## Output Contract

Emit a decision record to `.claude/agent-events.jsonl`:

```json
{
  "event": "skill-router.decision",
  "phase": "design",
  "selected": ["stitch-mcp"],
  "skipped": ["figma-mcp", "ui-ux-pro-max"],
  "reason": "Stitch MCP connected, user referenced 'generate mockups'",
  "ts": "2026-04-14T00:00:00Z"
}
```

Never silently use a skill without a recorded decision. The event log is the audit trail.
