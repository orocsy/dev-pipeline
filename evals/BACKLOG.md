# Eval-Surfaced Improvement Backlog

Findings from judge score cards + the 2026-07-06 whole-system diagram audit.
Each is a candidate "ONE change" for a future ratchet round (README loop step 1).
Ordered by expected score impact. Delete entries when landed + re-scored.

## From judges (both batches, 2026-07-06)

1. **hotfix.md — encode the incident doctrine the runs had to improvise** (D1, weakest
   dim on both T05 cards): revert-vs-forward-fix decision rule; branches for
   "revert conflicts", "revert lands but symptom persists", "cannot reproduce";
   explicit prohibitions (never `git reset --hard`/force-push shared history as
   rollback; never declare mitigated without a prod-surface check; never bundle
   class-level fixes into the incident diff).
2. **hotfix.md — G4 consent-text mismatch** (D5, T05 post-diet): the gate asks the
   user to confirm "push directly to main" while the executed path is
   branch → PR → squash-merge. Align the gate text with the real route.
3. **deliver.md — post-merge-smoke failure branch** (D1, T03 post-diet): merge lands
   at 10.5 but prod smoke runs at 12.5; encode the rollback/revert route when smoke
   fails after merge.
4. **fix.md — standalone never-do block** (D3, T03 baseline: scored 6/10): the flow's
   own foot-guns (no test-rewrite-to-match, no unblessed push, no `git add -A`) live
   only by reference; give fix.md its own blacklist section.
5. **fix.md — Rule 11 sweep must fix in-pass** (D6, T03 post-diet): a sweep-identified
   in-class consumer may currently be deferred to review; mandate same-pass fixes.
6. **refactor.md — staleness + analyzer-failure branches** (D1, T07 both): re-verify
   proposal locations if HEAD moved before "accept"; handle analyzer agent failure /
   malformed YAML. Consider pinned analyzer prompt blocks (reproducible delegation)
   and emitting proposals to `docs/` instead of `.claude/` scratch.

## Factory-redesign adaptations (landed 2026-07-06 — PENDING RATCHET, one per round)

Per `docs/factory-redesign-assessment.md` §5. All four are IMPLEMENTED but none has been
through its ratchet round yet — sequence them AFTER items 1–3 above (which outrank them
on expected score impact), ONE change per round, revert on non-improvement:

- **MIU-A landed**: contract-first ordering (`miu-methodology` Contract-source rule +
  tech-lead). Ratchet: T01 + T04 mean; judge should see contract MIU ordered first.
- **MIU-B landed**: Rule-19 mutation backstop (`validate.md` STEP 3.5, opt-in via
  Stryker). Ratchet: T03 + T09 + T10 mean; step fires only on assertion-rewrite diffs.
- **MIU-C landed**: quality-goals SPEC axis (`spec-elicitor` §6 + `verify-traceability`
  quality category). Ratchet: T01 + T08; SPEC in transcript contains the section.
- **MIU-D landed**: mechanical MIU-format validator (`tools/validate-miu-breakdown.sh`
  + `implement.md` STEP 0). Fixtures committed at `tools/fixtures/miu-breakdown/`
  (`compliant.md` / `missing-fields.md` / `ordering-violations.md`) with runner
  `tools/fixtures/miu-breakdown/run-fixture-tests.sh` asserting exit codes +
  named messages (incl. CRLF, column-0-bullet, and co-editor-exemption cases);
  ratchet: T01 + T04 + T07 mean.

## From the diagram audit (NEVER-RUN components — spec with zero executions)

7. **co-review**: one real `--once` round on a live PR (cold-start + cursor paths are
   the risk). Highest spec-to-reality ratio in the plugin.
8. **verify-visual**: run once on a real UI diff (auto-invoked only by the full
   pipeline; real work has routed via fix/update which skip it).
9. **setup-machine**: execute on the second device (its natural testbed).
10. **scaffold-from-prd / spec-forge bridge**: exercise on the next new-project idea.

## Methodology notes (calibrate the numbers)

