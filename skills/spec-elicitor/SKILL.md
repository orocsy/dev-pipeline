---
name: spec-elicitor
description: Socratic requirements elicitation. Walks the user from a vague idea ("I want to build…", "我要做一个…", "help me brainstorm", "flesh out an idea", "spec out a feature", "let's discuss a requirement") to a complete SPEC document with five sections — Problem Statement, Proposed Solution, Technical Constraints, Non-goals, Success Criteria — by asking exactly one numbered-options question per turn. Fires at the very start of /dev-pipeline:plan, /dev-pipeline:dev-pipeline, and /dev-pipeline:scaffold-from-prd whenever the user has not already supplied a written SPEC or PRD. Output is `docs/<feature-slug>/SPEC.md`. Never writes code. Never skips ahead.
---

# spec-elicitor — Socratic Requirements Skill

## Activation Banner (print exactly once when this skill loads)

```
🔧 [dev-pipeline] skill: spec-elicitor — Socratic spec elicitation active
   One question per turn → numbered options → SPEC.md when all 5 sections are filled.
```

---

## When to use this skill

Fire automatically when the user opens a session with any of:

- "I want to build…" / "I want to make…" / "I'm thinking about…"
- "我要做一个…" / "我想做…" / "帮我想想…" / "我有个想法…"
- "help me brainstorm" / "let's discuss a requirement" / "let's spec this out"
- "flesh out an idea" / "think through this with me" / "I have an idea for…"
- They pasted a one-line feature wish without any structure

Also fire when a pipeline command (`/dev-pipeline:plan`, `/dev-pipeline:dev-pipeline`, `/dev-pipeline:scaffold-from-prd`) detects that the user request is a raw sentence rather than a structured spec or PRD.

## When NOT to use this skill

- The user has already supplied a PRD, design doc, or written SPEC — skip directly to `prd-parser` or `requirements-analyst`.
- The user is asking a **question** about the codebase (not proposing a new build).
- The user explicitly asks for code or to fix a bug — those are pipeline flows (`/dev-pipeline:hotfix`, `/dev-pipeline:fix`), not elicitation.
- A SPEC.md already exists at `docs/<feature-slug>/SPEC.md` and the user is iterating inside it — read it first; only re-invoke this skill if the user explicitly asks to redo the spec.

If unsure, ASK the user: "It sounds like you have an idea you want to think through. Do you want me to walk you through it as a structured discussion (one question at a time), or do you already have a written spec to hand me?"

---

## The Protocol (NON-NEGOTIABLE)

### Rule 1 — One question per turn

Never ask more than one question per response. The whole point is to avoid overwhelming the user with a wall of clarifications. If you find yourself drafting question 2 in the same turn, stop and save it for the next turn.

### Rule 2 — Numbered options every time

Every question MUST include 2-4 numbered options the user can pick by typing a single digit. Always include a final option labelled `N. Other (please describe)` so the user can free-form when none of the options fit. Format:

```
**Q3 — What's the primary user role?**

1. End customer (booking/buying)
2. Internal staff (admin/operator)
3. Both — equal weight
4. Other (please describe)
```

If you can't think of plausible options, your question is too abstract — refine it before asking.

### Rule 3 — Follow the five-section coverage tracker

You are filling these five sections, in roughly this order. Each must be substantively populated before the SPEC is "complete":

| # | Section | What it captures | Sample probing questions |
|---|---------|------------------|--------------------------|
| 1 | **Problem Statement** (问题陈述) | Who has the problem, what is the pain, what's the cost of doing nothing | "Who experiences this problem most acutely?" "What do they do today as a workaround?" "How often does this come up?" |
| 2 | **Proposed Solution** (方案描述) | The shape of what we're building — not implementation detail, but enough to picture it | "What's the user's entry point?" "What's the happy-path output?" "Is this a new flow or an extension to an existing one?" |
| 3 | **Technical Constraints** (技术约束) | Stack, deploy target, performance/security/compliance limits, integration boundaries | "Which apps does this touch (booking / admin / api)?" "Any latency SLA?" "Multi-tenant scope?" "Locales needed?" |
| 4 | **Non-goals** (明确不做的事) | Explicit scope cuts — what would be reasonable to include but is intentionally OUT for this round | "Should we handle X in this round, or is X a follow-up?" "Mobile native — in or out?" "Bulk operations — in or out?" |
| 5 | **Success Criteria** (成功标准) | Observable, testable conditions that prove the feature works | "How will the user know it worked?" "What metric / log / test would prove it shipped correctly?" "What's the visible 'done' state for the operator?" |

Maintain a mental checklist. After every user answer, decide which section the next question should advance. Don't bounce randomly — finish what you started on a section before moving on.

### Rule 4 — Acknowledge before asking

Each turn, briefly reflect back what you understood from the prior answer ("Got it — so the pain is X and the workaround is Y."), THEN ask the next question. This catches mishearings early and shows the user you're listening.

### Rule 5 — Print progress every turn

After the acknowledgement and before the question, print a one-line tracker so the user knows how close they are to a complete SPEC:

```
📋 SPEC progress: [✓ Problem] [✓ Solution] [◐ Constraints] [ ] Non-goals [ ] Success
```

Use `✓` for "done", `◐` for "in progress", `[ ]` for "not yet started".

### Rule 6 — Never write code, never name files, never propose architecture

This skill is the THINK phase. No implementation choices. No file paths. No "we'll use Prisma for X." That belongs to `technical-architect` later in the pipeline. If the user pushes for it, redirect: "Hold that — we'll get to architecture once the SPEC is locked. For now, what's the success criterion?"

### Rule 7 — Detect the natural language and mirror it

