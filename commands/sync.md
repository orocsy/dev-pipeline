---
description: Refresh all living documents (PROJECT_STATUS, ARCHITECTURE, RECENT_CHANGES) from current codebase state. Run after any significant work or before context compaction.
---

# Development Pipeline: Sync

You are refreshing the project's living documents so they reflect current reality.
All steps are pre-approved. Do not ask for permission. Run to completion.

---

## STEP 1: Gather Current State

```bash
git log --oneline -20
git status
git branch --show-current
gh pr list --limit 5 2>/dev/null || true
```

---

## STEP 2: Update PROJECT_STATUS.md

Rewrite `.claude/docs/PROJECT_STATUS.md` with:

```markdown
# Project Status
_Updated: [timestamp]_

## Current Branch
[branch name]

## Active Task
[current task from pipeline-state.json, or "none"]

## MIU Progress
[miu-progress.json summary, or "none"]

## Open PRs
[gh pr list output]

## Recent Commits (last 10)
[git log --oneline -10]

## Blockers
[any known blockers, or "none"]
```

---

## STEP 3: Update ARCHITECTURE.md

Only update sections that have changed since last sync (check `git diff` for structural changes):
- Stack: re-read `project-profile.json`
- Dependencies: re-read `package.json` dependencies
- Env vars: re-read `.env.example`
- Directory structure: only if new top-level dirs were added

Preserve existing explanatory prose — do not regenerate it.

---

## STEP 4: Update RECENT_CHANGES.md

Prepend the last sync's new commits to the top of `RECENT_CHANGES.md`:

```markdown
## [date]
- [commit sha] [commit message] ([files changed])
...
```

Keep a rolling window of the last 30 entries. Remove entries older than that.

---

## STEP 5: Commit Sync (if run manually)

```bash
git add .claude/docs/
git commit -m "chore: sync living documents [$(date +%Y-%m-%d)]" \
  --no-verify 2>/dev/null || true
```

(Skip commit if sync was triggered by post-commit hook to avoid infinite loop.)

---

## OUTPUT

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ SYNC COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROJECT_STATUS:  updated
ARCHITECTURE:    [updated / unchanged]
RECENT_CHANGES:  [N] new entries
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
