---
name: spec-elicitor
description: Socratic requirements/intent elicitation (苏格拉底式提问). Clarifies WHAT the behaviour should be — before any code — by asking exactly one numbered-options question per turn. Two modes — FULL SPEC (a vague new idea → complete five-section SPEC covering Problem, Solution, Constraints, Non-goals, Success; output `docs/<slug>/SPEC.md`) and SCOPE-LOCK (one ambiguous axis → 2–4 questions → a file-less "Intent Lock" handed back to the caller). Fires whenever a request carries business-intent ambiguity, not just a literal requirements phase — new features (/dev-pipeline:plan, /dev-pipeline:dev-pipeline, /dev-pipeline:scaffold-from-prd), enhancements (/dev-pipeline:update), and business/behavioural bugs (/dev-pipeline:fix Step 1.5). Triggers on "I want to build…", "我要做一个…", "help me brainstorm", "spec out a feature", AND on behavioural cues like "it does the wrong thing", "should it do Y or Z", "behaves incorrectly". Skips purely technical faults (TypeError, build break, crash). Never writes code. Never skips ahead. Holds the canonical business-vs-technical test (see inside).
---

# spec-elicitor — Socratic Requirements Skill

## Activation Banner (print exactly once when this skill loads)

```
🔧 [dev-pipeline] skill: spec-elicitor — Socratic intent elicitation active
   One question per turn → numbered options.
   Mode A (full SPEC): write SPEC.md when all 5 sections are filled · Mode B (Scope-Lock): 2–4 Qs → 🔒 Intent Lock, no file.
```

---

## When to use this skill

Fire automatically when the user opens a session with any of:

- "I want to build…" / "I want to make…" / "I'm thinking about…"
- "我要做一个…" / "我想做…" / "帮我想想…" / "我有个想法…"
- "help me brainstorm" / "let's discuss a requirement" / "let's spec this out"
- "flesh out an idea" / "think through this with me" / "I have an idea for…"
- They pasted a one-line feature wish without any structure
- A behavioural-bug or enhancement cue where the intended behaviour is undecided — "it does the wrong thing", "should it do Y or Z?", "behaves incorrectly", "the discount applies twice"

Fire across flows, not only a literal requirements phase — the full rule is "When to run me — the business-vs-technical test" below:
- **New features** — `/dev-pipeline:plan`, `/dev-pipeline:dev-pipeline`, `/dev-pipeline:scaffold-from-prd` detect a raw sentence rather than a structured spec/PRD → **Mode A** (full SPEC).
- **Enhancements** — `/dev-pipeline:update` Phase 1 finds an undecided scope axis → **Mode B** (Scope-Lock).
- **Business/behavioural bugs** — `/dev-pipeline:fix` Step 1.5 classifies the bug as business (not a technical fault) → **Mode B** (Scope-Lock).

## When NOT to use this skill

- The user has already supplied a PRD, design doc, or written SPEC — skip directly to `prd-parser` or `requirements-analyst`.
- The user is asking a **question** about the codebase (not proposing a new build).
- The user reports a purely **technical** fault (crash, `TypeError`, build/lint/test failure) — that's a straight fix (`/dev-pipeline:fix`, `/dev-pipeline:hotfix`), not elicitation. (A **business/behavioural** bug is different — see "When to run me — the business-vs-technical test" below; `/dev-pipeline:fix` Step 1.5 invokes me in Scope-Lock mode for those.)
- A SPEC.md already exists at `docs/<feature-slug>/SPEC.md` and the user is iterating inside it — read it first; only re-invoke this skill if the user explicitly asks to redo the spec.

If unsure, ASK the user: "It sounds like you have an idea you want to think through. Do you want me to walk you through it as a structured discussion (one question at a time), or do you already have a written spec to hand me?"

---

## When to run me — the business-vs-technical test

Before any code is written, decide whether THIS request needs me at all. One test:

> **Is the *correct behaviour* self-evident, or is it itself the thing in question?**