If the user is writing in Chinese, respond in Chinese. If in English, respond in English. If mixed, match the dominant language. Section labels in the final SPEC always include BOTH the English and the Chinese name (per the template below) regardless of which language the conversation used.

### Rule 8 — Don't drag it out

Target: 6–12 turns total for a typical feature. If you hit 15+ turns without closing a section, you're over-elaborating — summarize what you have and ask the user "is this enough detail for section X, or do you want to keep digging?"

---

## Termination & Output

When all five sections have substantive content, do this in a SINGLE turn:

### Step 1 — Confirm

Print a draft of the SPEC inline and ask:

```
We've covered all five sections. Here's the draft SPEC:

[full SPEC content]

Type:
1. Approve — write to docs/<slug>/SPEC.md and proceed
2. Tweak — tell me what to change
3. Add more — there's a corner we haven't covered

Which?
```

### Step 2 — On approval, write the file

Slug rule: kebab-case of the feature name the user used most consistently. If unclear, ask: "What should we call this feature in one short phrase (will become the folder name)?"

Path: `docs/<slug>/SPEC.md` relative to the project root (NOT the plugin repo — always the user's project).

If `docs/` does not exist, create it. If `docs/<slug>/SPEC.md` already exists, ASK the user before overwriting; offer `SPEC-v2.md` as an alternative.

### Step 3 — Hand off

After writing, print exactly this (substituting the slug and project context):

```
✓ SPEC written to docs/<slug>/SPEC.md

Next steps:
• For an existing project — run `/dev-pipeline:plan` to design the architecture and break into MIUs.
• For a brand-new project — run `/dev-pipeline:scaffold-from-prd docs/<slug>/SPEC.md`.

The SPEC is the contract. Subsequent phases will trace every MIU back to a line in this file.
```

Then stop. Do NOT auto-invoke the next command — let the user choose.

---

## SPEC Template

Write this exact structure to `docs/<slug>/SPEC.md`:

```markdown
# <Feature Name> — SPEC

> Authored via `dev-pipeline:spec-elicitor` on <YYYY-MM-DD>.
> This is the contract for downstream phases. Every MIU must trace to a line below.

## 1. Problem Statement (问题陈述)

<2–5 sentences. Who has the problem, what is the pain, what is the cost of doing nothing.>

## 2. Proposed Solution (方案描述)

<2–6 sentences. Shape of what we're building — entry point, happy path, output. NOT implementation.>

## 3. Technical Constraints (技术约束)

- **Apps touched**: <booking / admin / api / packages>
- **Stack constraints**: <stay within current stack? any new dependencies?>
- **Performance**: <latency / throughput targets, if any>
- **Multi-tenancy**: <how tenant scoping applies>
- **Locales**: <en / zh-HK / both>
- **Compliance / security**: <PII handling, auth requirements, etc.>
- **Integration boundaries**: <external APIs, webhooks, etc.>

## 4. Non-goals (明确不做的事)

- <Thing 1 that is intentionally OUT of scope for this round, with one-line rationale>
- <Thing 2>
- <Thing 3>

## 5. Success Criteria (成功标准)

- [ ] <Observable, testable condition 1>
- [ ] <Observable, testable condition 2>
- [ ] <Observable, testable condition 3>

---

## Elicitation Trace

<Bulleted summary of the Q&A turns, for future readers who want to know how this SPEC was reached. Each bullet: "Asked X → user chose Y → captured in section Z.">
```

---

## Anti-patterns (do NOT do these)

- ❌ Asking three questions in one turn ("What's the user role, what's the success metric, and what's the latency budget?")
- ❌ Asking open-ended questions without numbered options ("Tell me more about the user.")
- ❌ Jumping to implementation ("So we'd add a `Waitlist` table with…")
- ❌ Skipping the acknowledgement and just firing the next question
- ❌ Letting the conversation sprawl past 15 turns without summarizing
- ❌ Writing the SPEC before the user explicitly approves the draft
- ❌ Forgetting to print the progress tracker each turn
- ❌ Auto-invoking `/dev-pipeline:plan` after writing the SPEC — the user picks the next step

---

## Worked example (truncated for brevity)

User: "我要做一个让客户在等位列表里自动收到位置开放通知的功能"

Assistant (turn 1 — banner + acknowledge + first question on Problem):

```
🔧 [dev-pipeline] skill: spec-elicitor — Socratic spec elicitation active
   One question per turn → numbered options → SPEC.md when all 5 sections are filled.

明白了 — 你想做的是等位列表的自动通知功能。先从「问题」开始。

📋 SPEC progress: [◐ Problem] [ ] Solution [ ] Constraints [ ] Non-goals [ ] Success

**Q1 — 这个痛点最直接影响谁?**

1. 排队的客户 — 他们不知道什么时候轮到自己,只能反复打电话或刷网页
2. 店里的员工 — 每次空位出来都要手动打电话通知,占用时间
3. 两者都有,但客户更明显
4. Other (please describe)
```

User: "2"

Assistant (turn 2 — acknowledge + drill into Problem):

```
好 — 所以痛点是员工的人工成本,通知是手动的、容易漏掉。

📋 SPEC progress: [◐ Problem] [ ] Solution [ ] Constraints [ ] Non-goals [ ] Success

**Q2 — 目前店里平均每天有多少这种「打电话通知等位客户」的动作?**

1. 0–2 次(偶尔)
2. 3–10 次(每天都有)
3. 10+ 次(高频,占员工大量时间)
4. Other (please describe)
```

…and so on through the five sections. Typical close in 6–12 turns.

---

*Skill owned by `dev-pipeline`. See `deps.json → owned[]`. Referenced by `commands/plan.md` Phase 1, `commands/dev-pipeline.md` Phase 1, and `commands/scaffold-from-prd.md` Phase 2.*
