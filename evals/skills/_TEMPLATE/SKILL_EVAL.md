# SKILL_EVAL · <SKILL-NAME>

> Copy this folder to `evals/skills/<skill-name>/` and fill the blanks. Delete the guidance in
> «angle brackets». Keep only the section for your skill's **class** (delete the other two).

**Class:** «1 Deterministic | 2 Judgement | 3 Hybrid»
**Skill under test:** `skills/<skill-name>/SKILL.md`
**What "good" means (one sentence):** «the observable property that makes this skill useful»

---

## ‼ Pick your class (delete the others)

### ── Class 1 · Deterministic (SkillOpt-style) ──
Use when the skill has a **checkable correct answer** (input → output you can diff).
Examples in this repo: `project-detector` (reference impl), `cross-file-reasoning`, `prd-parser`.

- `cases/<id>/` = the input (a fixture repo, a PRD file, a diff with a planted break).
- `expected/<id>.json` = the known-correct answer. Convention (see `project-detector/score.py`):
  - top-level keys → **hard** (exact / set-equal);
  - `_soft: {field: "alt1|alt2"}` → **soft** (defensible variants, lenient);
  - `_ignore: [...]` → not scored.
- Scorer: copy `../project-detector/score.py` and adapt the field logic, OR for detection-style
  skills score **TP/FP**: `expected/<id>.json = {"should_catch": ["bug-A","bug-B"], "should_not_flag": [...]}`
  and have the scorer compute precision/recall over what the skill flagged.
- **The number that ratchets** = mean over cases. `python3 score.py --batch runs/<sha>/`.

### ── Class 2 · Judgement (Darwin-style) ──
Use when there's **no single right answer** but quality is judgeable on a rubric.
Examples: `spec-elicitor`, `miu-methodology`, `cloud-design-patterns`, `code-refactor`,
`skill-router`, `cloudflare-security`.

- `cases/<id>.md` = an input prompt + the **expected protocol** and **traps** (like `evals/TASKS.md`).
- Score with the **independent judge** (`../../judge.md`) against the **per-skill rubric below**,
  not the macro orchestration rubric.
- Fill the rubric: 3–6 dimensions, each 0–10 × weight, summing to 100. Seed with the SkillLens
  trio where they apply (does the skill's *output* encode failure branches / stay specific /
  flag risks), plus skill-specific dimensions. Example dimension set for `spec-elicitor`:
  | Dim | Name | Weight | 9–10 looks like |
  |-----|------|--------|-----------------|
  | S1 | Correct mode/route choice | 25 | picked Mode A vs B correctly; got business-vs-technical right |
  | S2 | One-question-per-turn discipline | 15 | never batched questions; numbered options each turn |
  | S3 | Question quality (clarify/probe/alternatives) | 25 | questions actually narrow the ambiguity; no filler |
  | S4 | Output fidelity (SPEC 5 sections / Intent Lock shape) | 20 | artifact matches the contract exactly |
  | S5 | Knows when to stop / escalate | 15 | capped Mode B at ~4 turns; escalated oversized scope |
- **The number that ratchets** = judge total. Fresh judge each round (anti-anchoring).

### ── Class 3 · Hybrid ──
Use when the skill emits an **artifact** that is partly checkable, partly judgement.
Example: `excalidraw-diagram-generator`.

- **Gate (programmatic, pass/fail):** valid JSON? renders? required node/edge types present? A
  failed gate caps the score (a broken artifact can't be "good" regardless of taste).
- **Quality (rubric, 0–100):** is the diagram legible / correctly structured for the described
  system? Score with `../../judge.md` against the rubric below.
- **The number that ratchets** = `gate_pass ? rubric_total : 0`.

---

## Cases (frozen — grow, don't edit to match output)

| id | input | exercises |
|----|-------|-----------|
| 01 | «…» | «…» |
| 02 | «…» | «…» |

«Coverage intent: hit every major branch of the skill. Add cases when the skill fails a real
input in the wild. NEVER relax an expected value to match current output (Rule-19 tautology).»

---

## How to run a round

```
# baseline → change ONE thing in skills/<skill-name>/SKILL.md → re-run SAME cases → ratchet
# Class 1/3:  python3 score.py --batch runs/<plugin-sha>/
# Class 2:    launch ../../judge.md per case with the rubric above
# keep iff new mean STRICTLY > old on the same cases; else git revert.
# roll up: re-run the macro evals/TASKS.md task(s) that exercise this skill to confirm no
#          orchestration regression, then log to BOTH this results.tsv and evals/results.tsv.
```

## Known soft edges
«List fields/judgements where defensible alternatives exist, so you don't chase false regressions.»
