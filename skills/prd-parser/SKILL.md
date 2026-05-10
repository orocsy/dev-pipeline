---
name: prd-parser
description: Translate a product requirements document (PRD, spec, design brief, idea brief — any reasonable shape) into a structured `project-spec.json` that the bootstrap subsystem can consume. Use for the `/dev-pipeline:bootstrap-from-prd` flow's Phase B0, or when a project's requirements need to be re-parsed after the PRD evolves.
---

# PRD Parser

Translate human-written project requirements into a strict `ProjectSpec` JSON object that drives the rest of the bootstrap subsystem (stack-decider, integration-applier, codegen).

## When to use this skill

- `/dev-pipeline:bootstrap-from-prd` invokes you at Phase B0
- User asks "parse my PRD into a spec"
- A PRD evolves and the project needs `/dev-pipeline:sync-spec` — you re-parse to produce the new authoritative spec

## When NOT to use this skill

- Just chatting about a PRD (no structured output needed)
- Translating between spec versions (use the spec-migration skill instead)
- Doing the stack decision itself (that's the `stack-decider` agent's job — you only produce the input)

---

## Input contract

You accept any of these shapes:

| Shape | Examples |
|-------|----------|
| Long Notion/Markdown PRD | Sections like *Goals*, *Users*, *Features*, *Constraints* |
| Bullet list | `- multi-tenant booking SaaS / - auth / - payments / - email` |
| Free-form spec narrative | "We need a platform for X to do Y, in Hong Kong, supporting EN+zh-HK..." |
| Image of a whiteboard / Figma | Caption-driven extraction |
| A `prd.md` already partially structured | Just normalize and fill gaps |

The user provides a path or pastes content. You always produce the same output shape.

---

## Output contract

Strict `project-spec.json` matching `bootstrap/layer1/schemas.ts:ProjectSpec`. Validate before returning. If validation fails, return the validation errors and abort — do NOT silently fix.

Minimum-viable example:

```json
{
  "meta": {
    "name": "luxebook",
    "description": "Multi-tenant booking SaaS for nail salons in Hong Kong",
    "version": "0.0.1",
    "spec_schema_version": 1
  },
  "data_model": [
    {
      "name": "Tenant",
      "fields": [
        { "name": "id", "type": "string", "unique": true },
        { "name": "name", "type": "string" },
        { "name": "createdAt", "type": "datetime" }
      ]
    },
    {
      "name": "Customer",
      "fields": [
        { "name": "id", "type": "string", "unique": true },
        { "name": "tenantId", "type": "relation", "references": "Tenant" },
        { "name": "phone", "type": "string", "unique": true }
      ]
    }
  ],
  "features": [
    {
      "id": "F1",
      "title": "Customer books a service online",
      "user_role": "customer",
      "done_when": [
        "Customer can browse a tenant's services",
        "Customer picks a slot and submits booking",
        "Confirmation email is sent",
        "Booking visible in admin calendar"
      ],
      "needs": ["scheduling", "auth-customer", "email"]
    }
  ],
  "integrations": [
    { "name": "postgres-neon-prisma", "category": "database" },
    { "name": "clerk", "category": "auth" },
    { "name": "stripe", "category": "payments" },
    { "name": "resend", "category": "email" },
    { "name": "sentry", "category": "observability" },
    { "name": "google-analytics", "category": "observability" }
  ],
  "deploy": { "target": "vercel" },
  "non_functional": {
    "multi_tenant": true,
    "i18n": ["en", "zh-HK"],
    "scale_target": "10-100 tenants, ~10k bookings/month"
  }
}
```

---

## Heuristics — how to map PRD signals to spec fields

### Keyword → integration mapping (non-exhaustive)

| Signal in PRD | Integration suggestion | Confidence |
|---------------|------------------------|------------|
| "subscription", "billing", "checkout", "payment", "pricing tier" | `stripe` | High |
| "login", "user account", "sign up", "sign in" | `clerk` (default) — lower to `nextauth` if PRD says "self-host" or "OSS auth" | High |
| "multi-role", "admin can", "staff", "two types of users" | `clerk` (multi-role first-class) | High |
| "email confirmation", "notify", "send a link" | `resend` | High |
| "image upload", "photo", "user uploads", "media gallery" | `r2-cloudflare` | High |
| "real-time", "live", "presence", "websocket", "chat" | `pusher` or `ably` (defer to stack-decider for choice) | Medium |
| "search", "find", "filter products" | `meilisearch` | Medium |
| "background", "worker", "queue", "scheduled job" | `inngest` | High |
| "rate limit", "abuse prevention", "throttle" | `upstash-redis` + ratelimit | High |
| "feature flag", "rollout", "A/B test" | `vercel-edge-config` | High |
| "AI", "chatbot", "summarize", "generate", "agent", "assistant" | `ai-sdk` + `gemini-flash` (default) | High |
| "Hong Kong", "Asia", "中文", "bilingual", "multilingual" | `i18n: ['en', 'zh-HK']` (or per region) | High |
| "multi-tenant", "platform for X to Y", "white-label" | `non_functional.multi_tenant: true` | High |