- 2026-07-06 comparison caveat: baseline judge read the pinned plugin files
  (D1–D3 HIGH confidence); post-diet judge was transcript-only (D1–D3 LOW).
  Directionally consistent, but don't over-read per-dimension deltas.
- All runs so far are SIMULATED sessions from pinned worktrees. The harness's
  stronger evidence tier — judging a real session transcript — is unused; add one
  real-session transcript per shipped feature.

## From the T01 A/B round (2026-07-07)

11. **dev-pipeline.md — gate-rejection branches** (D1, flagged by BOTH T01 judges
    independently): every gate defines only the approval path; "user says No/Tweak
    at G1/G3/G4" is unwritten (which phase re-runs, which artifacts invalidate).
    Mirror the elicitor's Approve/Tweak/Add-more pattern per gate.
12. **CLAUDE.md gate table — G3 dual approval under-specified**: the run had to
    invent "G3 part 2" for the MIU plan reusing the architecture wording. Give the
    MIU-plan approval its own labeled ask (G3b) — 1-line CLAUDE.md change.
13. **Candidate NEW frozen task T11** (do NOT edit T01): "feature with a hard
    quality constraint" — expected protocol includes six-section SPEC quality
    criteria traced to tests + validator gate at implement STEP 0. Extends the
    instrument to cover the surfaces MIUs A-D added, which T01 measures only
    incidentally (a tie today = rubric ceiling, not absence of effect).
14. **Eval-transcript convention**: scoped runs must use planned/future wording for
    out-of-scope phases ("would run"), never achieved tense ("G5 green") — both T01
    judges flagged the same cap-risk ambiguity.

## From the Fable-5 field-guide review (2026-07-07) — design-assessed, awaiting ratchet rounds

15. **Blindspot pass (unknown-unknowns) in elicitation** — VALID, high-value, cheap.
    Today the elicitor asks about its six KNOWN sections and requirements-analyst
    surfaces ambiguities from the codebase; neither explicitly hunts unknown-unknowns.
    Spec: after the six sections (Mode A) or the locked axis (Mode B), run ONE
    codebase-grounded blindspot round — "this change also touches X/Y/Z (auth,
    tenancy, i18n, migrations, quotas) which you haven't mentioned — decide or defer
    each." Loops until the user has no new "oh right" reactions ("keep doing blind
    pass until you know"). Files: spec-elicitor SKILL.md + requirements-analyst.
16. **Architecture-impact question ordering** — VALID, tiny. Elicitor Rule: among
    candidate questions, ask FIRST those whose answer would change the architecture
    (the field guide's interview heuristic). One paragraph in spec-elicitor Protocol.
17. **Explicit Deviations log** — MOSTLY EXISTS (execution docs + doc-writer own
    "what failed first / trade-offs"; tracked docs already solve the cross-device
    /cross-account context problem by design). Gap: a named `## Deviations` subsection
    in the per-MIU execution format + the rule "hit an edge case mid-MIU → pick the
    conservative option, log it under Deviations, keep going — never silently deviate."
    Files: miu-methodology output format, doc-writer, implement.md.
18. **`/dev-pipeline:explain` — HTML change report + comprehension quiz** — NEW, good
    fit as an OPT-IN deliver-phase artifact (not agent-global): generates an HTML
    walkthrough of a merged change (context, intuition, what/why, diffs annotated)
    ending with a quiz the user must pass; wire as an optional deliver Phase 12.7
    offer + standalone command. Rationale: comprehension-verification closes the
    "user rubber-stamps agent work" gap — same philosophy as the eval quiz idea.
19. **Design-direction prototyping ("4 wildly different directions")** — PARTIALLY
    EXISTS design-phase routing (skill-router: Stitch/Figma/ui-ux-pro-max) is dated;
    ui-ux-pro-max is a deps.json external whose upstream should be re-checked by
    /dev-pipeline:refresh-deps + skill-doctor (run in a fresh session — freshness
    check is exactly what they exist for). Spec: design-check phase gains a
    "divergent directions" step — produce N contrasting HTML mock directions for
    user reaction BEFORE converging (works in Claude Code via artifacts; claude.ai
    Design is an alternative surface, not a replacement — the workflow needs the
    artifact IN the repo/design-doc trail).
