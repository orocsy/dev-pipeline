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

- If **clean** → proceed to PHASE 10.5 (E2E gate). Do NOT auto-merge yet.
- If **issues found** → run `/dev-pipeline:fix` automatically, then re-review.
- Do NOT ask the user. Fix and re-review autonomously.

---

## PHASE 10.5: Browser E2E Gate (MANDATORY for frontend-touched PRs)

After code review clears, BEFORE merge, run targeted Playwright E2E against the deploy preview URL. Unit tests can't observe SSR hydration, basePath redirects, footer-link placement under real browser rendering, or visual issues that only manifest in a real browser — and these are exactly the regressions that have shipped to prod in the past despite green unit tests.

### Step 1 — Detect surface area

```bash
BASE="$(gh pr view --json baseRefName --jq '.baseRefName')"
PR_NUM="$(gh pr view --json number --jq '.number')"
CHANGED="$(git diff --name-only "origin/$BASE"..HEAD)"

FRONTEND_TOUCHED=0
declare -a AFFECTED_APPS=()

# Detect frontend changes. Per-app granularity so the test run stays
# narrow (one app's spec suite, not the whole monorepo).
for app in apps/admin apps/booking; do
  if echo "$CHANGED" | grep -qE "^$app/(src|messages|public)/"; then
    FRONTEND_TOUCHED=1
    AFFECTED_APPS+=("$(basename "$app")")
  fi
done

# Also count shared UI changes (packages/ui) as frontend.
if echo "$CHANGED" | grep -qE "^packages/ui/"; then
  FRONTEND_TOUCHED=1
  # Without knowing which apps consume the changed bits, run both.
  AFFECTED_APPS=(admin booking)
fi

if [[ "$FRONTEND_TOUCHED" -eq 0 ]]; then
  echo "ℹ️  No frontend files touched — skipping E2E gate."
  echo "    (Docs-only / config-only / backend-only diffs skip Playwright.)"
  # Continue to merge.
else
  echo "🌐 Frontend touched: ${AFFECTED_APPS[*]} — running E2E against preview..."
fi
```

### Step 2 — Resolve deploy preview URLs

```bash
# Vercel bot posts a comment on the PR with preview URLs. Parse it.
PREVIEW_COMMENT="$(gh api "repos/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/issues/$PR_NUM/comments" --jq '[.[] | select(.user.login == "vercel[bot]")] | last | .body')"

for app in "${AFFECTED_APPS[@]}"; do
  url="$(echo "$PREVIEW_COMMENT" | grep -oE "https://luxebook-${app}-[a-z0-9-]+\.vercel\.app" | head -1 || true)"
  case "$app" in
    admin)   ADMIN_PREVIEW="$url" ;;
    booking) BOOKING_PREVIEW="$url" ;;
  esac
done

# Verify accessibility (Vercel deployment protection can lock previews).
for app in "${AFFECTED_APPS[@]}"; do
  var="${app^^}_PREVIEW"
  url="${!var}"
  [[ -z "$url" ]] && { echo "⚠️  No preview URL for $app — falling back to local stack (slow)"; continue; }
  status="$(curl -sI -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)"
  if [[ "$status" == "401" ]]; then
    echo "🛑 $app preview is auth-protected (HTTP 401). Either:"
    echo "   1. Set VERCEL_PROTECTION_BYPASS in Playwright env, OR"
    echo "   2. Disable deployment protection for this PR's preview, OR"
    echo "   3. Run E2E against local stack (docker compose up + pnpm dev)."
    exit 1
  fi
done
```

### Step 3 — Run targeted Playwright project against preview

```bash
for app in "${AFFECTED_APPS[@]}"; do
  case "$app" in
    admin)
      PLAYWRIGHT_ADMIN_URL="$ADMIN_PREVIEW" \
        npx playwright test --project=admin-chromium tests/e2e/admin/ || {
          echo "🛑 Admin E2E failed against preview — blocking merge."
          exit 1
        }
      ;;
    booking)
      PLAYWRIGHT_BOOKING_URL="$BOOKING_PREVIEW" \
        npx playwright test --project=booking-chromium tests/e2e/booking/ || {
          echo "🛑 Booking E2E failed against preview — blocking merge."
          exit 1
        }
      ;;
  esac
done

echo "✅ E2E gate cleared for ${AFFECTED_APPS[*]} — proceeding to merge."
```

### Why this is automatic, not opt-in

The branding-e2e GitHub Actions workflow was changed to `workflow_dispatch` only in April 2026 (CI minutes cost). That decision plus the missing per-PR gate left a real gap: frontend changes routinely merge without browser tests, and a regression in SSR hydration / link placement / route behaviour ships to prod despite green unit tests. The deploy-preview approach sidesteps the CI-minutes concern entirely — tests run on the artifact Vercel already built, not a fresh CI environment.

### Override

For docs-only / config-only / backend-only PRs the detection step skips automatically. **There is no override for frontend-touched PRs** — the cost (40s of test run against an already-built preview) is far less than one prod-bug post-mortem.

### When a preview is auth-protected

Vercel "deployment protection" can be enabled on a per-project basis, locking previews behind a login. If E2E hits a 401, three options listed in the script above. For projects that need preview protection AND auto-E2E, use Vercel's "Protection Bypass for Automation" tokens — set `VERCEL_PROTECTION_BYPASS` as a CI/local secret and pass it via the `x-vercel-protection-bypass` header in Playwright's `extraHTTPHeaders`.

### After E2E passes

Auto-merge:

```bash
gh pr merge "$PR_NUM" --squash --auto
```

`--squash` is the project's merge style (single commit on main per PR). `--auto` lets GitHub merge as soon as branch protection requirements are met (in case CI or required reviews are still finishing).

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
