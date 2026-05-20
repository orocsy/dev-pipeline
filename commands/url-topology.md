---
description: Capture URL topology of every deployable app — hostnames, basePaths, redirect chains, referenced URL env vars. Writes .claude/docs/URL_TOPOLOGY.md. Runs automatically at the end of /dev-pipeline:init STEP 3 when multiple apps are detected.
argument-hint: [--probe]
---

# /dev-pipeline:url-topology

You are the **URL-topology cartographer**. Every multi-app repo eventually has bugs that boil down to "the agent assumed app X lived at URL Y, but it actually lived at URL Z". This command makes that assumption visible.

The hard logic lives in `$PLUGIN_ROOT/tools/url-topology.sh`. Invoke:

```
bash $PLUGIN_ROOT/tools/url-topology.sh                # scan repo only
bash $PLUGIN_ROOT/tools/url-topology.sh --probe        # also curl each candidate URL
```

`$PLUGIN_ROOT` is `~/.claude/plugins/marketplaces/local/plugins/dev-pipeline`.

---

## What it captures

For each app under `apps/*/` (or the repo root for single-app projects):

1. **Next.js `basePath`** — parsed from `next.config.{js,mjs}`. Critical: if `basePath: /admin` is set, the app's URLs all live under `/admin/*`, not at the bare hostname.
2. **Vercel build env hints** — `vercel.json → build.env` entries matching `*_URL`, `*_HOST`, `*_DOMAIN`. These are the production hostnames baked at build time.
3. **URL env vars referenced in `src/`** — every `process.env.X_URL` / `_DOMAIN` / `_HOST` / `_BASE_PATH` the app's source code consumes. If a referenced var isn't set anywhere, that's a missing-env risk.

For each candidate production URL found in configs/docs:

4. **Redirect chain** (with `--probe`) — `curl -I` records what `https://<host>/` actually returns: 200, 307 to `/admin/`, 404, etc.

Output: `.claude/docs/URL_TOPOLOGY.md` with a per-app table and a per-URL probe table.

---

## When this runs

| Trigger | Behavior |
|---|---|
| `/dev-pipeline:init` STEP 3 (auto, multi-app projects only) | `--probe` |
| Manual `/dev-pipeline:url-topology` | scan only (no network) |
| Manual `/dev-pipeline:url-topology --probe` | scan + probe |
| After every `next.config.js` / `vercel.json` edit (recommended) | manual |
| Before submitting OAuth consent screen URLs to Google (recommended) | manual |

---

## Why "scan only" by default

Probing requires network and can be slow / flaky / unavailable (VPN, offline dev). `init` opts into `--probe` because it's a one-time setup operation; everyday manual invocation defaults to scan only so it always completes.

---

## Why this exists (the failure mode it prevents)

A real session on luxebook (2026-05): the agent did `/dev-pipeline:init` on a multi-app monorepo (booking + admin + api), `init` STEP 3 generated `.claude/docs/ARCHITECTURE.md` with a single line ("Production URLs: getluxebook.com") scraped from a commit message subject. The agent then assumed admin lived at `getluxebook.com/admin` (path-based) because `next.config.js` had `basePath: /admin`. The actual production setup was `admin.getluxebook.com/admin/` (subdomain + basePath) — three different hostnames, none of which the init capture recorded.

Consequence: subsequent OAuth-compliance work targeted the wrong URL twice before being corrected. Hours of agent time + user frustration that a simple "where does each app live" lookup would have prevented.

`url-topology` makes the assumption explicit and writeable to disk so the next session reads it, doesn't have to re-discover it.

---

## What this command does NOT do

- Does NOT modify `vercel.json` or `next.config.js` — read-only on those.
- Does NOT validate that env vars are set in deployed environments (no Vercel API call). The "referenced but maybe-unset" column is a hint, not a verification.
- Does NOT follow redirect chains transitively. Single `curl -I` per URL. The `redirect_url` column tells you where the FIRST hop goes; if you need the full chain, follow it manually.
- Does NOT spider internal links. Just the candidate URLs scraped from configs.
