---
description: Smart project detection — runs automatically before Phase 1. Detects project type, deploy targets, relevant skills. Never asks the user.
argument-hint: (no arguments — runs silently)
---

# /dev-pipeline:detect

You are the **project intelligence agent**. Run silently before Phase 1 of any pipeline invocation.
Output a structured detection report stored in `.claude/project-context.json`.
Never ask the user anything — infer everything from files and conversation context.

---

## STEP 1: Project Type Detection

Read these files (whichever exist):
- `package.json` (and all workspace `*/package.json`)
- `Cargo.toml`, `go.mod`, `pyproject.toml`, `*.csproj`, `*.gradle`
- `vercel.json`, `fly.toml`, `railway.json`, `supabase/config.toml`
- `Dockerfile`, `docker-compose.yml`
- `.github/workflows/*.yml`
- `electron-builder.yml`, `tauri.conf.json`

Classify into ONE primary type + optional secondary:

| Files found | Project type | Deploy relevant? |
|-------------|-------------|-----------------|
| electron / tauri | DESKTOP | No |
| expo / react-native | MOBILE | No (app store) |
| next.js + @nestjs/core | FULLSTACK | Yes |
| next.js / nuxt / remix / vite (no nest) | FRONTEND | Yes |
| @nestjs/core / fastify / express (no next) | BACKEND | Yes |
| no package.json + Cargo.toml | RUST_CLI | No |
| no package.json + go.mod | GO_SERVICE | Yes (optional) |
| no package.json + pyproject.toml | PYTHON | Yes (optional) |
| package.json with `"main"` only, no framework | LIBRARY | No |

---

## STEP 2: Deploy Target Detection

### From existing config files:
```
vercel.json OR .vercel/ → Vercel confirmed
supabase/config.toml → Supabase confirmed
fly.toml → Fly.io confirmed
railway.json OR railway.toml → Railway confirmed
serverless.yml → AWS Lambda/Serverless confirmed
cdk.json → AWS CDK confirmed
cloudbaserc.json → CloudBase confirmed
.github/workflows/ with "vercel" | "supabase" | "fly" | "railway" → confirm from workflow
```

### From conversation (scan $ARGUMENTS and prior messages):
```
Keyword "vercel"       → DEPLOY_VERCEL=true
Keyword "supabase"     → DEPLOY_SUPABASE=true
Keyword "railway"      → DEPLOY_RAILWAY=true
Keyword "fly" / "fly.io" → DEPLOY_FLY=true
Keyword "aws" / "lambda" / "ecs" / "cdk" → DEPLOY_AWS=true
Keyword "cloudbase"    → DEPLOY_CLOUDBASE=true
Keyword "no deploy" / "just local" / "library" → DEPLOY_NONE=true
```

### Fallback for web projects with no deploy info:
Set DEPLOY_UNKNOWN=true. At Gate G3, ask once:
"Deploy setup needed? Which platform? (Vercel / Railway / Supabase / AWS / CloudBase / none)"

---

## STEP 3: Skill Mapping

Map detected stack → skills to activate in Phase 7:

```json
{
  "HIGH": [],   // activate via Skill tool before implementation
  "MEDIUM": [], // activate if relevant MIU comes up
  "CONTEXT7": [] // use Context7 MCP for on-demand docs
}
```

Mapping rules:
```
next / react         → HIGH: vercel-react-best-practices, vercel-composition-patterns
nestjs               → HIGH: nestjs-best-practices
typescript           → HIGH: mastering-typescript
websocket            → HIGH: websocket-engineer
redis                → MEDIUM: nodejs-caching-redis
prisma / typeorm     → MEDIUM: nodejs-database-orm
docker               → MEDIUM: nodejs-docker-production
jest / vitest        → MEDIUM: nodejs-testing
express / fastify    → MEDIUM: nodejs-architecture
unknown library      → CONTEXT7: [library name]
```

---

## STEP 4: Design Asset Detection

