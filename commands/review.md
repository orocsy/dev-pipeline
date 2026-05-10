---
description: Proactive local code review on the current diff BEFORE push. Runs parallel reviewer agents, surfaces findings, and blesses HEAD if clean. Mandatory before /dev-pipeline:deliver.
---

# Development Pipeline: Pre-Push Self-Review

You are reviewing your own diff BEFORE pushing. Do NOT push without blessing. Do NOT rely on Codex to catch things.
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

## STEP 2: Run Parallel Reviewers (MANDATORY)

Announce before spawning each agent:

```
🤖 [dev-pipeline] spawning: deep-reviewer — correctness, race conditions, edge cases
🤖 [dev-pipeline] spawning: typescript-reviewer — type safety audit (if .ts/.tsx in diff)
🤖 [dev-pipeline] spawning: security-reviewer — auth, env vars, SQL, user input (if applicable)
🤖 [dev-pipeline] spawning: test-reviewer — test coverage + mock completeness
🤖 [dev-pipeline] spawning: code-review-plugin — 5-agent sweep (if installed)
```

Launch these reviewers in parallel. Each gets its own context window. Do NOT run them sequentially.

**A. Deep reviewer** (always)
- Prompt: "Review this diff for correctness, race conditions, state bugs, edge cases, missing error handling. Rank each finding P1 (must fix) / P2 (should fix) / P3 (nit). Be specific: file, line, what's wrong, proposed fix."
- Input: `git diff $BASE..HEAD`

**B. TypeScript reviewer** (if `.ts` / `.tsx` in diff)
- Prompt: "Review for type safety violations: `as any`, unchecked nullable access, missing return types, incorrect generics, unsafe assertions, `@ts-ignore` without explanation."
- Input: only the TS/TSX files from the diff

**C. Security reviewer** (if diff touches auth, crypto, env vars, SQL, user input)
- Prompt: "Review for: secrets in commits, `process.env.X` without validation, SQL injection, XSS, missing authz checks, insecure defaults, unvalidated user input flowing to dangerous sinks."
- Input: the auth/env/sql-touching files

**D. Test reviewer** (if test files changed OR production code changed without test changes)
- Prompt: "Review: are the tests actually testing the behaviour change? Any `.only` / `.skip`? Mock completeness — are all interface fields present? Did production code change without matching test updates?"

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
