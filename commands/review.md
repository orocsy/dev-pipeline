---
description: Proactive local code review on the current diff BEFORE push. Runs parallel reviewer agents, surfaces findings, and blesses HEAD if clean. Mandatory before /dev-pipeline:deliver.
---

# Development Pipeline: Pre-Push Self-Review

You are reviewing your own diff BEFORE pushing. Do NOT push without blessing. Do NOT rely on an async review bot to catch things.
All steps are pre-approved. Run to completion.

This command is the **blessing gate**: it writes `.claude/.last-reviewed-sha` on success. The pre-push hook refuses any push whose HEAD SHA does not match the blessed SHA.

---

## STEP 1: Capture the Diff

```bash
BASE="${1:-$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD~1)}"
HEAD_SHA="$(git rev-parse HEAD)"
DIFF_STATS="$(git diff --stat "$BASE"..HEAD)"
FILES_CHANGED="$(git diff --name-only "$BASE"..HEAD)"

echo "Reviewing $BASE..HEAD ($HEAD_SHA)"
echo "$DIFF_STATS"
```

If the diff touches zero files, abort: "Nothing to review."
If the diff is >50 files, split into clusters by directory and review in parallel batches.

---

## STEP 1.5: Load Production-Defensive-Patterns Skill (MANDATORY)

Before spawning reviewers, load the `engineering-craft` skill index. This skill is distilled from real post-merge incidents — every rule cites a historical SHA — and is the single highest-leverage filter to run BEFORE the parallel reviewers.

Detect which categories the diff touches by grep:

```bash
# Concurrency / CAS triggers
git diff "$BASE"..HEAD | grep -E "findUnique|findFirst|update.*WHERE|consumedAt|tokenVersion|client\.(get|set|del|eval)|requestPasswordReset|resetPassword|otp|jti|consume" | head -5

# Enumeration safety triggers
git diff "$BASE"..HEAD | grep -E "@HttpCode\(204\)|forgot-password|equalizeBcrypt|findFirst.*email|@Post.*forgot" | head -5

# Config drift triggers
git diff "$BASE"..HEAD --name-only | grep -E "env\.schema|deploy\.yml|\.env\.example|envSchema" | head -5

# Silent no-op integration triggers
git diff "$BASE"..HEAD | grep -E "RESEND_API_KEY|TWILIO|STRIPE_SECRET|isConfigured\(\)|new Resend\(|sendEmail" | head -5

# Grep-for-siblings triggers (security literal removal)
git diff "$BASE"..HEAD | grep -E "^-.*'(dev-secret|change-in-production|local-|TODO-set)" | head -5
```

For each category that fires:

1. Load the matching `~/.claude/skills/engineering-craft/categories/<class>/README.md` into context.
2. Use that category's rule list and templates as the FRAME for the reviewer prompts in STEP 2 (specifically — the reviewer's `Look for:` clause must include this category's anti-patterns).