```
Stitch project ID in $ARGUMENTS or conversation   → DESIGN_SOURCE=stitch_mcp
  (use Stitch MCP: get_screen_code, get_screen_image, screens)
Figma URL in $ARGUMENTS or conversation           → DESIGN_SOURCE=figma, URL=[url]
Image/screenshot attached                          → DESIGN_SOURCE=screenshot
No design info + UI feature with visual needs     → DESIGN_SOURCE=needs_stitch
  (suggest user create design at stitch.withgoogle.com, share project ID for MCP)
No design info + simple/minor UI change           → DESIGN_SOURCE=text_spec
Non-UI feature                                    → DESIGN_SOURCE=skip
```

Stitch MCP: Google's AI design tool with full MCP server (npx @_davideast/stitch-mcp proxy).
Tools: get_screen_code, get_screen_image, build_site, serve, screens.
Stitch is the PRIMARY design integration — agent reads design AND can push suggestions back.

## STEP 4b: Write Per-Language Check Commands

Based on project type, write check/lint/test/build commands to project-context.json:

```
TypeScript:
  checkCommand: "npx tsc --noEmit 2>&1 | grep -E 'error TS' | head -10"
  lintCommand: "npx eslint . --ext .ts,.tsx 2>&1 | tail -10"
  testCommand: "npx vitest run" or "npx jest --passWithNoTests"
  buildCommand: "npm run build"

Rust:
  checkCommand: "cargo check 2>&1 | tail -10"
  lintCommand: "cargo clippy -- -D warnings 2>&1 | tail -10"
  testCommand: "cargo test"
  buildCommand: "cargo build --release"

Go:
  checkCommand: "go vet ./... 2>&1 | tail -10"
  lintCommand: "golangci-lint run 2>&1 | tail -10"
  testCommand: "go test ./... -count=1"
  buildCommand: "go build ./..."

Python:
  checkCommand: "mypy . --ignore-missing-imports 2>&1 | tail -10"
  lintCommand: "ruff check . 2>&1 | tail -10"
  testCommand: "pytest -x -q"
  buildCommand: "python -m build" (if library)

Monorepo (multiple stacks):
  checkCommands: { "apps/web": "npx tsc --noEmit", "services/api": "cargo check" }
```

These commands are used by the PostToolUse hook (universal-check.sh) for instant feedback.

---

## STEP 5: Git Hooks Check

```bash
[ -f ".git/hooks/pre-commit" ] && echo "hooks_installed=true" || echo "hooks_installed=false"
```

If false → silently run: `~/.claude/setup-git-hooks.sh`

---

## OUTPUT

Write `.claude/project-context.json` in the project root:

```json
{
  "projectType": "FULLSTACK",
  "primaryFramework": "next+nestjs",
  "techStack": ["typescript", "nestjs", "react", "prisma"],
  "checkCommand": "npx tsc --noEmit 2>&1 | grep -E 'error TS' | head -10",
  "lintCommand": "npx eslint . --ext .ts,.tsx 2>&1 | tail -10",
  "testCommand": "npx vitest run",
  "buildCommand": "npm run build",
  "formatCommand": "npx prettier --check .",
  "deployTargets": ["vercel", "railway"],
  "deployConfigExists": { "vercel": true, "railway": false },
  "deployMiusNeeded": ["railway"],
  "skillsHigh": ["vercel-react-best-practices", "nestjs-best-practices", "mastering-typescript"],
  "skillsMedium": ["nodejs-database-orm", "nodejs-docker-production"],
  "skillsContext7": [],
  "designSource": "stitch_mcp",
  "stitchProjectId": "abc123",
  "gitHooksInstalled": true,
  "taskType": "NEW_FEATURE",
  "pipelinePhases": [0,1,2,3,4,5,6,7,8,9,10,11,12],
  "gates": ["G1","G2","G3","G4"],
  "detectedAt": "2026-03-23T11:30:00Z"
}
```

Then print a one-line summary (not a full report) and continue to Phase 1 automatically:
`[detect] FULLSTACK | deploy: vercel(✓) + railway(create) | skills: 3 HIGH | design: figma`
