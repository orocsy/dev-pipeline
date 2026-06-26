---
description: Bootstrap a new or existing project — refresh plugin deps, run project detection, create .claude/docs/, install git hooks, scaffold missing deploy configs.
---

# Development Pipeline: Init

You are setting up pipeline infrastructure for a project.
All steps are pre-approved. Do not ask for permission. Run to completion.

---

## STEP 0: Refresh External Plugin Dependencies

Invoke `/dev-pipeline:refresh-deps`. It will:
- Read `deps.json` from this plugin's root.
- Verify every referenced external plugin/skill/MCP is installed AND up-to-date.
- `git pull --ff-only` any stale marketplaces.
- Flag hybrid-skill drift (owned skills that compose with public ones whose shape may have changed).
- Honour `supersedes[]` and `status: search-required` declarations so renamed/known-gap skills don't flood the report.
- Write `.claude/dev-pipeline-deps-status.json`.

Decision tree based on exit code:

| Exit | Meaning | Init behavior |
|---|---|---|
| 0 | Clean | Continue to STEP 1 silently |
| 1 | REQUIRED dep missing (e.g. `code-review`) | STOP. Surface install instructions. |
| 2 | Hybrid drift detected (owned skills reference moved/renamed externals) | **Auto-dispatch `/dev-pipeline:skill-doctor --report`** (next sub-step) |
| 3 | Config error (deps.json malformed, jq missing) | STOP. Fix infrastructure first. |

## STEP 0.5: Skill Doctor (only when STEP 0 returned exit 2)

Invoke `/dev-pipeline:skill-doctor --report`. It will:
- Read the status JSON from STEP 0.
- Classify each missing entry as **Auto-resolvable**, **Marketplace-resolvable**, or **Search-required**.
- Write `.claude/dev-pipeline-skill-doctor-plan.md`.

Init surfaces the counts in its final summary. Init does NOT auto-`--apply` — rename of public-skill references touches owned-skill prose, which is human-review territory. If there are auto-resolvable items, init prints:

> Skill doctor found N auto-fixable items — run `/dev-pipeline:skill-doctor --apply` to fix.

For search-required items:

> Skill doctor flagged M items as search-required — see `.claude/dev-pipeline-skill-doctor-plan.md`.

Then continue to STEP 1.

---

## STEP 1: Run Project Detection

Invoke the `project-detector` skill. It will:
- Fingerprint the stack (language, framework, ORM, test runner, linter)
- Detect deploy targets from config files and Phase 1 text
- Emit `.claude/project-profile.json`

If `project-profile.json` already exists and is <7 days old, skip detection.

---

## STEP 1.5: engineering-craft skill bootstrap

No manual action needed in init — the skill is bootstrapped by layered, self-healing paths
that share one 24h marker, so it converges without a dedicated step here:

1. **SessionStart hook (`session-start.sh`) — primary.** Runs once per session; clones the
   skill if missing, else fast-forward-refreshes it (and refreshes the read-write mirror
   when that already exists — it does not provision the mirror itself).
2. **`/dev-pipeline:detect` STEP 0 — secondary safety net.** Runs at Phase 0 of flows that
   invoke detect, covering non-interactive sessions where the hook didn't fire.
3. **Skill-dependent commands self-bootstrap.** `/dev-pipeline:review` STEP 1.5 clones the
   skill if it's still missing when review runs directly.

So in practice a fresh machine that starts a session, or runs a pipeline flow, or runs
`/dev-pipeline:review`, ends up with the skill — but it is NOT literally bootstrapped before
*every* command (only those three paths). For a guaranteed one-shot install on a brand-new
device, run `/dev-pipeline:setup-machine`.

See `commands/detect.md` STEP 0 for the implementation.

---

## STEP 2: Create .claude/ Structure

```bash
mkdir -p .claude/docs .claude/instincts
touch .claude/agent-events.jsonl
```

Create `.claude/pipeline-state.json`:
```json
{ "phase": null, "task": null, "mius": [], "updatedAt": null }
```

Create `.claude/miu-progress.json`:
```json
{ "task": null, "mius": [], "updatedAt": null }
```

---

## STEP 3: Generate Living Documents

Create `.claude/docs/PROJECT_STATUS.md` from codebase scan:
- Current branch, recent commits (`git log --oneline -10`)
- Open PRs (`gh pr list`)
- Any TODO/FIXME density (`grep -r "TODO\|FIXME" src/ | wc -l`)
- Active blockers: none at init

Create `.claude/docs/ARCHITECTURE.md`:
- Stack summary from `project-profile.json`
- Directory structure (`find . -maxdepth 3 -type d | grep -v node_modules | grep -v .git`)
- Key dependencies from `package.json` (top 10)
- Environment variables from `.env.example` if present
- **Production URL topology** — if multiple deployable apps detected (any
  combination of `apps/*/vercel.json`, `apps/*/Dockerfile`, `apps/*/next.config.{js,mjs}`),
  invoke `/dev-pipeline:url-topology --probe` so `.claude/docs/URL_TOPOLOGY.md`
  is generated alongside this file. Link to it from the Deploy posture
  section. This prevents "agent assumed app X lives at URL Y, but actually
  lives at URL Z" failures — the classic miss when there's a subdomain split
  and a `basePath`, or multiple Vercel projects sharing a domain.

Create `.claude/docs/RECENT_CHANGES.md`:
- Last 10 commits formatted as entries

```bash
# URL topology dispatch — runs only when multi-app deployment surface detected.
APP_COUNT="$(find apps -maxdepth 2 -name 'vercel.json' -o -name 'Dockerfile' 2>/dev/null | wc -l)"
if [[ "$APP_COUNT" -ge 2 ]]; then
  bash "$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline/tools/url-topology.sh" --probe || true
fi
```

---

## STEP 4: Install Git Hooks

Hook bodies (`pre-commit`, `pre-push`, `post-commit`) ship inside this plugin at
`hooks/` and are installed by `hooks/setup-git-hooks.sh`. The plugin is fully
self-contained — no external scripts required.

The user-level entrypoint at `~/.claude/setup-git-hooks.sh` is a thin forwarder
that locates the plugin and runs the real installer. Either path works.

```bash
if [[ -d .git ]] && [[ ! -f .git/hooks/pre-push ]]; then
  PLUGIN_HOOKS="$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline/hooks/setup-git-hooks.sh"
  if [[ -f "$PLUGIN_HOOKS" ]]; then
    bash "$PLUGIN_HOOKS"
  elif [[ -f "$HOME/.claude/setup-git-hooks.sh" ]]; then
    bash "$HOME/.claude/setup-git-hooks.sh"
  else
    echo "⚠️  Hooks not installed — dev-pipeline plugin not found at expected paths."
  fi
fi
```

The check uses `pre-push` (not `pre-commit`) because the dev-pipeline contract
hinges on the pre-push gates (review-blessed-SHA + doc-update). pre-commit may
already be present from other tooling; that should not block re-installing
dev-pipeline's pre-push.

---

## STEP 5: Scaffold Missing Deploy Configs

Read `project-profile.json` → `scaffoldingMIUs`. For each:
- Create the missing config file with sensible defaults
- Commit: `chore: scaffold [config] for [platform]`

---

## STEP 6: Summary

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ PIPELINE INIT COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Stack:    [framework] / [runtime]
Deploy:   [targets]
Hooks:    [installed / already present]
Scaffolded: [list of new config files]
Docs:     .claude/docs/ created
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Next: /dev-pipeline:dev-pipeline [your first feature]
```
