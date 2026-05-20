---
description: Diagnose missing/drifted external skills and propose fixes. Runs AFTER /dev-pipeline:refresh-deps when exit code indicates drift. Three modes — report, apply, search.
argument-hint: [--report | --apply | --search]
---

# /dev-pipeline:skill-doctor

You are the **rename + drift resolver**. When `refresh-deps` says a skill is missing, you figure out whether it was renamed, moved to a different marketplace, deprecated entirely, or just never installed — then propose a concrete fix.

The hard logic is in the executable so the resolution is reproducible:

```
$PLUGIN_ROOT/tools/skill-doctor.sh                # default: --report
$PLUGIN_ROOT/tools/skill-doctor.sh --apply        # apply non-destructive auto-resolves
$PLUGIN_ROOT/tools/skill-doctor.sh --search       # emit web-search prompts for unmatched skills
```

`$PLUGIN_ROOT` is `~/.claude/plugins/marketplaces/local/plugins/dev-pipeline`.

---

## Resolution pipeline (per missing skill `X`)

Each missing entry from `.claude/dev-pipeline-deps-status.json` is run through this in order. First match wins.

| Step | Match against | Outcome |
|---|---|---|
| 1 | Already declared `supersedes[]` in deps.json | Auto-resolvable — drop old name |
| 2 | Exact name in installed `SKILL.md` files | Auto-resolvable — refresh-deps misclassified |
| 3 | Plugin name matches a single-skill plugin's `name` (top-level `SKILL.md`) | Auto-resolvable — same |
| 4 | Plugin listed in any marketplace catalog (downloaded or URL-only) | Marketplace-resolvable — propose `/plugin install` |
| 5 | Fuzzy match: token overlap with installed `SKILL.md` descriptions | Auto-resolvable — propose rename |
| 6 | None of the above | Search-required — emit LLM web-search prompts |

---

## Modes

### `--report` (default)

Read-only. Writes `.claude/dev-pipeline-skill-doctor-plan.md` with three sections:
- **Auto-resolvable** — items the `--apply` mode can fix mechanically.
- **Marketplace-resolvable** — items already known to a marketplace; needs interactive `/plugin install`.
- **Search-required** — items with no local trace; emits structured web-search prompts.

Exit code: `2` if any auto-resolvable items exist (so init knows to prompt), `0` otherwise.

### `--apply`

Same report PLUS applies non-destructive patches:
- Drops entries from `deps.json → external.skills[]` whose name appears in another entry's `supersedes[]`.
- Removes references to those old names from `hybridSkills[].composesWith[]`.
- For fuzzy-match renames: leaves a manual-edit suggestion (rewording surrounding prose in `skill-router` / `project-detector` requires human judgment, not regex replace).

Does NOT:
- Install plugins (Claude Code interactive concern).
- Edit `enabledPlugins` in `~/.claude/settings.json` (user policy).
- Mutate `skill-router` / `project-detector` SKILL.md prose (only deps.json + hybridSkills).

### `--search`

Same report PLUS for every search-required entry, emits structured prompts the LLM can use to web-search. Example:

```
SEARCH: nodejs-best-practices replacement for Claude Code dev-pipeline
prompts:
  "Claude Code skill nodejs best practices"
  "Claude plugin marketplace nodejs production"
follow-up: if found, propose deps.json + marketplaces[] patch.
```

The LLM driving the session is responsible for the actual web search; the script just produces the prompt set.

---

## Init wiring

`/dev-pipeline:init` STEP 0 calls `refresh-deps`. If `refresh-deps` returns exit code 2 (hybrid drift), init auto-invokes `/dev-pipeline:skill-doctor --report`. The init summary then surfaces:
- "Skill doctor found N auto-fixable items — run `/dev-pipeline:skill-doctor --apply` to fix."
- "Skill doctor flagged M items as search-required — see `.claude/dev-pipeline-skill-doctor-plan.md`."

Init does NOT auto-`--apply`. The rename of public-skill references touches prose in owned skills; that's a human-review change.

---

## How `supersedes[]` works

When you discover that public skill `old-name` has been replaced by `new-name`, edit `deps.json`:

```json
{
  "name": "new-name",
  "required": false,
  "marketplaceHint": "claude-plugins-official",
  "supersedes": ["old-name", "older-alias"]
}
```

After that:
- `refresh-deps` will look for `new-name` and stop flagging `old-name` as missing.
- `skill-doctor` will classify any remaining `old-name` reference as auto-resolvable.
- `--apply` will drop the explicit `old-name` entries from the schema.

---

## When this runs

| Trigger | Behavior |
|---|---|
| `/dev-pipeline:init` STEP 0.5 (refresh-deps exit 2) | `--report` |
| Manual `/dev-pipeline:skill-doctor` | `--report` |
| Manual `/dev-pipeline:skill-doctor --apply` | apply auto-resolves |
| Manual `/dev-pipeline:skill-doctor --search` | emit search prompts |

## Exit codes

- `0` — nothing to fix OR everything that can be applied was applied.
- `1` — config error (deps.json missing, jq missing, etc.).
- `2` — auto-resolvable items exist (re-run with `--apply` to fix).

## What this does NOT do

- Install Claude Code plugins.
- Run web searches itself (it produces prompts).
- Author new SKILL.md files for skills that genuinely don't exist anymore.
- Modify prose in owned skills (e.g. `skills/skill-router/SKILL.md`).