Always:
- `postgres-neon-prisma` (database) is the default unless PRD says NoSQL
- `sentry` (errors) is always added
- `google-analytics` is always added unless PRD says "no third-party analytics" or "privacy-strict"

### Data model extraction

For each noun the PRD treats as a first-class entity (Customer, Booking, Service, Tenant, Order, Product, etc.):
1. Create an `EntitySpec`
2. Always add `id` (string, unique) and `createdAt` (datetime)
3. Add fields the PRD mentions (e.g. "customer has phone, email, name")
4. Add `tenantId` relation if `multi_tenant: true`
5. Don't over-extract — better to leave it incomplete than invent fields

If the PRD mentions relations between entities ("a customer makes many bookings"), encode as `type: "relation"`.

### Features extraction

One `FeatureSpec` per user-visible deliverable. Each feature must have:
- A unique `id` (`F1`, `F2`, …)
- A short `title`
- The `user_role` who uses it
- At least one `done_when` criterion (used by `verify-traceability` later)

If the PRD lists "must have" / "should have", treat must-haves as features and should-haves as a `roadmap.md` (not in the spec).

### Non-functional extraction

| PRD says | Spec field |
|----------|-----------|
| "Hong Kong", "for the HK market" | `i18n: ['en', 'zh-HK']`, `region: 'asia-east1'` |
| "GDPR", "privacy-first", "EU users" | `data_sensitivity: 'PII-GDPR'` |
| "10k users, 100k bookings/month" | `scale_target` |
| "multi-tenant", "many salons" | `multi_tenant: true` |

---

## Uncertainty handling

You **must not** invent confident answers when the PRD doesn't say. For each ambiguous field:

1. Set the field to `null` (or omit it for optional fields)
2. Add an entry to a `_clarifications` array in the output:

```json
"_clarifications": [
  {
    "field": "integrations.payments",
    "ambiguity": "PRD mentions 'paid bookings' but doesn't specify recurring vs one-time",
    "options": ["stripe-checkout-onetime", "stripe-checkout-subscription"],
    "default_if_no_answer": "stripe-checkout-onetime"
  }
]
```

The orchestrator surfaces these as a single batched clarifying question to the user before proceeding to G0.

**Never silently default.** Either be confident or surface the ambiguity.

---

## Output validation

Before returning:
1. Validate against `ProjectSpec` Zod schema
2. Check feature IDs are sequential and unique
3. Check entity references in `data_model[*].fields[*].references` resolve to actual entities
4. Check declared integrations exist in the registry (`bootstrap/integrations/<name>/manifest.json`)

If validation fails, return:

```json
{
  "ok": false,
  "errors": [
    { "path": "data_model[2].fields[0].references", "message": "References 'Order' but no entity named 'Order' exists" }
  ]
}
```

The orchestrator decides whether to ask the user or abort.

---

## Anti-patterns (don't do these)

- **Don't use a regex to find features.** This is an LLM-judgment task; use semantic understanding.
- **Don't fabricate entities the PRD doesn't mention** to be "complete." Underspecified is fine; the user adds detail later.
- **Don't pick integrations the user didn't ask for.** If they don't mention email, don't add Resend "just in case."
- **Don't translate PRD prose into the description fields.** Keep descriptions short — full prose stays in the original PRD which gets committed alongside.
- **Don't decide deploy targets.** That's the `stack-decider` agent's job. You only forward `deploy_target_hint` if the PRD explicitly mentions one.

---

## Reference: where the output goes

The orchestrator (Layer 3) calls you, validates the output, and writes it to `project-spec.json` at the project root. Then the `stack-decider` agent reads it. You have one job; do it well.

---

## Test fixtures

Test PRDs live at `bootstrap/skills/prd-parser/fixtures/`:

| Fixture | What it tests |
|---------|--------------|
| `dental-clinic.md` | Long-form PRD, multi-role, payments, calendar |
| `bullet-list-saas.md` | Minimum signal — 8 bullet points |
| `image-of-whiteboard.png` | Image-only input |
| `prd-with-conflicts.md` | Has conflicting requirements; should surface clarifications |
| `prd-without-data-model.md` | Features only; should produce features without entities |

Each fixture has a paired `*.expected.json` — golden file for the parser's output. CI runs your output diff against the goldens.

---

*Status: skill definition complete. The actual orchestration logic that calls this skill lives at `bootstrap/layer3/orchestrator.ts` (not yet built — Day 1 of §26/§30).*
