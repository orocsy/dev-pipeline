---
name: cross-file-reasoning
description: Mandatory cross-file consistency checklist for any code change that introduces or modifies a value, symbol, route, env-var, event, or SDK option consumed at a separate file. Invoked automatically by /dev-pipeline:implement (per-MIU) and /dev-pipeline:review (pre-push). Reading this skill costs tokens; missing one of its checks costs production incidents.
---

# Cross-File Reasoning

You are about to declare an MIU done or about to bless a SHA for push. Before you do that, you MUST trace EVERY new symbol / value / file path the diff introduces or modifies through to its consuming sites. Not just the file you're looking at. **The whole graph.**

This skill exists because of one recurring failure mode: **single-file thinking**. The implementing agent reads one file deeply, makes a locally-correct change, and ships it. The bug lives at the seam — env-var, route, SDK option, mock interface, event lifecycle — where another file's expectations don't match. The unit test for the file passes. The fix's contradiction with the OTHER file is invisible until production (or worse, until a post-merge reviewer catches it after the agent has already moved on).

Run this skill at:
- **Every MIU boundary** (before the MIU is marked complete) — `/dev-pipeline:implement` STEP 4.5
- **Every pre-push review** (before bless) — `/dev-pipeline:review` STEP 2 (the cross-file reviewer)
- **Any time you change an env-var schema, an SDK init, a route file path, or an event emit** — manual, immediate

If the diff has zero symbols that cross file boundaries (e.g. a pure CSS tweak, a comment-only change, a doc edit), you can skip. Otherwise: **do every trace below**.

---

## The Seven Traces

For each NEW or CHANGED symbol the diff introduces, walk the appropriate trace. Don't skim — `grep` the whole repo. Cross-file bugs hide in the assumption that "this is the only place".

### Trace 1 — Env-var trace (PRODUCER → CONSUMER → FALLBACK)

When the diff adds, removes, or renames a `process.env.X` reference, walk the FULL chain:

