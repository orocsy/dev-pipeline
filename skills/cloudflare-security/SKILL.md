---
name: cloudflare-security
description: Cloudflare-specific security configuration patterns — WAF Custom Rules, Bot Fight Mode / Super Bot Fight Mode, rate limiting, Page Rules, DNS records, Authenticated Origin Pulls. Activates when the user mentions Cloudflare + (WAF, bot challenge, firewall, security rules, managed challenge, custom rule, page rule, origin pull, DNS record), OR when diagnosing intermittent 4xx/5xx that match the CDN-bot-mitigation failure signature (HTTP 000 from SSR origins, generic node-fetch UAs being challenged, Vercel-IP-pool reputation drops). Prefers exact click-paths over vague guidance because Cloudflare's dashboard layout changes frequently.
---

# Cloudflare Security Skill

## When to activate

This skill is the right call when the conversation involves ANY of:

- A Cloudflare-fronted API behaving differently from direct-origin behaviour
- "Bot challenge" / "managed challenge" / "Bot Fight Mode" / "Super Bot Fight Mode" mentioned
- SSR fetches intermittently failing with HTTP 000 / dropped connections / non-JSON responses
- Need to write or modify a Cloudflare WAF Custom Rule expression
- Configuring rate limiting rules
- DNS record changes that affect security posture (proxied vs DNS-only, CNAME flattening)
- Authenticated Origin Pulls / Origin Rules
- "Why does the API work for my browser but fail from Vercel SSR?" diagnostic questions

If the user is asking about Cloudflare's data plane (Workers, R2, D1, KV) — not this skill, defer to the Cloudflare MCP (`mcp__719e1f83-..._workers_*`, `_d1_*`, `_kv_*`, `_r2_*`) which has direct API access for those.

## Available tools

The Cloudflare MCP attached to most setups (`mcp__719e1f83-...`) covers:

| Surface | MCP supports | Manual path |
|---|---|---|
| Workers code + lists | ✅ via `_workers_*` tools | dashboard or `wrangler` |
| D1 / KV / R2 / Hyperdrive | ✅ | dashboard or wrangler |
| Documentation search | ✅ via `_search_cloudflare_documentation` | docs.cloudflare.com |
| **WAF Custom Rules** | ❌ not exposed via MCP | dashboard OR Cloudflare API direct curl |
| **Bot Management config** | ❌ | dashboard |
| **Rate Limiting Rules** | ❌ | dashboard |
| **Page Rules** | ❌ (deprecated for new use anyway) | dashboard |
| **DNS Records** | ❌ | dashboard |

For WAF / Bot / Rate / DNS work: either guide the user through the dashboard click-path OR have them provision a Cloudflare API token with the right scope (e.g. `Zone:WAF:Edit`) and run a curl against `https://api.cloudflare.com/client/v4/...`.

## Core patterns

### Pattern 1: SSR-origin can't reliably reach a Cloudflare-fronted API

**Symptom:** intermittent HTTP 000 / 4xx from SSR fetches; browser fetches work fine. Vercel function logs show fetch failures but the origin's logs show no requests (because Cloudflare dropped them).

**Diagnosis:**
- Direct curl to API hostname → 200. Confirms origin healthy.
- SSR fetch from Vercel → fails intermittently. Confirms CDN-layer issue.
- Cloudflare Security → Events → filter by hostname → shows JS-challenged or blocked requests from Vercel egress IPs.

**Root cause:** Cloudflare's bot management (Bot Fight Mode on free, Super Bot Fight Mode on Pro+, full Bot Management on Enterprise) flags requests with:
- Generic UA (node-fetch, curl, axios) on shared cloud-host IPs
- TLS fingerprint that differs from a real browser
- Bursty per-IP request patterns typical of serverless workers

**Fix: shared-secret header + WAF Skip rule.** Authoritative reference: `spec-forge/integrations/edge-ssr-auth-header/patch/docs/edge-ssr-auth-header.md`. Operationally:
1. Server-side env var on hosting platform (e.g. Vercel) — `INTERNAL_API_TOKEN`, NOT `NEXT_PUBLIC_*` prefix.
2. Cloudflare Custom Rule on the API zone:
   - Expression: `(http.host eq "api.example.com" and http.request.headers["x-internal-token"][0] eq "<secret>")`
   - Action: Skip
   - Skip: Super Bot Fight Mode, managed rules, rate limiting, remaining custom rules
3. SSR code attaches header via `getInternalApiHeaders()` helper.
4. Verify with 30-iteration curl loop.

### Pattern 2: WAF Custom Rule expression syntax (Wirefilter)

