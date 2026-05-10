---
description: Bootstrap a new or existing project — run project detection, create .claude/docs/, install git hooks, scaffold missing deploy configs.
---

# Development Pipeline: Init

You are setting up pipeline infrastructure for a project.
All steps are pre-approved. Do not ask for permission. Run to completion.

---

## STEP 1: Run Project Detection

Invoke the `project-detector` skill. It will:
- Fingerprint the stack (language, framework, ORM, test runner, linter)
- Detect deploy targets from config files and Phase 1 text
- Emit `.claude/project-profile.json`

If `project-profile.json` already exists and is <7 days old, skip detection.

---

## STEP 2: Create .claude/ Structure

```bash
mkdir -p .claude/docs .claude/instincts
touch .claude/agent-events.jsonl
```

Create `.claude/pipeline-state.json`:
```json
{ "phase": null, "task": null, "mius": [], "updatedAt": null }
```

Create `.claude/miu-progress.json`:
```json
{ "task": null, "mius": [], "updatedAt": null }
```

---

## STEP 3: Generate Living Documents

Create `.claude/docs/PROJECT_STATUS.md` from codebase scan:
- Current branch, recent commits (`git log --oneline -10`)
- Open PRs (`gh pr list`)
- Any TODO/FIXME density (`grep -r "TODO\|FIXME" src/ | wc -l`)
- Active blockers: none at init

Create `.claude/docs/ARCHITECTURE.md`:
- Stack summary from `project-profile.json`
- Directory structure (`find . -maxdepth 3 -type d | grep -v node_modules | grep -v .git`)
- Key dependencies from `package.json` (top 10)
- Environment variables from `.env.example` if present

Create `.claude/docs/RECENT_CHANGES.md`:
- Last 10 commits formatted as entries

---

## STEP 4: Install Git Hooks

```bash
if [[ -d .git ]] && [[ ! -f .git/hooks/pre-commit ]]; then
  bash ~/.claude/setup-git-hooks.sh
fi
```

---

## STEP 5: Scaffold Missing Deploy Configs

Read `project-profile.json` → `scaffoldingMIUs`. For each:
- Create the missing config file with sensible defaults
- Commit: `chore: scaffold [config] for [platform]`

---

## STEP 6: Summary

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ PIPELINE INIT COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Stack:    [framework] / [runtime]
Deploy:   [targets]
Hooks:    [installed / already present]
Scaffolded: [list of new config files]
Docs:     .claude/docs/ created
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Next: /dev-pipeline:dev-pipeline [your first feature]
```