1. **Producer**: where is `X` declared as a deploy secret? Check (in this order):
   - `.env.example` (the contract)
   - `.github/workflows/*.yml` (CI / deploy injection — `env:` block, `docker run -e`, `secrets.X`)
   - `vercel.json` (build env, `env`, `build.env`)
   - `docker-compose*.yml` (the `environment:` block)
   - Local `.env`, `.env.local`, `.env.production` if tracked (they shouldn't be)
2. **Consumer**: where is `process.env.X` actually read? `grep -rn 'process.env.X' apps/ packages/`. Every read site is a consumer.
3. **Fallback semantics**: at each consumer, what happens when `X` is `undefined` vs `''` (empty string)?
   - `??` falls back ONLY on `null|undefined`. **Empty strings pass through.**
   - `||` falls back on any falsy value (empty string, 0, false). **Use this when "missing" includes "empty".**
   - Many secret pipelines (GitHub Actions `${{ secrets.X }}` when secret is unset, Vercel optional env when blank) pass `''` to the runtime. If your fallback is `??`, the default is silently lost.
4. **Validation**: is `X` in the env schema (`config/env.schema.ts`, `zod` schema, etc.)? If marked optional, does the consumer handle missing gracefully? If marked required, does CI fail when missing?

Output for each new env-var: a 5-line table — `X declared in <file>, consumed at <file:line>, fallback uses <?? | ||>, empty-string behavior is <pass through | fall back>, validated in <schema | NOT VALIDATED>`.

### Trace 2 — Route / path / URL trace (FILE PATH → EFFECTIVE URL)

When the diff adds, moves, or renames a route file (Next.js `app/`, NestJS `@Controller(...)`, Express route, etc.), the file path is NOT the URL. Compose:

```
effective URL = host + protocol prefix (CDN/router) + framework prefix (basePath, locale, route group, version) + file path
```

For each new/moved route file:

1. **Read the framework config** (don't trust memory): `next.config.js → basePath`, `middleware.ts → i18n routing`, `nestjs main.ts → setGlobalPrefix`, `vercel.json → routes`/`rewrites`/`redirects`.
2. **List EVERY prefix** the framework will prepend: basePath, locale prefix, route group `(group)` (which is invisible — does NOT contribute to URL), dynamic segments `[param]`.
3. **State the effective URL** out loud (in a comment or in the engineering rationale). Then verify a consumer reaches it.

The recurring trap: Next.js `basePath: '/admin'`. A file at `app/admin/posthog/[...path]/route.ts` resolves at `/admin/admin/posthog/*`, not `/admin/posthog/*`. Because basePath is added by the FRAMEWORK at runtime, the developer who already wrote `/admin` in the path is doubling it.

For each new route: in the engineering rationale, write `Effective URL: <full URL with all prefixes applied>` and then `grep` for any client code that uses that URL. If they don't match, you have a bug right now.

### Trace 3 — SDK / framework option-name trace (CODE → TYPE DEFS)

SDK options are versioned. Memory, blog posts, and the LLM's training data can all be wrong about an option's name in the version actually installed. The type definitions in `node_modules/<pkg>/dist/**/*.d.ts` are the source of truth.

When the diff sets a config option on any SDK (PostHog, Sentry, Stripe, Prisma, ioredis, BullMQ, Next.js config, etc.):

1. **`grep` the installed package's type defs** for the option name:
   ```bash
   grep -rn 'optionName' node_modules/<package>/dist/ | head -10
   ```
2. If the option does NOT appear in the type defs: it doesn't exist in this version. Look up the right option, or accept that the SDK doesn't support what you want.
3. **Check the version pinned in `package.json`** before consulting external docs. Docs default to the latest version; the installed version may be different.

The recurring trap: `posthog-js` v1.376 has no `maskAllText` (must use `maskTextSelector: '*'`) and no `disable_exception_autocapture` (the option is `capture_exceptions: false`). Setting a non-existent option is silently ignored — the SDK accepts unknown keys without warning.

For each SDK option set in the diff: in the engineering rationale, write `Verified <optionName> in node_modules/<pkg>/dist/<file>.d.ts (line N)`. If not verifiable, write `Could not verify — option may be ignored at runtime`.

### Trace 4 — Event lifecycle trace (EMIT → SUBSCRIBE → ERROR / TX SEMANTICS)

When the diff emits or subscribes to an event (`EventEmitter2`, `Subject`, custom pub/sub, message queue), trace:

1. **Emit site**: what's the calling context? Is the emit inside a transaction (Prisma `executeInTransaction`, ORM unit of work, request scope)?
2. **Subscribe site**: what listener fires? Is it `async` (returns a Promise) or sync? Does it throw, and if so, is the throw propagated back to the emit site? (For `@nestjs/event-emitter`, default `suppressErrors: true` swallows listener throws — the emit site never knows.)
3. **Side-effect semantics**: if the listener triggers a fire-and-forget external SDK call (PostHog `capture`, Stripe `events.create`, Slack webhook), the queued operation flushes EVEN IF THE EMIT SITE'S TX ROLLS BACK. Document this trade-off.
4. **Failure-mode matrix**:

| Listener behavior | Tx commits | Tx rolls back |
|---|---|---|
| Sync, throws, `suppressErrors: false` | Throw bubbles → tx rolls back. OK. | Throw bubbles → tx rolls back. OK. |
| Sync, fire-and-forget SDK capture | Captured. OK. | **Captured anyway — ghost event.** Trade-off. |
| Async, returns Promise unawaited | Floating Promise — may run after request closes | Same — may capture event for cancelled work |
| `suppressErrors: true` (default) | OK | **Tx still commits despite listener failure** — silent loss |

In the engineering rationale for the new event: state which row you're in and why.

### Trace 5 — Mock-completeness trace (MOCK → REAL INTERFACE)

When a test mocks a service that has been EXTENDED (new method, new field, new constructor arg), the existing mocks may pass while the production code breaks. Mock-based unit tests give you false confidence in proportion to how much of the real interface the mock omits.

For each diff that changes a class signature (new constructor arg, new public method, new injected dependency):

1. **List every spec file** that instantiates the changed class: `grep -rn 'new <ClassName>(' apps/*/src/`
2. **For each spec file**, verify the mock or test double provides the new method/field. A missing constructor arg in a test typically fails at compile-time, but a missing field in a typed mock object does not (TypeScript only warns at the call site).
3. **If the new method has a NEW SIDE EFFECT** (DB write, external SDK call, event emit), add at least ONE test that asserts the side effect fires — not just one that asserts the method returns the right value.

The recurring trap: mocking `PostHogService` with `{ capture: jest.fn() }` proves the method is called. It does NOT prove the captured event has the right `distinctId`, `groupId`, or `properties` — those are silent at the type level but visible in PostHog dashboards.

### Trace 6 — Conditional-coupling trace (GATE → EFFECTS UNDER IT)

When the diff adds a new effect (side-effect, identify call, tag set, scope change), check what conditional gates it sits under. Effects that share a gate become coupled to the gate's condition — when the condition is false, ALL gated effects skip, even if some of them have nothing to do with the condition.

For each effect (e.g. `Sentry.setTag`, `posthog.identify`, analytics call) added to a function:

1. **What gates currently wrap this effect?** `if (POSTHOG_KEY)`, `if (user)`, `if (typeof window !== 'undefined')`.
2. **Does THIS effect's required precondition match the gate's condition?** Sentry tagging needs `user` (to know who to tag) — it does NOT need `POSTHOG_KEY`. Putting it inside `if (POSTHOG_KEY)` couples Sentry tagging to PostHog being configured, which is wrong.
3. **If the gate is too restrictive**: hoist the effect out into its own `useEffect` / its own if-block with the right precondition.

The recurring trap: Sentry tenant tagging placed inside `if (NEXT_PUBLIC_POSTHOG_KEY)` — when PostHog wasn't configured, Sentry events still fired but had no tenantId tag, fingerprinting all errors as `no-tenant`.

### Trace 7 — Wrapper-lifecycle trace (WRAPPER → INNER)

When the diff wraps a Promise, Observable, async iterable, generator, EventEmitter, or any other long-running primitive, the wrapper takes on the **lifecycle responsibilities** of the inner. Skipping any of them creates a leak.

For each `new Observable(...)`, `new Promise(...)`, `async function*`, or similar:

1. **Setup**: what does the inner need to start?
2. **Teardown**: what cleanup does the inner expose? Subscription `unsubscribe`, AbortController `abort`, EventEmitter `removeListener`, async-iterator `return()`, file-descriptor close?
3. **Propagate the teardown** through the wrapper. For RxJS: the function passed to `new Observable(subscriber => {...})` must RETURN a teardown function that the wrapper invokes on unsubscribe. Failing to return one means client cancellation (HTTP/2 stream close, request timeout, `takeUntil`) does not reach the inner — emissions keep arriving at a dead subscriber.

The recurring trap: a NestJS interceptor wrapped `next.handle().subscribe(...)` inside a `new Observable(subscriber => {...})` without capturing the inner Subscription. When the client cancelled, the wrapper's teardown was a no-op, the route handler kept emitting, and the framework reported a subscriber leak.

---

## Output format

When this skill runs (manually OR invoked by a command), produce a YAML-block report:

```yaml
cross-file-reasoning:
  scope: <files in diff>
  symbols-traced:
    - name: POSTHOG_HOST
      type: env-var
      trace: producer(deploy.yml:42) → consumer(posthog.service.ts:18) → fallback(||) → empty-string-safe(YES)
      verdict: PASS
    - name: app/posthog/[...path]/route.ts
      type: route
      trace: basePath(/admin) + locale(none) + file(/posthog/[...path]) → effective(/admin/posthog/*)
      verdict: PASS
    - name: maskAllText
      type: sdk-option
      trace: posthog-js v1.376 type defs → NOT FOUND
      verdict: BLOCK — option ignored at runtime, must use maskTextSelector
  failure-mode-matches:
    - mode: framework-prefix-doubling
      file: app/admin/posthog/[...path]/route.ts
      explanation: basePath /admin + path /admin → /admin/admin/posthog. Move file or remove /admin from path.
  verdict: BLOCK   # PASS | WARN | BLOCK
```

A BLOCK verdict halts the calling command (review or implement) until the listed items are resolved.

---

## When to skip (allow-list, narrow)

You can skip this skill if the diff is:

- **Doc-only** (`*.md` files only, no code).
- **Test-only** with no new mocks or interface assumptions.
- **Comment-only** (lint passes, no behavior change).
- **Pure formatting** (Prettier, lint --fix).
- **Migration SQL** with no application-code change.

For anything else — including "tiny" changes — run the traces. The session that triggered this skill's existence shipped a 4-line file move that broke every analytics request in production. There is no "tiny" cross-file change.

---

## Failure-mode catalog

See `FAILURE_MODES.md` in this same directory. The catalog is the growing list of general-form failure modes captured from real bugs the reviewer caught after this agent missed them. Read it before running the traces — it sharpens what to look for.

When you spot a NEW failure mode in production-bound code (not yet in the catalog), append it. The format is in `FAILURE_MODES.md`'s template section.