Cloudflare's expression language is **Wirefilter** — Rust-based, evaluated at edge. Key gotchas:

- **Header lookups return arrays.** `http.request.headers["x-foo"]` is `["value1", "value2", ...]` (a header can appear multiple times). To compare a single value, use `[0]` index: `http.request.headers["x-foo"][0] eq "expected"`.
- **Header names are lowercased.** Cloudflare normalises HTTP headers to lowercase in expressions. Write `"x-internal-token"`, not `"X-Internal-Token"`. Both will match incoming traffic.
- **String comparison is `eq` not `==`.** `==` is invalid in Wirefilter.
- **`in {...}` for multi-value match.** `http.request.headers["x-foo"][0] in {"a" "b" "c"}` — space-separated values inside braces, NO commas.
- **Multi-condition uses `and` / `or`.** Lowercase. Parentheses required for mixing: `(A and B) or C`.
- **Negation is `not`.** `not http.host eq "api.example.com"`.
- **Path/URL fields:** `http.request.uri.path` (no query), `http.request.uri.query`, `http.request.full_uri` (with query). Use `contains`, `matches` (regex), `wildcard` for partial matches.
- **IP fields:** `ip.src` (string), `ip.geoip.country` ("US", "HK", etc.). For range matching, use `ip.src in $list_name` where `$list_name` references an IP List defined elsewhere.

Reference: `docs.cloudflare.com/ruleset-engine/rules-language/`.

### Pattern 3: Bot Fight Mode tiers — what skips work where

| Plan | Bot product | Custom Rule "Skip" target available? |
|---|---|---|
| Free | Bot Fight Mode | ❌ Skip not exposed in free Custom Rules UI |
| Pro / Business | Super Bot Fight Mode | ✅ "Skip Super Bot Fight Mode Rules" checkbox |
| Enterprise | Bot Management | ✅ Skip Bot Management + custom-rule-based actions |

Free-plan workarounds:
- **Page Rule** (max 3 on free): `URL pattern → Security Level: Essentially Off`. Coarse but works.
- **Disable BFM globally** via Security → Bots toggle. Removes protection for the whole zone, not just SSR egress. Only acceptable if zone-wide bot protection isn't valuable.
- **Upgrade to Pro** ($20/mo as of 2026). For a production SaaS, almost always the right call once you've hit this pattern.

### Pattern 4: Rate limiting rules

If under attack OR if your SSR is being rate-limited (separate from bot challenge):

- Dashboard: zone → Security → WAF → Rate limiting rules → Create.
- Counting: by IP, by header value (e.g. by API key), by cookie, by JA3 fingerprint.
- Action: Block, Challenge, Log, Skip.
- Free tier: 10 rate limiting rules. Pro: 25. Business: 50.

To rate-limit the API but NOT rate-limit your SSR: write the rule with `http.host eq "api.example.com" and not http.request.headers["x-internal-token"][0] eq "<secret>"` — same header trick as Pattern 1.

### Pattern 5: DNS record changes that affect security

Cloudflare DNS records have two posture modes (orange / grey cloud):

- **Proxied (orange cloud)** — traffic flows through Cloudflare. All security products apply (WAF, bot management, DDoS, rate limit, CDN cache).
- **DNS only (grey cloud)** — Cloudflare resolves DNS but returns origin IP directly. No security products apply.

Common mistake: setting `api.example.com` to grey cloud "to bypass Cloudflare". That exposes the origin IP publicly and disables ALL protection. The correct path for selective bypass is the WAF Skip rule in Pattern 1, NOT grey-clouding the record.

### Pattern 6: Authenticated Origin Pulls

For Pro+ plans, you can require that requests to your origin come from Cloudflare (mTLS):

- Cloudflare presents a client certificate signed by Cloudflare CA on every request to origin.
- Origin (nginx, ALB, etc.) requires + validates the cert.
- Anyone with the origin's IP can't bypass Cloudflare anymore.

This is COMPLEMENTARY to the WAF rule pattern, not a replacement. Authenticated Origin Pulls protect the origin from direct bypass; the WAF rule protects the SSR from being challenged on its way THROUGH Cloudflare.

## Click-path navigation cheat sheet

