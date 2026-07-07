---
description: Scaffold a NEW project from a PRD or English description. Runs requirements-analyst → produces a spec.json → invokes spec-forge to scaffold a real building project. Decoupled from dev-pipeline; requires spec-forge to be installed at ~/Desktop/projects/spec-forge (or set SPEC_FORGE_DIR).
---

# /dev-pipeline:scaffold-from-prd

End-to-end flow: PRD or English description → structured spec.json → real working project.

This command is for **NEW projects only**. For features inside an existing project, use `/dev-pipeline:pipeline` instead.

## Phase 1 — Locate spec-forge

```bash
SPEC_FORGE_DIR="${SPEC_FORGE_DIR:-$HOME/Desktop/projects/spec-forge}"
if [[ ! -f "$SPEC_FORGE_DIR/cli.ts" ]]; then
  echo "❌ spec-forge not found at $SPEC_FORGE_DIR"
  echo "   Clone or download it: https://github.com/<owner>/spec-forge"
  echo "   Or set SPEC_FORGE_DIR=/path/to/spec-forge"
  exit 1
fi
```

**Decoupling rule**: dev-pipeline never imports spec-forge code. They communicate only via `spec.json` files + the `spec-forge` CLI. spec-forge is upgradable independently.

## Phase 2 — Gather inputs

If `$ARGUMENTS` is a path to an existing PRD/SPEC file → accept it and skip to Phase 3.

If `$ARGUMENTS` is empty OR is a one-line description (no structured PRD attached):

### Phase 2a — Elicit a SPEC (NEW)

Invoke the **`dev-pipeline:spec-elicitor`** skill via the Skill tool. It walks the user through a Socratic discussion — one numbered-options question at a time — and produces a complete SPEC covering Problem / Solution / Constraints / Non-goals / Success Criteria / Quality Criteria. Wait for it to write `docs/<slug>/SPEC.md`.

For scaffold-from-prd (new project), the SPEC is the PRD — `prd-parser` in Phase 3 will read it directly. Do NOT skip elicitation for "I'll fill it in later" — the spec is what makes integration selection in Phase 3 deterministic.

### Phase 2b — Gather scaffold-specific opinions

After the SPEC exists, ask ONE more question (numbered options):

```
The SPEC is locked. A few scaffold-level choices:

1. Output directory — default to `./<slug>` derived from the SPEC name?
2. Stay free-tier only on all integrations (recommended for prototypes)?
3. Any explicit framework / auth provider override the SPEC didn't capture?
```

If the user has an existing PRD file (not a SPEC produced by spec-elicitor), accept the path and skip Phase 2a entirely.

## Phase 3 — Generate the spec via requirements-analyst

Invoke the `dev-pipeline:requirements-analyst` agent with the PRD as input. The agent must produce a `spec.json` matching the schema at `$SPEC_FORGE_DIR/layer1/schemas.ts:ProjectSpec`. Required fields:

- `meta.name` (kebab-case)
- `meta.description` (≥10 chars)
- `meta.spec_schema_version: 1`
- `integrations[]` — list from `tsx $SPEC_FORGE_DIR/cli.ts list-integrations`

Default integration set (free-tier production preset):

```json
[
  "nodejs-typescript-base",
  "next-app",
  "tailwind-v4",
  "prisma",
  "postgres-neon",
  "auth-better-auth",
  "email-resend",
  "observability-sentry",
  "analytics-umami",
  "vitest",
  "playwright-e2e",
  "eslint-prettier",
  "git-hooks",
  "github-actions-ci",
  "vercel-deploy",
  "dependabot-config"
]
```

Add or remove based on the PRD (e.g. add `ai-sdk` if the PRD mentions AI/chat; swap `auth-better-auth` for `auth-clerk` only if the user explicitly asks for hosted auth UI).

## Phase 4 — Validate the spec

```bash
tsx "$SPEC_FORGE_DIR/cli.ts" validate /tmp/spec.json
```

If validation fails, the agent must fix the spec until it passes. Don't proceed to scaffold with an invalid spec.

## Phase 5 — Confirm with user (gate G1-equivalent)

Print the resolved integration list + their categories. Ask the user to type `Y` to proceed. **Do not scaffold without explicit `Y`** — this is the only gate for new-project flows because there's no MIU breakdown.

## Phase 6 — Scaffold

```bash
tsx "$SPEC_FORGE_DIR/cli.ts" scaffold /tmp/spec.json "$OUT_DIR" --install
```

This will take 3–5 minutes (`pnpm install` is most of it). Stream the CLI's stdout so the user can see progress.

## Phase 7 — Surface the keys-to-claim list

Read the produced `.env.example`. List every blank key with the URL where the user can claim a free tier:

```
✓ Project ready at <out-dir>

Before you can `pnpm dev`, claim these free-tier keys:
   • DATABASE_URL          → https://console.neon.tech (free 0.5GB)
   • RESEND_API_KEY        → https://resend.com (free 3k/mo)
   • SENTRY_DSN            → https://sentry.io (free 5k events/mo)
   • OPENROUTER_API_KEY    → https://openrouter.ai (free Llama/Mistral models)
   • BETTER_AUTH_SECRET    → run: openssl rand -hex 32
   • NEXT_PUBLIC_UMAMI_*   → https://umami.is (free 10k events/mo)

Set them in <out-dir>/.env.local, then:
   cd <out-dir> && pnpm dev
```

## Phase 8 — Print summary

```
✓ scaffold-from-prd complete
  spec:           /tmp/spec.json (also copied to <out-dir>/.spec.json for the record)
  out:            <out-dir>
  integrations:   <count>
  installed:      ✓
  next steps:     fill keys → pnpm dev → /dev-pipeline:pipeline for first feature
```

## Errors / rollback

If the scaffold fails partway:

```bash
tsx "$SPEC_FORGE_DIR/cli.ts" rollback "<out-dir>.journal.jsonl"
```

This replays inverse actions in reverse order, restoring the target tree to a clean state.

---

## When NOT to use this

- ❌ Adding a feature to an existing project → use `/dev-pipeline:pipeline`
- ❌ Modifying a single file → use `/dev-pipeline:update`
- ❌ Production hotfix → use `/dev-pipeline:hotfix`
- ❌ Doing a refactor → use `/dev-pipeline:refactor`

This command exists for the moment **before** any of those — when there's no project yet.
