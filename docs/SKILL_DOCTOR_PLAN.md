# Skill Doctor — Plan

Closes the gap surfaced by the first `/dev-pipeline:refresh-deps` run: 15 optional skills missing + 6 hybrid-drift entries, all because public skill names referenced in dev-pipeline have moved / consolidated / been deprecated upstream. `refresh-deps` reports the drift; `skill-doctor` resolves it.

---

## Problem (as observed on a real multi-app project)

dev-pipeline references skills by their HISTORICAL names. The ecosystem moved on:

| dev-pipeline says it needs | What's actually upstream | Detection cost |
|---|---|---|
| `vercel-react-best-practices`, `vercel-composition-patterns` | No standalone plugin. The current `vercel` plugin is a deployment tool, not a coding-style skill. These were community skills that didn't persist. | Cannot resolve without web search. |
| `ui-ux-pro-max`, `web-design-guidelines` | `frontend-design` (single plugin replacing both) | Resolvable by description-match in `claude-plugins-official`. |
| `nestjs-best-practices`, `nestjs-modules`, `mastering-typescript`, `websocket-engineer`, `nodejs-*` (×7) | Not in `claude-plugins-official`. Likely in personal / community marketplaces. | Requires web search + marketplace discovery. |

`refresh-deps` correctly says "missing". What it can't do: figure out the canonical replacement name, suggest a deps.json patch, or queue the install action. That's `skill-doctor`'s job.

---

## Design — `/dev-pipeline:skill-doctor`

A diagnostic + remediation flow that runs AFTER `refresh-deps` and turns each missing/drifted entry into one of three outcomes:
1. **Auto-resolvable** — found a near-match in an installed marketplace → propose deps.json + skill-router patch.
2. **Marketplace-resolvable** — found in a marketplace NOT yet added → propose `/plugin marketplace add` command.
3. **Search-required** — no match anywhere local → emit a web-search prompt the LLM can act on.

### Three modes

| Mode | Output | Side effects |
|---|---|---|
| `--report` (default) | `.claude/dev-pipeline-skill-doctor-plan.md` with prioritised action items | none |
| `--apply` | Same report + applies non-destructive auto-resolves (deps.json patches, skill-router edits behind a marker) | edits dev-pipeline source |
| `--search` | Same report + LLM-driven web search for `search-required` entries | reads web; never writes plugin installs |

`--apply` does NOT install plugins or enable plugins. Plugin enablement remains a Claude Code policy decision (you decide which marketplaces to trust). The mode applies only edits inside `deps.json` and `skills/*/SKILL.md`.

### Resolution pipeline (per missing skill `X`)

