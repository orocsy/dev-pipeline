# Dev Pipeline Plugin

Multi-agent development pipeline that simulates an engineering team. Each agent plays a distinct role, does one thing well, and hands off to the next.

## Commands

| Command | Description | Usage |
|---------|-------------|-------|
| `/dev-pipeline` | Full feature workflow (12 phases) | `/dev-pipeline add dark mode toggle` |
| `/validate` | Run validation suite (lint, tsc, tests, build) | `/validate admin` |
| `/fix-review` | Fix code review issues from a PR | `/fix-review 10` |

## Agents

| Agent | Role | Model | Tools |
|-------|------|-------|-------|
| `requirements-analyst` | Product Owner / BA | sonnet | Read-only |
| `technical-architect` | Senior Architect | sonnet | Read-only |
| `tech-lead` | Module & task breakdown | sonnet | Read-only |
| `test-planner` | QA Lead (test scenarios) | sonnet | Read-only |
| `validator` | QA Engineer (run checks) | haiku | Bash only |
| `review-analyzer` | Review parser | sonnet | Read + gh CLI |
| `design-checker` | Design gatekeeper | haiku | Read-only |
| `skill-scout` | Tooling specialist | haiku | Read + ls |

## Pipeline Flow

```
Phase 1:  Requirements Analysis    → requirements-analyst agent
Phase 2:  Skill Discovery          → skill-scout agent
Phase 3:  Design Check             → design-checker agent
Phase 4:  Technical Design         → technical-architect agent
Phase 5:  Module Breakdown         → tech-lead agent
Phase 6:  Test Planning            → test-planner agent
Phase 7:  Implementation           → Claude (with auto-activated skills)
Phase 8:  Final Validation         → validator agent
Phase 9:  Commit & PR              → /commit-push-pr (existing plugin)
Phase 10: Code Review              → /code-review (existing plugin)
Phase 11: Fix Cycle                → review-analyzer + validator agents
Phase 12: Summary                  → done
```

## Reuses Existing Plugins

This plugin delegates to existing plugins rather than duplicating:
- `commit-commands` for git operations
- `code-review` for PR reviews
- `vercel-react-best-practices` auto-activates during React work
- `vercel-composition-patterns` auto-activates for component architecture
- `ui-ux-pro-max` and `web-design-guidelines` for design phases (manual)

## Installation

Enabled via `~/.claude/settings.json`:
```json
{
  "enabledPlugins": {
    "dev-pipeline@local": true
  }
}
```
