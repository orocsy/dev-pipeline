---
description: Smart deploy adapter — reads project-context.json, creates missing config files if needed, runs the right deployment for any platform. Called automatically at Phase 12.
argument-hint: (no arguments — reads from project-context.json)
---

# /dev-pipeline:deploy

You are the **smart deploy adapter**. Run at Phase 12 of the dev-pipeline.
Read `.claude/project-context.json` to determine targets and whether config files need creating.
Never ask the user what platform — it was captured in planning. Just execute.

---

## Deploy-bootstrap protocol (first deploy / new target)

Run this BEFORE STEP 1 whenever this is the project's first deploy, or the first deploy to a target that hasn't gone live before (new platform, new environment, new account). Already-bootstrapped, routine redeploys skip straight to STEP 1.

### Step 0 — Credential probe, never assume

A CLI being installed does not mean it's authenticated, and a login from a past session may have expired. Probe every surface before planning anything:

```bash
vercel whoami
aws sts get-caller-identity
gh auth status                    # read the scopes, not just "logged in"
cloudflared --version
grep '^Host' ~/.ssh/config         # enumerate configured remote hosts
```

Classify every deploy surface from what the probe actually returned:
- **AUTONOMOUS** — working, sufficiently-scoped auth. Execute immediately.
- **HUMAN-GATED** — missing/expired/under-scoped auth, or an account-boundary decision (which org, which payment plan, which domain).

A missing CLI never blocks the whole deploy phase — it only moves that one surface to the human list. Keep going on everything else.

### The split plan

- **Autonomous lane** executes immediately — it doesn't wait on the human list.
- **Human lane** becomes a precise checklist: exact commands or exact dashboard paths, one line per item. Only account-boundary items belong here — logins, OAuth grants, payment-vendor dashboard config, domain/DNS, secrets. Secrets are always handed over as env/file/`gh secret set < file`, never pasted into chat.
- **GitHub Actions is always autonomous** whenever `gh auth status` shows repo+workflow scopes. It touches real cloud infrastructure but needs zero local cloud credentials: CI on real service containers, container-image publish via the workflow's own `GITHUB_TOKEN` (`packages:write`), and secrets-gated deploy workflows shipped dispatch-only (`workflow_dispatch`, not push-triggered) are all autonomous-lane work.

### Local prod-parity gate (mandatory before any first cloud deploy)

Prove the artifact boots locally under production conditions before it ever touches a real target:

- Full compose stack — production builds, `NODE_ENV=production`, real datastores, not mocks or a subset of services
- A one-shot migrate service ordered with `service_completed_successfully` so migrations finish before the app container starts, never racing it
- A distinct port band that collides with neither the dev stack nor the E2E stack
- Real health checks, hit for real
- Browser verification — load the actual page, don't stop at a curl 200

If it doesn't boot here, it will not boot there. Deploy artifacts are code: scaffold → build → boot → health-check is one validation loop, the same discipline as implement → validate. Evidence: a real first live-fire of freshly scaffolded deploy artifacts caught 3 config bugs in about 10 minutes — bugs that reading the Dockerfile and compose file line-by-line had not surfaced.

### First-deploy footguns

| Footgun | Bite | Fix |
|---|---|---|
| Monorepo Dockerfile copies package manifests but not the root config a `tsconfig` `extends` chain needs | `tsc` runs lib-less; TS2583 cascade inside third-party `.d.ts` files | COPY the full `extends` chain into the manifests layer, not just each package's own `tsconfig.json` |
| ORM client generate ≠ migrate | CI that migrates but never generates leaves a TS2305 storm on generated types | Run both, explicitly, every time — never assume one implies the other |
| `npx <tool>` from a workspace root silently downloads latest when the bin is package-local (pnpm) | Version drift between what CI runs and what's pinned in the lockfile, and it fails silently | Run from the owning package directory with `--no-install` so drift fails loud instead of quietly resolving to a stray global |
| Repo-hygiene hooks fire on remote infra paths (hardcoded `/home/<user>` in deploy scripts) | Script breaks the moment the deploy user or box changes | Use `$HOME`-relative remote paths so the script survives a deploy-user change |
| Push-trigger auto-deploy wired to a target that has never had a green manual deploy | Every push after that auto-fires against an unverified target — cascading failures with no manual checkpoint | Dispatch-only until the first green manual deploy; only then wire the push trigger |

### Cross-reference

This protocol is the generic flow. Its output, per project, is the `docs/<project>/deploy-runbook.md` convention — topology, secrets contract, and the first-deploy sequence, each step marked 🧑 (human) or 🤖 (autonomous). Write or update that runbook as this protocol runs; don't let the bootstrap knowledge live only in this session.

---

## STEP 1: Load Context

```bash
cat .claude/project-context.json
```

Extract:
- `deployTargets[]` — which platforms to deploy to
- `deployConfigExists{}` — which have config files already
- `deployMiusNeeded[]` — platforms needing config file creation

If `deployTargets` is empty or `DEPLOY_NONE=true`:
→ Print "No deploy configured for this project type. Done." and exit.