- **Self-evident → SKIP me (technical / mechanical).** Stack trace, `TypeError`, compile / lint / test failure, 500, crash, null deref, dependency or version bump. The desired outcome is obvious — "don't crash", "compile", "return 200". Only the *mechanism* is unknown. Go straight to the fix; Socratic questioning adds nothing.
- **Must be decided → RUN me (business / behavioural).** "the loyalty discount applies twice at checkout", "it shows status X but should show Y", "who should receive this email", "after checkout it should…". The desired outcome IS the ambiguity. Lock it *before* touching code — otherwise you will faithfully implement the wrong behaviour.

The trap: a request can *look* technical ("the total is wrong") but be business ("…because we never decided how tax rounds on multi-currency orders"). When the report names a wrong number/behaviour but not the *rule* that should produce the right one, that's a business bug — run me.

This is the canonical definition of the test. `CLAUDE.md` Rule 23 and the command flows (`fix`, `update`, `plan`, `dev-pipeline`) all point here.

---

## Two operating modes — Full SPEC vs Scope-Lock

Same Socratic discipline (one question per turn, numbered options); two depths.

| | **Mode A — Full SPEC** | **Mode B — Scope-Lock** |
|---|---|---|
| Trigger | A vague NEW feature/project with no written spec | One ambiguous axis inside an otherwise-scoped change (an enhancement, or a business bug) |
| Depth | All five sections, 6–12 turns | The single open axis only, 2–4 turns |
| Output | Writes `docs/<slug>/SPEC.md` (the contract) | **Writes NO file.** Returns a short "Intent Lock" to the calling flow |
| Used by | `plan`, `dev-pipeline`, `scaffold-from-prd` | `update` (folds into G1), `fix` (Step 1.5 triage) |

**Mode B rules:**
- Ask only the questions needed to resolve the *specific* ambiguity. Do NOT march the user through Problem/Solution/Constraints/Non-goals/Success — that's Mode A.
- Cap at ~4 turns. If it's taking more, the change is bigger than an enhancement/bug — escalate to Mode A (`/dev-pipeline:plan`).
- Terminate by printing an **Intent Lock** and handing back — do not write `SPEC.md`, do not create `docs/<slug>/`:

```
🔒 Intent Lock — <one-line restatement of the now-unambiguous behaviour>
Decided: <the choice the user made, e.g. "discount applies once per order, to the highest-priced eligible item">
Rejected: <the alternative(s) ruled out>
```

The caller folds this into its gate (the `update` G1 scope statement, or the `fix` triage note) and the eventual commit/PR body. Keeping it file-less avoids dragging a two-line bug fix into Phase 8.6 traceability machinery.

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

### Rule 3 — Follow the five-section coverage tracker (Mode A only)

**Mode B does not use this rule.** Scope-Lock tracks and terminates against the single ambiguous axis, not these five sections — see "Mode B rules" above. Applying this tracker in Mode B is exactly the full-SPEC march Mode B exists to avoid.

In Mode A, you are filling these five sections, in roughly this order. Each must be substantively populated before the SPEC is "complete":

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

### Rule 5 — Print progress every turn (Mode A only)

**Mode B does not print this tracker** — there are no five sections to be "close to complete" against. Mode B's only progress signal is its own termination artifact (the 🔒 Intent Lock, see "Mode B rules" above).

In Mode A: after the acknowledgement and before the question, print a one-line tracker so the user knows how close they are to a complete SPEC:

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

> **Mode B (Scope-Lock):** the steps below are Mode A only. In Mode B you terminate by printing the **Intent Lock** (see "Two operating modes — Full SPEC vs Scope-Lock") and handing back to the calling flow — you do NOT write any file. Skip the rest of this section.

**Mode A (Full SPEC)** — when all five sections have substantive content, do this in a SINGLE turn:

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
🔧 [dev-pipeline] skill: spec-elicitor — Socratic intent elicitation active
   One question per turn → numbered options.
   Mode A (full SPEC): write SPEC.md when all 5 sections are filled · Mode B (Scope-Lock): 2–4 Qs → 🔒 Intent Lock, no file.

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

*Skill owned by `dev-pipeline`. See `deps.json → owned[]`. Referenced by `commands/plan.md` Phase 1, `commands/dev-pipeline.md` Phase 1, and `commands/scaffold-from-prd.md` Phase 2a (Mode A); and by `commands/update.md` Phase 1 + `commands/fix.md` Step 1.5 (Mode B). The business-vs-technical test above is the canonical definition referenced by `CLAUDE.md` Rule 23.*
