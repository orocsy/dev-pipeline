---
description: System health diagnostic — TypeScript errors, lint, test pass rate, dep freshness, CI status, living docs staleness. Green/red report.
---

# Development Pipeline: Health Check

You are diagnosing the project's overall health. Report everything. Fix nothing unless explicitly asked.
All checks are pre-approved. Run to completion.

---

## CHECK 1: TypeScript

```bash
npx tsc --noEmit 2>&1 | tail -30
```
- 0 errors → 🟢
- 1–5 errors → 🟡
- 6+ errors → 🔴

---

## CHECK 2: Lint

```bash
npx eslint . --quiet 2>&1 | tail -20
```
- 0 errors → 🟢
- Warnings only → 🟡
- Errors → 🔴

---

## CHECK 3: Tests

```bash
npm test -- --passWithNoTests 2>&1 | tail -20
```
- All pass → 🟢
- Skipped/pending → 🟡
- Failures → 🔴

---

## CHECK 4: Build

```bash
npm run build 2>&1 | tail -10
```
- Success → 🟢
- Warnings → 🟡
- Failure → 🔴

---

## CHECK 5: Dependency Freshness

```bash
npx npm-check-updates --doctor 2>/dev/null | head -30 || \
npx npm-check 2>/dev/null | head -30 || \
npm outdated 2>/dev/null | head -20 || true
```
- All current → 🟢
- Minor/patch updates → 🟡
- Major updates or vulnerabilities → 🔴

```bash
npm audit --audit-level=high 2>&1 | tail -10
```

---

## CHECK 6: CI Status

```bash
gh run list --branch main --limit 5 --json status,conclusion,name \
  --jq '.[] | "\(.status) \(.conclusion) \(.name)"' 2>/dev/null || true
```
- All passing → 🟢
- In progress → 🟡
- Failed → 🔴

---

## CHECK 7: Living Documents Freshness

```bash
for doc in .claude/docs/PROJECT_STATUS.md .claude/docs/ARCHITECTURE.md .claude/docs/RECENT_CHANGES.md; do
  if [[ -f "$doc" ]]; then
    age=$(( ($(date +%s) - $(stat -c %Y "$doc" 2>/dev/null || stat -f %m "$doc" 2>/dev/null || echo 0)) / 3600 ))
    echo "$doc: ${age}h old"
  else
    echo "$doc: MISSING"
  fi
done
```
- <24h → 🟢
- 1–7 days → 🟡
- >7 days or missing → 🔴 (run `/dev-pipeline:sync`)

---

## CHECK 8: Git Hygiene

```bash
git status --short | wc -l   # uncommitted changes
git stash list | wc -l       # stashed work
git log --oneline origin/main..HEAD | wc -l  # unpushed commits
```

---

## REPORT

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🏥 HEALTH REPORT: [project]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TypeScript:   🟢/🟡/🔴
Lint:         🟢/🟡/🔴
Tests:        🟢/🟡/🔴
Build:        🟢/🟡/🔴
Deps:         🟢/🟡/🔴
CI:           🟢/🟡/🔴
Living Docs:  🟢/🟡/🔴
Git:          🟢/🟡/🔴

🔴 Action required:
  [list]
🟡 Recommended:
  [list]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Do not start fixing anything. Present the report and wait for instruction.
