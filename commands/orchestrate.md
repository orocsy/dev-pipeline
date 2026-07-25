---
description: Run this task in Orchestrator-Advisor mode — coordinator drafts micro-milestone specs, Opus-class executors implement, coordinator reviews each report before the next dispatch.
argument-hint: [task description]
---

# /dev-pipeline:orchestrate — Orchestrator-Advisor Mode (invoked)

Execute the task below using the **Orchestrator-Advisor execution schema**. This
command is the in-plugin entry point Rule 24 refers to: typing
`/dev-pipeline:orchestrate` (or asking for "orchestrator mode") is what flips a
session from direct execution into coordinator mode. Uninvoked sessions keep
executing directly — do NOT assume this schema unless it was asked for.

**Authority:** the canonical schema is `docs/RULES.md` → **"Rule 24:
Orchestrator-Advisor execution schema"**. That rule text governs; the reminders
below are an operational summary of it, not a substitute — if they ever drift,
Rule 24 wins.

Task: $ARGUMENTS

---

## Operating reminders (summary of Rule 24 — the rule text is authoritative)

- **You are the coordinator + advisor, not the implementer.** When this mode is
  active the coordinating session does NOT write the code itself. It drafts
  specs, dispatches them, and reviews the results.
- **One MICRO-milestone per dispatch (MIU-grade).** Each spec is the smallest
  independently verifiable increment — one file-cluster edit, one function + its
  test, one config change with its check. Never "implement the whole thing, then
  review": that collapses into after-the-fact code review, which already exists
  as a separate gate and is not what this schema buys.
- **Draft each task as a DETAILED spec** — context, exact files, exact edits or
  acceptance criteria, and the verification commands the executor must run.
- **Dispatch to a high-capability executor** (Opus-class, maximum effort), ONE
  spec at a time.
- **Review each report as ADVISOR before the next dispatch** — evaluate against
  the spec, then continue / redirect / redesign, and only then draft the next
  micro-milestone. Never dispatch the next unit before judging the last one.
- **Sequence risk-first** — order milestones so the costly, likely, or invisible
  failures (irreversible actions, silent failures) are confronted early rather
  than left to the end.
- **Sizing is your judgment — err MICRO.** If judging a report would itself
  require a code review, the milestone was too big; split it.
- **Trivial one-step work stays direct** — a config line, a rename, a lookup:
  just do it, even when this mode is active. Dispatch overhead is not free.
- **Executors report facts** (diffs, command outputs, deviations), never
  marketing summaries. A deviation from spec is reported, not silently
  improvised around.
