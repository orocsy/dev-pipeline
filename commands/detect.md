---
description: Smart project detection — runs automatically before Phase 1. Detects project type, deploy targets, relevant skills. Never asks the user.
argument-hint: (no arguments — runs silently)
---

# /dev-pipeline:detect

You are the **project intelligence agent**. Run silently before Phase 1 of any pipeline invocation.
Output a structured detection report stored in `.claude/project-context.json`.
Never ask the user anything — infer everything from files and conversation context.

---

## STEP 0: Ensure engineering-craft skill is present (auto-bootstrap)

The dev-pipeline plugin depends on the `engineering-craft` skill at user-level
(`~/.claude/skills/engineering-craft/`) — `/dev-pipeline:review` STEP 1.5 reads
from it; `/dev-pipeline:consolidate-lessons` writes to it. The skill content is
NOT bundled with the plugin (knowledge has a different lifecycle than workflow
harness — see "Harness isn't the goal, knowledge is the moat").

This step is a **secondary safety net**. The primary engineering-craft bootstrap is the
SessionStart hook (`session-start.sh`), which runs once per session and clones the skill
if missing (it fast-forward-refreshes the read-write mirror only when that already exists —
provisioning the mirror itself is `setup-machine` / `consolidate-lessons` territory). STEP 0
rate-limits its own SKILL refresh with a **skill-specific** marker (`.last-skill-sync`) —
deliberately NOT the hook's `.last-mirror-sync`. The hook touches the mirror marker every
time it refreshes the *mirror*; sharing it would let a mirror-only refresh suppress a needed
*skill* pull for 24h, leaving `/dev-pipeline:review` on stale rules. STEP 0 earns its keep
for non-interactive / piped command invocations where SessionStart didn't fire. It does NOT
run before literally every command (only flows that invoke `/dev-pipeline:detect` do);
commands that hard-depend on the skill self-bootstrap too (see `/dev-pipeline:review` STEP 1.5).

```bash
SKILL_DIR="$HOME/.claude/skills/engineering-craft"
LAST_SYNC="$HOME/.claude/lessons-journal/.last-skill-sync"

# Check if we already synced today (rate-limit to once per 24h to avoid noise).
# stat: GNU coreutils uses `-c %Y`; BSD/macOS uses `-f %m`. Try `-c` FIRST — on
# BSD it fails cleanly (empty stdout, non-zero) and falls through to `-f`, whereas
# the reverse order makes GNU's `-f` print a multi-line filesystem report that
# poisons the arithmetic. So the value is always a single mtime on both OSes.
if [ -f "$LAST_SYNC" ]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$LAST_SYNC" 2>/dev/null || stat -f %m "$LAST_SYNC" 2>/dev/null || echo 0) ))
  if [ "$AGE" -lt 86400 ] && [ -d "$SKILL_DIR/categories" ]; then
    : # already fresh, no-op
  else
    NEEDS_SYNC=1
  fi
else
  NEEDS_SYNC=1
fi

if [ -n "${NEEDS_SYNC:-}" ]; then
  # Ensure the marker's parent dir exists before ANY branch touches it — the skill may
  # have been installed by setup-machine / review self-bootstrap, which create only the
  # skills dir, so the present-skill branches below would otherwise fail to advance it.
  mkdir -p "$(dirname "$LAST_SYNC")"
  if [ ! -d "$SKILL_DIR/categories" ]; then
    echo "[detect] engineering-craft not present — bootstrapping from public mirror"
    mkdir -p "$HOME/.claude/skills"
    if command -v git >/dev/null 2>&1; then
      # A leftover non-empty dir (partial/corrupt clone — no categories/, maybe no
      # .git/) would make `git clone` abort forever; clear it so the clone targets a
      # clean path. Safe: with no categories/ it isn't a usable skill anyway.
      [ -d "$SKILL_DIR" ] && [ -n "$(ls -A "$SKILL_DIR" 2>/dev/null)" ] && rm -rf "$SKILL_DIR"
      # Guard on BOTH the clone exit status AND the resulting dir — a pipe
      # (… | tail) would mask the clone's failure behind tail's exit code.
      if git clone --quiet https://github.com/orocsy/engineering-craft "$SKILL_DIR" 2>/dev/null && [ -d "$SKILL_DIR/categories" ]; then
        RULE_COUNT=$(find "$SKILL_DIR/categories" -name "*.md" -path "*/rules/*" 2>/dev/null | wc -l | tr -d ' ')
        CAT_COUNT=$(ls -d "$SKILL_DIR"/categories/*/ 2>/dev/null | wc -l | tr -d ' ')
        echo "[detect] engineering-craft installed: $RULE_COUNT rules across $CAT_COUNT categories"
        touch "$LAST_SYNC"   # advance the marker ONLY on a successful clone
      else
        echo "[detect] WARN: engineering-craft clone failed (offline?) — /review skill features degrade gracefully"
        # Deliberately do NOT touch the marker: leave it stale so the next command
        # (or session-start.sh) retries, instead of skipping for 24h after one blip.
      fi
    else
      echo "[detect] WARN: git not available; skipping engineering-craft bootstrap"
    fi
  elif [ -d "$SKILL_DIR/.git" ]; then
    # Skill present and is a git clone — refresh THE SKILL ITSELF (the dir /review
    # reads) in the background, and advance the marker only if the pull succeeds.
    ( git -C "$SKILL_DIR" pull --ff-only origin main >/dev/null 2>&1 && touch "$LAST_SYNC" ) &
  else
    # Skill present but not a git clone (copied/rsynced) — it's as fresh as it gets;
    # advance the marker so this block stops re-evaluating on every command for 24h.
    [ -d "$SKILL_DIR/categories" ] && touch "$LAST_SYNC"
  fi
fi
```

Behavior:
- **Fresh machine** (skill missing): clone from public mirror, ~5 sec, prints one-line summary (or a WARN on failure — never a false "0 rules" success, and the marker stays stale so the next run retries)
- **Skill present, last sync >24h ago**: background `git -C "$SKILL_DIR" pull --ff-only origin main`, marker advanced only on pull success, no wait
- **Skill present, last sync <24h ago**: no-op, instant
- **No git available / clone fails**: warn but continue (skill features in /review degrade gracefully); marker left stale

The 24h rate-limit avoids hitting GitHub on every single dev-pipeline command in a
working session while still keeping the skill fresh in normal use.

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
