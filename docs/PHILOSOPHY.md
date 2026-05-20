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

---

## 7. Read docs BEFORE code (the "wait, where does this live in prod?" check)

**Rule:** before writing any code that depends on deployment topology, runtime URLs, env-var contracts, or data-model invariants, read the project docs that document those things. The order is:

1. `README.md` — production URL topology, public API, "first-thing-an-engineer-should-know" section.
2. Project root `CLAUDE.md` — safety invariants, env-var patterns, multi-tenancy / consistency rules.
3. `.claude/docs/ARCHITECTURE.md` and `.claude/docs/URL_TOPOLOGY.md` (if present).
4. `docs/architecture-*.md`, `docs/deployment-*.md` — deeper topology.
5. THEN code (`vercel.json`, `next.config.js`, source).

**Why this order matters:** code shows what IS, docs explain what's INTENDED. If you read code first you'll often back-infer an "obvious" architecture that's actually wrong — `basePath: /admin` doesn't tell you whether the app is at `getluxebook.com/admin` (path-based) or `admin.getluxebook.com/admin` (subdomain + basePath). README says.

**Failure mode this prevents:** the 2026-05 OAuth-compliance work that targeted the wrong URL for three turns because the agent read `next.config.js` first, assumed path-based admin, never opened `docs/architecture-nginx-deployment.md` which had the ASCII diagram of the actual topology.

**Test for whether you read enough docs:** can you state, in one sentence per app, what hostname + path each deployed app lives at, including any framework-level redirects? If no, you haven't read enough.

---

## 8. Fix patterns, not enumerations

**Rule:** when you find a bug, look for the GENERAL CLASS, not just the specific symptom that surfaced. Then fix at the class level.

**Anti-pattern (enumeration fix):** user reports "`/en/admin` shows a fake store". Fix: redirect `/en/admin` somewhere else. Next week: "`/en/media` also shows a fake store". Each new symptom is fixed one URL at a time.

**Right pattern (class fix):** root cause is the fallback that renders a fake tenant on ANY error. Fix: drop the fallback. Every random slug now 404s. Pattern handled; future random slugs don't need separate fixes.

**Failure mode:** the booking app's `[locale]/[tenantSlug]` catch-all renders a "fake-tenant" page for any unknown slug. Pre-fix mental model was "add a redirect for `/admin/`". Post-fix mental model: "any unknown slug 404s, no fallback ever".

**Test:** before declaring a bug fixed, ask: "what other inputs would have triggered the same root cause, and does my fix cover them too?"

---

## 9. No file is "out of scope" inside the repo

**Rule:** every file in the repo you're working on is fixable. `next.config.js`, `vercel.json`, `Dockerfile`, CI workflows, even `package.json` — all of them are your code. If the right fix is to edit one of those instead of the file you started in, edit that one.

**Anti-pattern:** "Hop 1 is still there because it's a Next.js-level redirect that's outside my page code." This frames a config file as someone else's problem. It isn't. Reframe: "Hop 1 is configurable in `next.config.js → redirects()`. Here are the options for changing it: [A], [B], [C]. I recommend [B] because [reasons]."

**Failure mode:** focusing the fix on one component (the page that redirects) and missing the cleaner fix one layer up (the framework-level redirect that caused the same chain). Limiting your scope to "my page code" doubles the chance of the same issue recurring.

**Test:** before declaring a fix complete, ask: "is there a SIMPLER fix one level UP the stack (config / build / framework / infra) that I dismissed because it's not in my immediate code area?"

---

## 10. Self-correct mid-process, not just at output

**Rule:** when an assumption is corrected mid-work (by the user, by a different agent, by your own re-reading), STOP and redo affected steps in the SAME turn. Don't "note the correction and continue past it".

**Anti-pattern:** user says "admin.getluxebook.com is what I meant". Agent says "okay, noted" and keeps building OAuth pages targeting `getluxebook.com/admin`. The correction landed but didn't propagate.

**Right pattern:** user corrects an assumption → agent (a) acknowledges, (b) re-reads the relevant docs to verify the corrected version, (c) re-evaluates what's been built so far against the corrected reality, (d) fixes any drift before continuing forward.

**Operationalisation:** the `assumption-checker` agent (see `agents/assumption-checker.md`) is the dev-pipeline's automatic version of this. It fires at every MIU boundary and before every review, so mid-work drift can't accumulate silently until final output.

**Test:** when corrected, list what work-already-done depended on the now-wrong assumption. If that list is non-empty, redo before moving on.

---

## 11. Cross-check is a constraint, not a manual gate

**Rule:** the same way a high-quality human team has a second pair of eyes baked into the workflow (PR review, pair programming, code-review checklist), dev-pipeline's cross-check (`assumption-checker` + `validator` + the parallel reviewers in `/dev-pipeline:review`) is AUTOMATIC. It does not require the user to invoke `/dev-pipeline:review` manually.

- `/dev-pipeline:implement` MUST invoke `assumption-checker` at every MIU boundary.
- `/dev-pipeline:review` MUST invoke `assumption-checker` first, then the parallel deep / typescript / security / test reviewers.
- The post-commit hook MUST emit the AUTO-REVIEW DIRECTIVE.
- The pre-push hook MUST require a fresh `.last-reviewed-sha`.

If any of these gates becomes opt-in instead of automatic, the workflow has decayed back to "human notices the drift if they happen to look". That's the failure mode.

**Test:** can the human user complete a feature ship WITHOUT typing any `/dev-pipeline:*` command, and still get every gate fired? If yes, the automation is right. If no, find the missing trigger.
