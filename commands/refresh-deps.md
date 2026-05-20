---
description: Verify presence + pull the latest of every external plugin/skill/MCP that dev-pipeline references. Runs as Phase 0 of `/dev-pipeline:init` and on demand. Surfaces hybrid-skill drift.
argument-hint: [--pull]
---

# /dev-pipeline:refresh-deps

You are the **plugin freshness gate**. dev-pipeline assumes a set of external plugins/skills/MCPs exist; this command verifies and refreshes them. Without it, smart skill routing silently falls back to "skill not found" and Phase 7 implementations lose tech-stack guidance.

The hard logic lives in an executable so the result is reproducible:

```
$PLUGIN_ROOT/tools/refresh-deps.sh           # check + report only
$PLUGIN_ROOT/tools/refresh-deps.sh --pull    # also ff-only pull stale marketplaces
```

`$PLUGIN_ROOT` is `~/.claude/plugins/marketplaces/local/plugins/dev-pipeline`.

---

## What the script does

| Step | Action |
|---|---|
| 1 | Loads `deps.json` (plugin root) — the canonical list of expected externals. |
| 2 | Inventories every marketplace under `~/.claude/plugins/marketplaces/*` and every skill inside each plugin. |
| 3 | For each marketplace that is a git checkout: `git fetch origin`, compute how many commits HEAD is behind. With `--pull`, ff-only merge. |
| 4 | Cross-checks `deps.json → external.plugins[]` and `external.skills[]` against the inventory. |
| 5 | Hybrid-drift check: for each entry in `hybridSkills[]`, confirms the public skills it composes with are still present. Wildcards (e.g. `nodejs-*`) supported. |
| 6 | Writes `.claude/dev-pipeline-deps-status.json` in the cwd with full results. |
| 7 | Returns exit code: `0` clean, `1` required missing, `2` hybrid drift, `3` config error. |

---

## When this runs

| Trigger | Behavior |
|---|---|
| `/dev-pipeline:init` Phase 0 | Always (before project detection) |
| Once per 24h on session start (via session-start hook, when present) | Yes |
| `/dev-pipeline:refresh-deps` manual | Always |
| Before `/dev-pipeline:deliver` | Recommended; warn if stale |

## How to invoke from inside a pipeline phase

```bash
PLUGIN_ROOT="$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline"
bash "$PLUGIN_ROOT/tools/refresh-deps.sh"          # default: check only
bash "$PLUGIN_ROOT/tools/refresh-deps.sh" --pull   # auto-pull stale marketplaces
```

Then read `.claude/dev-pipeline-deps-status.json` to decide:
- `external.missingRequired[]` empty? → proceed.
- `hybridDrift[]` non-empty? → surface the warning in the next phase summary; do not block.
- `marketplaces.needsManual[]` non-empty? → tell the user; they need to resolve auth / merge conflicts.

---

## What this does NOT do

- **Does NOT install missing externals.** Claude Code's plugin system owns install. This command reports `missing` and tells you to `/plugin install <marketplace>/<name>` or visit the marketplace URL.
- **Does NOT downgrade externals if they break dev-pipeline.** Surfaces drift; human decides.
- **Does NOT touch `~/.claude/settings.json` (enabledPlugins).** Out of scope.
- **Does NOT auto-update MCPs.** MCPs run via `npx` or external servers; the status report lists them so you can `npx <name>@latest` manually.

---

## Why an executable, not pure markdown

The check involves filesystem scans, git operations, and JSON parsing across N marketplaces — too much to specify in prose. The executable produces deterministic output the rest of the pipeline can parse (`status.json`); the markdown is the human contract.

If you need to extend the check (e.g. new dependency kind), edit `tools/refresh-deps.sh` AND `deps.json` schema — the markdown only documents the contract.
