# dev-pipeline — Design Philosophy

Short notes on the few design decisions that took the most iteration. Read these before proposing a structural change; they exist because the obvious alternatives turned out worse in practice.

---

## 1. Plugin self-containment

**Rule:** every script, hook body, and dependency this plugin advertises must live inside the plugin tree.

**Why:** earlier versions referenced `~/.claude/setup-git-hooks.sh` but didn't ship it. Users who cloned the plugin got STEP 4 of `/dev-pipeline:init` silently no-op'ing because the script wasn't there. A "broken plugin in normal install state" failure mode is the worst kind: invisible.

**How:**
- Hook bodies live in `hooks/`.
- The user-level `~/.claude/setup-git-hooks.sh` (if present at all) is a 14-line forwarder that resolves the plugin path. Removing it does not break the plugin — `commands/init.md` STEP 4 calls the plugin's installer directly.
- Executable logic for commands (e.g. `tools/refresh-deps.sh`) lives in `tools/`.
- `deps.json` enumerates external dependencies. If something is required and not present, `refresh-deps` says so out loud.

**What this does NOT mean:** dev-pipeline absorbs functionality from other plugins. It still delegates to `code-review`, `commit-commands`, the vercel skill set, etc. The rule is about *the plugin's own promises* being self-contained, not about reinventing what other plugins already do well.

---

## 2. Decoupled siblings (spec-forge)

**Rule:** dev-pipeline and spec-forge never import each other's code. They communicate via `spec.json` + the `spec-forge` CLI.

**Why:** the two have different release cadences and audiences. spec-forge is for NEW projects (and might one day be public); dev-pipeline is for existing-project methodology (private). Coupling them at the code level would force lock-step releases.

**Concretely:**
- One bridge command: `/dev-pipeline:scaffold-from-prd` → resolves `$SPEC_FORGE_DIR` → invokes `tsx $SPEC_FORGE_DIR/cli.ts`.
- That command fails fast with a clear install pointer if spec-forge isn't present.
- Every other dev-pipeline command works without spec-forge installed.
- A project scaffolded by spec-forge can be operated by dev-pipeline forever after, without spec-forge ever being needed again.

---

## 3. spec-forge is a scaffolder, not a skills hub

**Rule:** spec-forge's `integrations/` directory contains project templates, not Claude Code runtime skills.

**Why this matters:** at first read it looks like there might be a conflict — both spec-forge and `claude-plugins-official` have "stuff named after the same domains" (next-app, prisma, vercel, …). There is no conflict because:

| | spec-forge `integrations/` | claude-plugins-official `plugins/` |
|---|---|---|
| Purpose | Files copied INTO newly-scaffolded projects | Skills/plugins Claude USES at runtime |
| Install path | `~/projects/spec-forge/integrations/<name>/` | `~/.claude/plugins/marketplaces/<mp>/plugins/<name>/` |
| Lifetime | Read once during scaffold, then never again | Live the entire time Claude is running |
| Activation | `tsx cli.ts scaffold <spec>` reads the manifest | Claude's plugin loader reads `marketplace.json` |
| Updated by | `git pull` of spec-forge OR adding new integration | `git pull` of the marketplace, `/plugin install` |

They live at different paths, serve different concerns, and never load each other's content. There is exactly one install path for Claude Code skills (`~/.claude/plugins/marketplaces/`) — spec-forge does not add a second one.

---

## 4. Git hooks: chain, don't replace

**Rule:** `hooks/setup-git-hooks.sh` honors `core.hooksPath` and, if a foreign hook already exists at the target, renames it to `<name>.next` and chains to it from the dev-pipeline hook.

**Why:** projects scaffolded by spec-forge (or pre-existing repos using husky / lefthook) already have hooks. Clobbering them silently breaks their pre-existing rules. Refusing to install silently breaks dev-pipeline's gates. Chaining preserves both.

**Order of execution when chained:**
1. dev-pipeline's body runs first — its gates fire (lint, blessed-SHA, doc-update).
2. On success, dev-pipeline tail-invokes `<hook>.next`, passing original args.
3. If either fails, the commit/push is blocked.

**Idempotency:**
- A second install detects identical content via `cmp -s` and reports `already current`.
- A second install detects dev-pipeline content via the `# dev-pipeline` marker on line 2 and updates without re-chaining (avoids stacking `.next.next.next`).

**Limitations:** if the foreign hook expects a specific cwd or env, the chain still works (we pass args through), but it now runs *after* dev-pipeline's gates rather than independently. Most hooks are order-insensitive; if one isn't, the user can manually re-order.

---

## 5. Refresh, don't auto-install

**Rule:** `/dev-pipeline:refresh-deps` reports missing externals and pulls stale marketplaces. It does NOT install plugins.

**Why:** Claude Code's plugin system owns install. The user has policy reasons (trust, audit, paid-vs-free preference) for choosing what to enable. Auto-installing would bypass that judgment. Reporting + linking to install instructions keeps the human in the loop.

**What the script does decide automatically:**
- Whether a marketplace is git-managed → fetches.
- Whether ff-only pull is safe → does the pull (with `--pull` flag).
- Whether the post-pull marketplace.json still lists every dep → updates the status JSON.

**What it punts to the user:**
- Whether a missing optional dep matters for *their* workflow.
- Whether a divergent marketplace should be rebased or recloned.
- Whether to install a brand-new external.

---

## 6. Hybrid skills are first-class drift risk

**Rule:** if an owned skill composes with public skills (e.g. `skill-router` routes to `vercel-react-best-practices`), the relationship is declared in `deps.json → hybridSkills[]`.

**Why:** public skill authors are free to rename, change activation triggers, or remove tools. dev-pipeline's composer (the owned skill) has no compile-time knowledge of that; it discovers breakage only when a pipeline phase fails midway. Declaring the composition lets `refresh-deps` flag the dependency early — *before* the next pipeline run, not during it.

**Maintenance protocol:**
- Whenever an external skill that's referenced in `hybridSkills[]` updates, re-read the owned skill's routing/composition logic and confirm names + triggers still align.
- If a public skill is removed upstream, treat it as a P1 task for the owned skill: re-route or remove the composition.
