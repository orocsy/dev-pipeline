---
description: Commit, push, PR, code review, and smart auto-deploy to detected platforms
---

# Development Pipeline: Deliver Phase

You are shipping completed implementation work — commit, push, PR, review, then auto-deploy.
All steps are pre-approved. Do not ask for permission. Run to completion.

---

## PHASE 9: Commit & PR

Stage only files related to this feature (never `git add -A`):

1. Run `git status` to list all changed files
2. Stage only relevant files — exclude unrelated changes, env files, credentials
3. Delegate to `/commit-push-pr` to:
   - Create a well-formatted conventional commit (feat/fix/chore)
   - Push to remote branch
   - Create a pull request with auto-generated description

---

## PHASE 10: Code Review

Delegate to `/code-review` to review the PR.

- If **clean** → auto-merge: `gh pr merge --squash --auto`
- If **issues found** → run `/dev-pipeline:fix` automatically, then re-review
- Do NOT ask the user. Fix and merge autonomously.

---

## PHASE 11: Monitor Merge & CI

After merge to main:
```bash
sleep 3
RUN_ID=$(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID" --exit-status
```

If CI fails → alert user with link: "❌ CI failed: gh run view $RUN_ID"
If CI passes → proceed to Phase 12.

---

## PHASE 12: Smart Deploy

Run `/dev-pipeline:deploy` — it reads `.claude/project-context.json` and:
- Skips deploy if project is DESKTOP, MOBILE, or LIBRARY
- Runs all configured platform adapters (Vercel, Railway, Supabase, Fly, AWS, CloudBase)
- Creates any missing config files before deploying
- Smoke tests each deployment
- Prints final summary with URLs

---

## FINAL OUTPUT

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ SHIPPED: [feature name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PR:     https://github.com/.../pull/N
CI:     ✅ passed
Deploy: ✅ [platform URLs]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Update `task_plan.md` with all phases complete.
