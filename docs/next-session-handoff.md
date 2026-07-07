# Next-Session Handoff + Live Project Test Protocol

_Last updated: 2026-07-07 (post PR #7 merge, e125a31; fix/codex-pr7-round1 in flight)_

## 1. State snapshot
- **main** carries: CLAUDE.md diet (94 lines) + docs/RULES.md · lifecycle hooks
  (hooks.json: SessionStart w/ compact matcher + Stop review-guard) · Rule 23 Socratic
  gate (Mode A six-section SPEC incl. Quality Criteria / Mode B Scope-Lock) ·
  contract-first MIU ordering · mutation-test backstop (opt-in) · quality-criteria
  traceability · tools/validate-miu-breakdown.sh gating implement STEP 0 (+ fixture suite).
- **Plugin cache** rewired to the merged SHA; slash commands live in fresh sessions.
- **ONE pending observation** (not an implementation): watch the SessionStart hook print
  pipeline state and the Stop guard block an unblessed turn — first live firing.
- Codex round-1 on PR #7: 6 P2s → fix branch `fix/codex-pr7-round1` (PR + merge + rewire
  to complete if the prior session didn't).

## 2. Live project test protocol (the user drives; per-phase scoring)
The user states what they want to build. Then run the pipeline FOR REAL (not simulated),
one phase at a time, with a measurement + discussion gate after each:

| Step | Pipeline phase | Score/verify with | Discussion gate |
|---|---|---|---|
| 1 | Routing + Phase 1.0 elicitation (Mode A, 6 sections) | judge.md D4 + D6 on the LIVE transcript segment | SPEC meets intent? |
| 2 | Phases 1.1–3 (analysts, skill-scout, design check) | D6 + blindspot coverage (did analysts surface unknowns the user hadn't considered?) | unknowns cleared? |
| 3 | Phase 4–5 (architect w/ Rule 22 probes, tech-lead MIUs) | run tools/validate-miu-breakdown.sh (mechanical) + D1/D2 judge pass | G3 approve |
| 4 | Phase 6 (test plan) + G4 | D5 gate integrity | G4 approve |
| 5 | Phase 7 implement (per-MIU) | validator agent + Stop-hook observation + execution-doc quality (Deviations logged?) | mid-point review |
| 6 | Phase 8-8.6 validate + traceability (incl. §6 quality criteria) | the verify-* outputs themselves | expectation check |
| 7 | Deliver (PR, conflict gate, review, merge) | D5/D7 on live evidence | ship decision |

Each step's judge run appends to evals/results.tsv (task id: LIVE-<slug>-S<step>).
This doubles as the harness's missing evidence tier: REAL session transcripts.

## 3. Where the field-guide ideas landed
See evals/BACKLOG.md #15–19 (added 2026-07-07) for design assessments + specs.
