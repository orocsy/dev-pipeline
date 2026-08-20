# Learnings

## [LRN-20260821-001] correction

**Logged**: 2026-08-21T00:55:00Z
**Priority**: critical
**Status**: resolved
**Area**: docs

### Summary
Cross-agent handoff cannot depend on a gitignored pointer or filename/newest-plan guessing.

### Details
A feature worktree had no `.claude/pipeline-state.json` in a fresh-agent context and no `.claude/docs/PROJECT_STATUS.md`. Its tracked `EXECUTION.md`, `task_plan.md`, `progress.md`, and `COMPATIBILITY.md` disagreed: MIU 22 was variously active, blocked, and complete, while remediation MIUs 23-25 had no status. Another agent invented a separate P1-P6 plan and even named a nonexistent branch because SessionStart printed nothing and implementation only recognized lowercase `*-execution.md`/`*-miu-breakdown.md` names.

### Suggested Action
Tracked execution docs declare branch, current phase, current/next MIU, role-specific next actions, and exact remote/deploy evidence. SessionStart and every pipeline role resolve docs through one branch/task-aware helper supporting both uppercase canonical and lowercase slugged filenames. Never select the repo-newest plan as a fallback; stop and run sync instead.

### Metadata
- Source: user_feedback
- Related Files: hooks/session-start.sh, tools/resolve-feature-doc.sh, commands/implement.md, commands/verify-traceability.md, agents/doc-writer.md
- Tags: multi-agent, handoff, state-drift, source-of-truth, miu

---
