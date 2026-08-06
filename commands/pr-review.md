---
description: Respond to PR review comments — parse, fix, validate, push. Takes PR number or reads open PR automatically.
---

# Development Pipeline: PR Review Response

You are addressing code review feedback on an open PR.
All steps are pre-approved. Do not ask for permission. Run to completion.

---

## STEP 1: Load Review Comments

```bash
PR="${1:-$(gh pr view --json number --jq '.number')}"
gh pr view "$PR" --json reviews,comments,reviewDecisions \
  | jq '.reviews[-1], .comments'
```

Categorise each comment:
- **Must-fix** — correctness, security, test failures, type errors
- **Should-fix** — style, naming, minor architecture
- **Nit** — formatting, preference (fix if trivial, note if not)

---

## STEP 2: Verify Current State

```bash
git fetch origin
git status
npx tsc --noEmit 2>&1 | tail -20
```

If there are pre-existing errors not mentioned in the review, note them separately — do NOT conflate with review feedback.

---

## STEP 3: Fix All Must-Fix and Should-Fix Items

For each item:
1. Re-read the file before editing
2. Apply the fix
3. Re-read after editing to confirm

After all fixes:
```bash
npx tsc --noEmit
npx eslint . --quiet
npm test -- --passWithNoTests
```

All must pass before proceeding.

---

## STEP 3.9: Gate the fixes before pushing them (MANDATORY)

A review-fix commit is still a commit. This command reaches neither
`/dev-pipeline:validate` nor `/dev-pipeline:review`, so without this step a fix round
pushes code that no gate has seen — and a fix made under time pressure to close a
reviewer's finding is exactly when a second one gets introduced.

```bash
# Resolve the runner from the PLUGIN, not the cwd. These commands run inside CONSUMER
# repos, where `tools/run-craft-gates.sh` does not exist — the relative path made the
# whole gate step a silent no-op everywhere it actually mattered.
GATE_RUNNER=""
for cand in \
  "${CLAUDE_PLUGIN_ROOT:-}/tools/run-craft-gates.sh" \
  "$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline/tools/run-craft-gates.sh" \
  "./tools/run-craft-gates.sh"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { GATE_RUNNER="$cand"; break; }
done
if [ -z "$GATE_RUNNER" ]; then
  echo "GATE ERROR — run-craft-gates.sh not found (looked in \$CLAUDE_PLUGIN_ROOT, the marketplace path, and ./tools)."
  echo "  The gates did NOT run. This is a P1, not a pass."
else
  git diff --name-only HEAD > /tmp/changed-files.txt
  "$GATE_RUNNER" --changed-files /tmp/changed-files.txt
  GATE_RC=$?   # 0 clean/NA · 1 findings · 2 gate execution error — gates did NOT run
fi
```

`2` blocks: the gates did not run, which is not a pass. `1` blocks when the finding is
in a file this fix touched. Then run `/dev-pipeline:review` to re-bless HEAD — the
pre-push hook refuses the push otherwise, and every new commit invalidates the previous
blessing.

---

## STEP 4: Commit and Push

```bash
git add -p   # stage only review-fix changes
git commit -m "fix: address PR review feedback"
git push
```

Do not squash the existing commits. Keep review fixes as a separate commit.

---

## STEP 5: Re-request Review

```bash
gh pr review "$PR" --comment \
  --body "Review feedback addressed. Summary of changes: [list each must-fix and should-fix item resolved]"
```

If nits were skipped, list them explicitly so reviewers know they were seen.

---

## OUTPUT

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ PR REVIEW ADDRESSED: #[N]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Fixed:   [N] must-fix, [N] should-fix
Skipped: [N] nits (listed above)
Pushed:  [commit sha]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
