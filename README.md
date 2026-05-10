# dev-pipeline

Personal Claude Code plugin: methodology, commands, agents, and skills for full-stack feature development. Private — opinionated to my workflow.

## Where it lives

The real source is at `~/Desktop/projects/dev-pipeline/`. It's symlinked into Claude Code's plugin marketplace so the plugin system loads it normally:

```
~/Desktop/projects/dev-pipeline/                       ← real source (this repo)
~/.claude/plugins/marketplaces/local/plugins/
    dev-pipeline → ~/Desktop/projects/dev-pipeline    ← symlink
```

Editing in either location works (they're the same files). Use the projects path for normal git workflows.

## What's inside

```
commands/        — slash-command definitions (/dev-pipeline:*)
agents/          — sub-agent definitions used by phase commands
skills/          — Skill tool definitions
docs/            — methodology notes (workflow improvements, etc.)
CLAUDE.md        — plugin-level instructions auto-loaded by Claude Code
```

## Decoupled sibling — spec-forge

`spec-forge` (separate repo) is the scaffolder for **new** projects. dev-pipeline references but does NOT depend on it. They communicate only via `spec.json` files + the `spec-forge` CLI.

| | dev-pipeline | spec-forge |
|---|---|---|
| Audience | me | anyone |
| License | private | MIT |
| Repo | `orocsy/dev-pipeline` (private) | `orocsy/spec-forge` (private for now) |
| Concern | methodology + commands for **existing-project** work | scaffold registry for **new-project** bootstrap |

## Commands index

### Master flow
- `/dev-pipeline:pipeline` — full 12-phase pipeline for new features (+ G1–G5 gates)
- `/dev-pipeline:scaffold-from-prd` — PRD → spec.json → spec-forge CLI (NEW projects only)

### Per-phase
- `/dev-pipeline:plan` — phases 1–6 (requirements → architecture → MIU breakdown → test plan)
- `/dev-pipeline:implement` — phase 7 (TDD)
- `/dev-pipeline:validate` — phase 8 (lint + tsc + unit + e2e + build)
- `/dev-pipeline:review` — phase 8.5 (proactive local code review on diff)
- `/dev-pipeline:deliver` — phases 9–12 (commit → push → PR → review → CI → deploy)

### Verify gates (new — wired into pipeline at Phase 7.5 / 8.1 / 8.2 / 8.6)
- `/dev-pipeline:verify-contract` — frontend payload ↔ backend DTO shape diff
- `/dev-pipeline:verify-blast-radius` — run dependent-feature tests when shared code changes
- `/dev-pipeline:verify-visual` — headed screenshots vs design spec
- `/dev-pipeline:verify-traceability` — re-check Phase 1 specs against final code

### Specialised flows
- `/dev-pipeline:fix` / `:fix-review` / `:pr-review` — bug fixes + review feedback
- `/dev-pipeline:hotfix` — production incident fast path
- `/dev-pipeline:update` — enhance existing feature (lighter than full pipeline)
- `/dev-pipeline:refactor` — propose-only refactor (never silently rewrites)
- `/dev-pipeline:perf` / `:health` — performance + system-health audits
- `/dev-pipeline:learn` / `:sync` — capture learnings + refresh living docs
- `/dev-pipeline:init` / `:detect` / `:deploy` — project bootstrap helpers

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

## Reuses existing plugins / skills

This plugin delegates rather than duplicates:
- `commit-commands` for git operations
- `code-review` for PR reviews
- `vercel-react-best-practices`, `vercel-composition-patterns` auto-activate during React work
- `ui-ux-pro-max`, `web-design-guidelines` for design phases (manual)
- 12 `nodejs-*` / `nestjs-*` skills auto-activate when descriptions match the task context

## License

Private. Not licensed for redistribution.