1. **Exact name match** across `~/.claude/plugins/marketplaces/*/plugins/*/skills/*/SKILL.md` → if found, classify as `installed-but-not-in-deps` (fix: update deps.json to remove the false-missing).
2. **Plugin-as-skill match** — a plugin whose top-level `SKILL.md` (single-skill plugin) shares the name → same fix.
3. **Description fuzzy-match** — read every installed `SKILL.md`'s frontmatter `description`. Compute trigram similarity with `X` and the `usedBy` context from `deps.json`. If best match ≥ 0.7, propose rename (e.g. `ui-ux-pro-max` → `frontend-design`).
4. **Marketplace catalog match** — scan every `marketplaces/*/.claude-plugin/marketplace.json`, including ones NOT yet installed locally (entries with `"source": "url"` aren't downloaded but ARE listed). If the name or a fuzzy match appears → propose `/plugin install <marketplace>/<name>`.
5. **Search-required** — emit a structured search prompt:
   ```
   SEARCH: "<X>" replacement for Claude Code dev-pipeline.
   Originally used by: <usedBy from deps.json>
   Likely categories: <inferred from name prefix>
   Action: web search for "Claude Code skill <X>" + "Claude plugin <stem of X>" + similar.
   If found, propose deps.json patch with new name + marketplace URL.
   ```

### Output format

`.claude/dev-pipeline-skill-doctor-plan.md`:

```markdown
# Skill Doctor — Action Plan
checkedAt: 2026-05-20T08:00:00Z

## Auto-resolvable (apply with --apply)
- [PATCH] deps.json: rename `ui-ux-pro-max` → `frontend-design`
        reason: description match (0.83) against frontend-design SKILL.md
        also-update: skills/skill-router/SKILL.md (2 references)
- [PATCH] deps.json: drop `web-design-guidelines` (merged into frontend-design)

## Marketplace-resolvable (run the suggested command)
- [INSTALL] vercel-deploy: `/plugin marketplace add https://github.com/vercel/vercel-plugin.git`
        used-by: scaffold-from-prd, deploy

## Search-required (LLM web search needed)
- [SEARCH] nestjs-best-practices — used by implement, detect
        prompts:
          "Claude Code skill nestjs best practices"
          "Claude plugin nestjs marketplace github"
        action: If found, propose marketplace add + deps.json update.
- [SEARCH] nodejs-* family (7 entries) — used by implement
        prompts:
          "Claude Code plugin nodejs skills"
          "Claude plugin marketplace nodejs production"
```

### Init wiring

`/dev-pipeline:init` STEP 0 already calls `refresh-deps`. New behavior:

```
After refresh-deps:
  if exit code == 0      → continue to STEP 1 (silently)
  if exit code == 1      → STOP (required missing)
  if exit code == 2      → invoke /dev-pipeline:skill-doctor --report
                           → if Auto-resolvable items exist, ask the user once:
                             "Skill doctor found N auto-fixable references. Run --apply? [y/N]"
                           → otherwise surface the report path in init summary
                           → continue to STEP 1
```

This makes init self-healing for the common rename case without ever silently mutating source.

---

## `deps.json` schema additions

```jsonc
{
  "marketplaces": [
    {
      "name": "claude-plugins-official",
      "source": { "type": "github", "repo": "anthropics/claude-plugins-public" },
      "required": true,
      "provides": ["code-review", "commit-commands", "context7", "frontend-design", "typescript-lsp"]
    },
    {
      "name": "local",
      "source": { "type": "local", "path": "~/.claude/plugins/marketplaces/local" },
      "required": true,
      "provides": ["dev-pipeline"]
    }
  ],
  "external": {
    "skills": [
      {
        "name": "frontend-design",
        "required": false,
        "trigger": "UI/design phase",
        "usedBy": ["plan"],
        "marketplaceHint": "claude-plugins-official",
        "supersedes": ["ui-ux-pro-max", "web-design-guidelines"]
      }
    ]
  }
}
```

`supersedes[]` lets refresh-deps mark old names as "renamed" rather than "missing" once the new name is in the manifest. skill-doctor uses it to drive Auto-resolvable patches.

---

## Implementation steps

1. **deps.json v2** — add `marketplaces[]`, `marketplaceHint`, `supersedes[]`. Update existing entries.
2. **tools/skill-doctor.sh** — resolution pipeline (steps 1–5 above), emits `.claude/dev-pipeline-skill-doctor-plan.md`.
3. **commands/skill-doctor.md** — human contract documenting modes + exit codes.
4. **tools/refresh-deps.sh** — honor `supersedes[]` so renamed-but-resolved skills don't show as missing.
5. **commands/init.md STEP 0** — auto-invoke `skill-doctor --report` when refresh-deps returns exit 2.
6. **smoke test** — run end-to-end on the reference project; expect:
   - `ui-ux-pro-max` + `web-design-guidelines` resolved to `frontend-design` (auto-resolvable).
   - `vercel-*` flagged for marketplace-resolvable (since vercel plugin exists upstream).
   - `nestjs-*`, `nodejs-*`, `mastering-typescript`, `websocket-engineer` flagged as search-required.
7. **Apply auto-resolves** for the reference project: update deps.json + skill-router/project-detector references.
8. **Final refresh-deps + skill-doctor** rerun — confirm exit code drops from 2 to either 0 or a smaller drift count.
9. **Commit + push** as one or two logical commits.

## Out of scope (explicit non-goals for this round)

- Auto-installing plugins. Plugin install is a Claude Code interactive concern; doctor only proposes commands.
- Auto-editing `~/.claude/settings.json → enabledPlugins`. User policy decision.
- Web search execution. `--search` mode emits prompts the LLM can run; doctor itself doesn't ship a search engine.
- Auto-creating brand-new SKILL.md files for unfindable skills. That's a separate "skill-authoring" workflow.

## Success criteria

- `/dev-pipeline:refresh-deps` exit 2 on the reference project drops to either 0 (clean) or surfaces only "search-required" entries.
- `deps.json` has zero stale names (every entry maps to either an installed skill or an upstream URL).
- skill-doctor plan file lives at a known path so a future session can resume the search-required items.
