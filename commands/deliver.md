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

## PHASE 9.5: Conflict Gate (MANDATORY — automatic, never skipped)

Immediately after PR creation, BEFORE handing off to review/CI/codex, check whether the PR has merge conflicts with the base branch. A `CONFLICTING` PR cannot be merged AND no review automation will fire on it (codex / CodeRabbit / GitHub branch protection won't comment on a PR that can't merge). Leaving a conflicting PR sitting "waiting for review" is dead time.

```bash
PR_NUM="$(gh pr view --json number --jq '.number')"

# GitHub computes mergeability asynchronously; poll briefly.
for i in 1 2 3 4 5; do
  STATE="$(gh pr view "$PR_NUM" --json mergeable,mergeStateStatus --jq '"\(.mergeable)|\(.mergeStateStatus)"')"
  case "$STATE" in
    UNKNOWN*) sleep 5 ;;
    *) break ;;
  esac
done

case "$STATE" in
  MERGEABLE*|*UNSTABLE)
    echo "✅ PR $PR_NUM mergeable (state: $STATE) — proceeding to review."
    ;;
  CONFLICTING*|*DIRTY)
    echo "🛑 PR $PR_NUM has conflicts ($STATE) — resolving before review."
    BASE="$(gh pr view "$PR_NUM" --json baseRefName --jq '.baseRefName')"

    # Snapshot uncommitted work, fetch, rebase. Rebase (not merge) keeps history
    # clean; force-with-lease prevents clobbering remote work we don't know about.
    git stash --include-untracked 2>/dev/null || true
    git fetch origin "$BASE" --quiet
    if ! git rebase "origin/$BASE"; then
      # Resolution loop: for each conflicted file, the agent reads both versions,
      # decides which combines correctly, edits, `git add`, `git rebase --continue`.
      echo "⚠️  Rebase has conflicts to resolve manually. Conflicted files:"
      git diff --name-only --diff-filter=U
      echo ""
      echo "Resolution policy:"
      echo "  1. Read BOTH sides of each conflict before editing."
      echo "  2. Prefer COMBINING (both sides' new functionality where compatible)"
      echo "     over choosing one side."
      echo "  3. After each file: \`git add <file>\` then \`git rebase --continue\`."
      echo "  4. After ALL files resolved: run lint + type-check + tests for"
      echo "     EACH affected app before force-push (catch resolution bugs)."
      # Hand the prompt back to the implementing agent — it has the diff context.
      exit 1
    fi

    # Re-run validation on rebased branch (the linter/type-checker may surface
    # bugs the conflict resolution introduced even if file-level resolution
    # looked clean).
    bash "$PLUGIN_ROOT/tools/refresh-deps.sh" >/dev/null 2>&1 || true
    # validate.md will re-run lint+tsc+tests at Phase 10's gate; skipping here
    # to avoid double-work.

    # Force-push with --force-with-lease (rejects if remote has new commits we
    # didn't see, preventing accidental clobber).
    git push --force-with-lease 2>&1 | tail -3

    # Confirm PR is now mergeable.
    sleep 3
    POST_STATE="$(gh pr view "$PR_NUM" --json mergeable --jq '.mergeable')"
    [[ "$POST_STATE" == "MERGEABLE" ]] || {
      echo "🛑 PR still not MERGEABLE after rebase ($POST_STATE) — escalate to user."
      exit 1
    }
    echo "✅ PR $PR_NUM now MERGEABLE after conflict resolution."
    ;;
  *)
    echo "🛑 PR $PR_NUM in unexpected state ($STATE) — pausing for human triage."
    exit 1
    ;;
esac
```

**Why this is automatic, not opt-in:** waiting on a CONFLICTING PR for an hour before noticing review never ran is a real-world failure mode. The pipeline owns the PR lifecycle end to end; "raised PR" is not the same as "shippable PR" — the conflict gate enforces the difference.

**Override:** there is no override for this gate. A conflicting PR cannot proceed to review or CI by definition, so skipping the check doesn't unblock anything — it just delays discovery.

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