```
dash.cloudflare.com
  ├─ Websites tab → click a zone (e.g. example.com)
  │    │
  │    ├─ Overview                       (zone summary, plan, edit)
  │    ├─ DNS → Records                  (A, CNAME, MX, TXT; orange/grey cloud)
  │    ├─ SSL/TLS                        (Edge cert, Origin cert, AOP)
  │    ├─ Security
  │    │    ├─ Events                    (audit log of WAF actions)
  │    │    ├─ WAF
  │    │    │    ├─ Custom rules         ← Pattern 1 lives here
  │    │    │    ├─ Rate limiting rules  ← Pattern 4
  │    │    │    ├─ Managed rules        (paid OWASP/Cloudflare-managed)
  │    │    │    └─ Tools                (Zone Lockdown, IP Access Rules)
  │    │    ├─ Bots                      (Bot Fight Mode toggle, Super BFM)
  │    │    ├─ DDoS                      (auto-mitigation; rarely tuned)
  │    │    └─ Settings                  (Security Level, Challenge Passage)
  │    ├─ Rules
  │    │    ├─ Page Rules                ← Pattern 3 fallback (free)
  │    │    ├─ Transform Rules
  │    │    ├─ Redirect Rules
  │    │    └─ Origin Rules
  │    ├─ Speed                          (caching, image optimisation, perf)
  │    ├─ Caching                        (cache rules, purge)
  │    └─ Workers Routes                 (assign workers to URL patterns)
  │
  └─ Account home (top-left)
       ├─ Plans                          (verify current plan tier)
       ├─ API Tokens                     (create scoped tokens)
       └─ Audit Log                      (account-level changes)
```

## API token scopes for common tasks

Create tokens at `dash.cloudflare.com → My Profile → API Tokens → Create Token`.

| Task | Minimum scope |
|---|---|
| Read WAF rules | `Zone:WAF:Read` |
| Create/modify WAF Custom Rule | `Zone:WAF:Edit` + `Zone:Zone:Read` |
| Read DNS records | `Zone:DNS:Read` |
| Modify DNS records | `Zone:DNS:Edit` |
| Read Bot Management config | `Zone:Bot Management Read` (Enterprise) |
| Modify Bot Management config | `Zone:Bot Management Write` (Enterprise) |
| Purge cache | `Zone:Cache Purge:Purge` |

Always scope tokens to a single zone (not "All zones") unless absolutely necessary. Tokens are revocable; rotate after one-off operations.

## Common diagnostic recipes

### "API works for me in browser, fails from production SSR"

1. From your machine: `curl -sI https://api.example.com/...` — should return 200.
2. From a Vercel function logs perspective: look for failed-fetch entries with status 000 / connection-refused / timeout.
3. Cloudflare → Security → Events → filter by hostname `api.example.com` → look for entries with `Action: Managed Challenge` or `Action: Block`.
4. If events show Vercel egress IPs being challenged → Pattern 1 (header bypass).
5. If events show no entries at all → not Cloudflare, look at origin (EC2 / RDS / network path).

### "Rule deployed but not firing"

1. Check rule placement order (Cloudflare evaluates Custom Rules top-to-bottom; a Block above your Skip wins).
2. Verify expression syntax: use the "Validate" button in the rule editor.
3. Confirm `http.host` matches the actual zone-routed hostname (case-insensitive, but verify spelling).
4. Set Action: Log temporarily → check Security Events → confirm the rule sees the traffic.
5. If Log shows matches but Skip-mode doesn't help → check what other rule is firing INSTEAD (Skip skips lower-priority phases; if a Block at the same phase fires first, Skip won't help).

### "Bot challenges happening even with valid token"

1. Token mismatch: dashboard expression vs Vercel env value — paste-the-same-thing test.
2. Token not reaching CF: `Security → Events → expand event → request headers` — confirm `x-internal-token` is present and value matches.
3. NEXT_PUBLIC_ prefix accidentally exposes the token to browser (worse: browsers send it, scrapers can read it from page source). `curl https://your-app | grep token` should return empty.
4. Skip targets wrong phase: re-verify "Skip Super Bot Fight Mode" + "managed rules" are checked.

## What this skill does NOT cover

- **Cloudflare Workers code itself** — different skill / Cloudflare MCP `_workers_*` tools.
- **Zero Trust / Access policies** — adjacent product, different config surface.
- **Magic Transit / Magic WAN** — enterprise networking, out of scope for typical SaaS.
- **Multi-tenant ZT setup** — see Cloudflare for Teams docs.
- **Pricing decisions** — defer to user; this skill doesn't recommend plan upgrades unless the user explicitly asks "what plan do I need for X".

## Sources of truth

- Wirefilter expression reference: `docs.cloudflare.com/ruleset-engine/rules-language/`
- Custom Rules action types: `docs.cloudflare.com/waf/custom-rules/`
- Bot Management feature comparison: `developers.cloudflare.com/bots/get-started/`
- API reference: `developers.cloudflare.com/api/operations/`
- For dashboard changes (Cloudflare ships UI updates frequently), invoke `mcp__719e1f83-..._search_cloudflare_documentation` with the user's specific question.