---

## STEP 2: Create Missing Config Files

For each item in `deployMiusNeeded`, create the config NOW (before deploying):

### Vercel (vercel.json)
```json
{
  "version": 2,
  "framework": "nextjs",
  "buildCommand": "npm run build",
  "outputDirectory": ".next",
  "env": {
    "NODE_ENV": "production"
  }
}
```
Also add `.github/workflows/vercel-deploy.yml`:
```yaml
name: Deploy to Vercel
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci && npm run build && npm test
      - name: Deploy
        run: npx vercel --prod --token ${{ secrets.VERCEL_TOKEN }}
```

### Supabase (supabase/config.toml + migrations scaffold)
```bash
mkdir -p supabase/migrations supabase/functions
cat > supabase/config.toml << 'EOF'
[api]
port = 54321
schemas = ["public"]

[db]
port = 54322

[studio]
port = 54323
EOF
```
Also add `.github/workflows/supabase-deploy.yml`:
```yaml
name: Deploy Supabase
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
      - run: supabase link --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
      - run: supabase db push
      - run: supabase functions deploy
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

### Railway (railway.json)
```json
{ "schema": "https://railway.app/railway.schema.json",
  "build": { "builder": "NIXPACKS" },
  "deploy": { "startCommand": "npm run start:prod", "restartPolicyType": "ON_FAILURE" } }
```
Add `.github/workflows/railway-deploy.yml`:
```yaml
name: Deploy to Railway
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build && npm test
      - uses: bervProject/railway-deploy@main
        with:
          railway_token: ${{ secrets.RAILWAY_TOKEN }}
          service: ${{ secrets.RAILWAY_SERVICE }}
```

### Fly.io (fly.toml)
```toml
app = "PROJECT_NAME"
primary_region = "sjc"
[build]
[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
```
Add Dockerfile if missing:
```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
CMD ["node", "dist/main.js"]
```
Add `.github/workflows/fly-deploy.yml`:
```yaml
name: Deploy to Fly.io
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - run: flyctl deploy --remote-only
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

### CloudBase (cloudbaserc.json)
```json
{
  "envId": "YOUR_ENV_ID",
  "framework": { "name": "nuxt3", "plugins": [{ "use": "@cloudbase/framework-plugin-nuxt" }] }
}
```

### AWS CDK (cdk.json + basic stack)
```json
{ "app": "npx ts-node --prefer-ts-exts bin/app.ts",
  "requireApproval": "never" }
```

---

## STEP 3: Commit Config Files

If any config files were created:
```bash
git add .github/ vercel.json supabase/ railway.json fly.toml cloudbaserc.json cdk.json Dockerfile 2>/dev/null || true
git commit -m "ci: add deployment configuration for [platforms]"
git push origin $(git rev-parse --abbrev-ref HEAD)
```

---

## STEP 4: Run Deployments

Run adapters for each target in `deployTargets`:

### Vercel adapter
```bash
# Check if Vercel CLI is installed
which vercel || npm i -g vercel
# Deploy
vercel --prod 2>&1 | tee .claude/deploy-vercel.log
DEPLOY_URL=$(grep -o 'https://[^ ]*\.vercel\.app' .claude/deploy-vercel.log | tail -1)
# Smoke test
curl -sf "$DEPLOY_URL/api/health" && echo "✅ Vercel health OK" || echo "⚠️ Health check failed — check logs"
```

### Railway adapter
```bash
which railway || npm i -g @railway/cli
railway up --service "$RAILWAY_SERVICE" 2>&1 | tee .claude/deploy-railway.log
echo "✅ Railway deployment triggered"
```

### Fly.io adapter
```bash
which flyctl || curl -L https://fly.io/install.sh | sh
flyctl deploy --remote-only 2>&1 | tee .claude/deploy-fly.log
flyctl status
```

### Supabase adapter
```bash
which supabase || npm i -g supabase
supabase db push 2>&1 | tee .claude/deploy-supabase.log
supabase functions deploy 2>&1 | tee -a .claude/deploy-supabase.log
echo "✅ Supabase: migrations + functions deployed"
```

### AWS CDK adapter
```bash
npx cdk deploy --all --require-approval never 2>&1 | tee .claude/deploy-aws.log
echo "✅ AWS CDK deployment complete"
```

---

## STEP 5: Monitor CI/CD

After pushing:
```bash
# Wait for GitHub Actions to pick up
sleep 5
RUN_ID=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
echo "Watching CI run: $RUN_ID"
gh run watch "$RUN_ID" --exit-status && echo "✅ CI passed" || echo "❌ CI failed — see: gh run view $RUN_ID"
```

---

## STEP 6: Deployment Summary

Print final summary:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ DEPLOYMENT COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Platform       Status    URL
────────────── ──────── ──────────────
Vercel         ✅ Live   https://...
Railway        ✅ Live   https://...
Supabase       ✅ Done   (migrations applied)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CI run: https://github.com/.../actions/runs/...
```