Always run the [pre-merge-self-review.md](file:///Users/SeanCai/.claude/skills/engineering-craft/checklists/pre-merge-self-review.md) checklist mentally, ticking each box that applies to the diff. Any unticked box on a triggered category → block with severity P1 even if no other reviewer flags it.

Skipping STEP 1.5 means reviewers operate without the project's own incident-derived priors. PR#85 cost 5 review rounds because this step didn't exist.

### STEP 1.5b: Emit knowledge-references sidecar

For each engineering-craft rule the reviewer agents will be primed with, record it. After STEP 5 (bless or block), write:

```bash
mkdir -p .claude
cat > ".claude/knowledge-refs-${HEAD_SHA:0:7}.json" <<JSON
{
  "sha": "${HEAD_SHA}",
  "ts": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "knowledgeReferences": [
    { "id": "concurrency-cas/state-machine-first",  "category": "concurrency-cas",   "usedIn": "STEP 2 reviewer-prompt prior" },
    { "id": "enumeration-safety/timing-oracle",     "category": "enumeration-safety","usedIn": "STEP 2 reviewer-prompt prior" }
  ]
}
JSON
```

Add one object per category-rule loaded into the reviewer prompts. Keep it valid JSON — no trailing comma after the last element, and **no comments inside the heredoc** (the file is machine-read; `//` makes it un-parseable).

The IDs are `<category>/<rule-slug>` matching `~/.claude/skills/engineering-craft/categories/<category>/rules/<slug>.md`.

This sidecar is **reserved** for a future decay loop in `/dev-pipeline:consolidate-lessons` that would bump each referenced rule's `last-referenced` field (proven 365d / verified 180d → demote). **That consumer is not yet implemented** — consolidate-lessons does not read these files today. Emit them anyway so the history exists when the loop is built; until then they are a write-only audit trail, not an active feedback loop.

If no engineering-craft rules were loaded (diff didn't trigger any category), still emit the sidecar with an empty `knowledgeReferences` array — that's the signal that STEP 1.5 ran.

---

## STEP 2: Run Parallel Reviewers (MANDATORY)

Announce before spawning each agent:

```
🤖 [dev-pipeline] spawning: assumption-checker — diff-vs-docs drift audit + cross-file backward-trace
🤖 [dev-pipeline] spawning: cross-file-reviewer — consumer/producer/lifecycle traces (load cross-file-reasoning skill first)
🤖 [dev-pipeline] spawning: deep-reviewer — correctness, race conditions, edge cases
🤖 [dev-pipeline] spawning: typescript-reviewer — type safety audit (if .ts/.tsx in diff)
🤖 [dev-pipeline] spawning: security-reviewer — auth, env vars, SQL, user input (if applicable)
🤖 [dev-pipeline] spawning: test-reviewer — test coverage + mock completeness
🤖 [dev-pipeline] spawning: code-review-plugin — 5-agent sweep (if installed)
```

Launch these reviewers in parallel. Each gets its own context window. Do NOT run them sequentially.

**A0. Assumption checker** (always — runs first, cheapest gate)
- Prompt: "Audit this diff for silent assumption drift — URL topology, env-var contracts, multi-tenancy invariants, data-model contracts. Cross-check against README, project CLAUDE.md, .claude/docs/ARCHITECTURE.md, .claude/docs/URL_TOPOLOGY.md (if present), docs/architecture-*.md, prisma/schema.prisma comments. ALSO run the cross-file backward traces (steps 8–14) per agents/assumption-checker.md → Method. Output: PASS / WARN / BLOCK with findings."
- Input: `git diff $BASE..HEAD` + the doc files above
- Severity escalation: a BLOCK from this agent fails the review even if deep/typescript/security all pass. Better to catch wrong-URL or dropped-tenant-filter drift here than at the user's "wait, this targets the wrong URL" five turns later.

**A0.5. Cross-file reviewer** (always — runs in parallel with A0; the cross-file-aware twin of the deep reviewer)
- Prompt: "Load `skills/cross-file-reasoning/SKILL.md` and `skills/cross-file-reasoning/FAILURE_MODES.md` first. Then walk this diff and run the seven cross-file traces (env-var, route/URL, SDK option, event lifecycle, mock completeness, conditional coupling, wrapper lifecycle) on every NEW or CHANGED symbol. For each symbol, produce the YAML output format the skill defines. Match the diff against FAILURE_MODES.md — if any entry matches, flag with the entry number and the specific anti-pattern. Output: PASS / WARN / BLOCK with the YAML report. Be brutal: cross-file bugs ship because the implementing agent never opened the consumer file."
- Input: `git diff $BASE..HEAD` + the consumer files surfaced by each trace + relevant config (`next.config.js`, `vercel.json`, `.github/workflows/*.yml`, `node_modules/<sdk>/dist/*.d.ts` excerpts for option-name verification)
- Severity escalation: same as A0 — a BLOCK from this reviewer fails the review even if everything else passes. The whole point of this reviewer is to mechanically detect the failure modes the deep/typescript/security reviewers historically MISS because they each look at the diff through one lens.

**A. Deep reviewer** (always)
- Prompt: "Review this diff for correctness, race conditions, state bugs, edge cases, missing error handling. **Cross-file lens — mandatory**: for every NEW symbol the diff introduces (env var, route file, SDK option, event, exported function), do not stop at the file where it's declared. `grep` for consumers. State the consumer file/line in your finding. If a NEW value flows to a consumer the diff doesn't touch, treat that as a candidate for review even if it 'looks fine in this file'. Reference `skills/cross-file-reasoning/FAILURE_MODES.md` for general patterns. Rank each finding P1 (must fix) / P2 (should fix) / P3 (nit). Be specific: file, line, what's wrong, proposed fix."
- Input: `git diff $BASE..HEAD`

**B. TypeScript reviewer** (if `.ts` / `.tsx` in diff)
- Prompt: "Review for type safety violations: `as any`, unchecked nullable access, missing return types, incorrect generics, unsafe assertions, `@ts-ignore` without explanation. **Cross-file lens**: for any `Partial<X>` / `as unknown as X` / mock-casting in tests, verify the mock provides every method/field the real interface declares — call out drift between mock shape and real shape."
- Input: only the TS/TSX files from the diff

**C. Security reviewer** (if diff touches auth, crypto, env vars, SQL, user input)
- Prompt: "Review for: secrets in commits, `process.env.X` without validation, SQL injection, XSS, missing authz checks, insecure defaults, unvalidated user input flowing to dangerous sinks. **Cross-file lens**: for every `process.env.X` introduced, trace producer (deploy.yml secret / vercel env / docker-compose) → consumer (use site) → fallback semantics (`??` vs `||`, empty-string behavior). An env var used without a producer entry is a deployment-time bug waiting to happen."
- Input: the auth/env/sql-touching files

**D. Test reviewer** (if test files changed OR production code changed without test changes)
- Prompt: "Review: are the tests actually testing the behaviour change? Any `.only` / `.skip`? Mock completeness — are all interface fields present? Did production code change without matching test updates? **Cross-file lens**: if production code added a new method / new constructor arg / new side effect, verify every spec that instantiates the class provides it. Look for `services-page.test.tsx`-style tautologies (test rewritten to match new behavior — see FAILURE_MODES.md #10)."

**E. Delegate to installed `/code-review`** (the 5-agent plugin)
If the `/code-review` slash command is installed (from the `code-review` plugin), invoke it in parallel with A–D. It runs its own 5-agent sweep (CLAUDE.md compliance, bug scan, git history, prior PR comments, inline comments) with a 0–100 score.

```bash
# Signal that /code-review should be dispatched for this SHA
echo "$HEAD_SHA" > .claude/.review-in-flight
```

---

## STEP 3: Aggregate Findings

Collect ALL findings from reviewers A–E into a single table:

| # | Severity | File:Line | Reviewer | Issue | Proposed Fix |
|---|----------|-----------|----------|-------|--------------|
| 1 | P1 | src/api/users.ts:42 | deep | A→B→A race on user.status | Use atomic update, not read-modify-write |
| 2 | P2 | src/ui/Button.tsx:18 | ts | `onClick?: any` | Type as `MouseEventHandler<HTMLButtonElement>` |
| … | … | … | … | … | … |

Dedupe identical findings from multiple reviewers (keep the most specific one).

Save to `.claude/review-findings-${HEAD_SHA:0:7}.md` for audit trail.

---

## STEP 4: Gate Decision

Count P1 and P2 findings:

```bash
P1_COUNT=$(grep -c '^| [0-9]* | P1 ' .claude/review-findings-*.md | head -1 || echo 0)
P2_COUNT=$(grep -c '^| [0-9]* | P2 ' .claude/review-findings-*.md | head -1 || echo 0)
```

**Gate rules:**
- ANY P1 finding → BLOCK. Do NOT bless. Print findings, invoke `/dev-pipeline:fix` automatically to address them, then re-run this review.
- 4+ P2 findings → BLOCK. Same flow.
- ≤3 P2 and 0 P1 → PROCEED with warning. User must ACK before blessing.
- 0 P1, 0 P2 → bless immediately.

---

## STEP 5: Bless (on pass) OR Fix-and-Retry (on block)

**On PASS:**
```bash
mkdir -p .claude
echo "$HEAD_SHA" > .claude/.last-reviewed-sha
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .claude/.last-reviewed-at
rm -f .claude/.review-in-flight
```

Report:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ REVIEW PASSED — HEAD blessed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SHA:      [HEAD sha]
Files:    [N]
Findings: 0 P1, [N] P2, [N] P3
Blessed:  .claude/.last-reviewed-sha
Next:     git push   OR   /dev-pipeline:deliver
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**On BLOCK:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛑 REVIEW BLOCKED — HEAD NOT blessed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
P1 findings: [N]  (all must be fixed)
P2 findings: [N]
Findings file: .claude/review-findings-[sha].md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Running /dev-pipeline:fix to address P1 findings…
```

Automatically invoke `/dev-pipeline:fix` with the findings file as context, then re-run `/dev-pipeline:review` on the new HEAD.

---

## STEP 6: Audit Trail

Append one line to `.claude/agent-events.jsonl`:
```json
{"event":"review.complete","sha":"[head]","p1":0,"p2":0,"p3":2,"blessed":true,"ts":"[iso]"}
```

---

## Emergency Override (for true incidents only)

```bash
DEV_PIPELINE_SKIP_REVIEW=1 git push origin [branch]
```

Every override is logged to `.claude/.review-overrides.log` by the pre-push hook. After an override, a retroactive review MUST be run in the same session.
