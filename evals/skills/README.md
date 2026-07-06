# Per-Skill Evaluation Layer

> **Two layers, one system.** The parent `evals/` folder scores the **whole pipeline** from a run
> transcript (the *macro* / orchestration harness). This folder scores **each standalone skill on
> its own** (the *micro* layer). A skill can be excellent in isolation yet mis-orchestrated, or
> well-orchestrated yet individually weak — you need both lenses.
>
> **Build order: micro first, then macro.** Individual skills are smaller, more isolated, and
> (for some) have a *checkable correct answer*, so they're the doable starting point. Fix the
> skills bottom-up, then the orchestration harness measures whether they compose well.

---

## Why this is where SkillOpt and Darwin actually kick in

The macro harness couldn't use either tool off-the-shelf, because a pipeline run isn't a single
`SKILL.md`. **A standalone skill is.** So at this layer the published tools map on directly —
*per skill*, depending on its **evaluability class**:

| Class | What it means | Tool that fits | Scoring |
|---|---|---|---|
| **1 · Deterministic** | The skill has a *checkable correct answer* (input→output you can diff against ground truth). | **SkillOpt-style** (benchmark + validation set) | **Programmatic** — exact-match / schema-valid / detection TP-FP → a hard number |
| **2 · Judgement** | No single right answer, but quality is judgeable against a rubric. | **Darwin-style** (rubric + independent judge + human-in-loop) | **Rubric-judge** (reuse `../judge.md` pattern, per-skill rubric) |
| **3 · Hybrid** | Produces an artifact that is partly checkable, partly judgement. | Both | **Programmatic gate + rubric** |

### The 9 skills, classed

Sorted so the "most doable / most objective" come first within each class.

**Class 1 — Deterministic (do these first; they yield hard numbers):**
- `project-detector` — fixture repo → `project-profile.json`. **Fully ground-truth-able.** ← built first, the reference implementation.
- `cross-file-reasoning` — seeded cross-file break → caught or missed. **Detection rate (TP/FP)** measurable; already ships a `FAILURE_MODES.md` catalog to seed cases from.
- `prd-parser` — PRD → `project-spec.json`. Schema-valid + required-field match (a soft edge remains: phrasing of derived fields).

**Class 3 — Hybrid:**
- `excalidraw-diagram-generator` — `.excalidraw` JSON. Programmatic gate (valid JSON, renders, required node/edge types present) **+** rubric (is the diagram actually legible?).

**Class 2 — Judgement (Darwin-style rubric; do after a Class-1 proves the pattern):**
- `spec-elicitor` — quality of Socratic questioning, correct mode selection (A vs B), correct business-vs-technical call.
- `miu-methodology` — decomposition quality, 8-field completeness, right granularity.
- `cloud-design-patterns` — did it select defensible patterns for the design, with documented trade-offs.
- `code-refactor` — proposal quality; **propose-only discipline** (never silently rewrites).
- `skill-router` — did it route to the right skills/MCPs for the stack+task.
- `cloudflare-security` — correct security-rule selection for the stated threat surface.

---

## Folder layout

```
evals/
├── RUBRIC.md            # macro: orchestration rubric (whole-pipeline)
├── TASKS.md             # macro: held-out task suite
├── judge.md             # macro+micro: the independent judge agent (reused)
├── results.tsv          # macro scoreboard
├── runs/                # macro transcripts
└── skills/                       # ← THIS LAYER (micro)
    ├── README.md                 # this file (taxonomy + how-to)
    ├── _TEMPLATE/                # copy this to start a new per-skill eval
    │   ├── SKILL_EVAL.md         # per-skill rubric + class + how-to-run
    │   ├── cases/                # inputs (fixtures or prompts)
    │   ├── expected/             # ground-truth answers (Class 1/3)
    │   ├── score.py              # programmatic scorer (Class 1/3); stub for Class 2
    │   └── results.tsv           # this skill's scoreboard
    └── project-detector/         # ← reference implementation (Class 1)
        ├── SKILL_EVAL.md
        ├── cases/                # mini fixture repos
        ├── expected/             # known-correct project-profile.json per case
        ├── score.py             # field-level exact-match scorer
        └── results.tsv
```

Each skill gets its **own** `results.tsv` (its local ratchet) and rolls a summary line up to the
macro `evals/results.tsv` when it changes, so you can see both "skill X improved" and "did the
whole pipeline improve."

---

## The per-skill loop (same ratchet, finer grain)

```
0. Baseline the skill
   Class 1/3 → run score.py over cases/ vs expected/ → hard % into the skill's results.tsv.
   Class 2   → run ../judge.md with the skill's SKILL_EVAL.md rubric over cases/ → /100.

1. Change ONE thing in the skill's SKILL.md (fix the weakest case / dimension).

2. Re-score the SAME cases.
   Class 1/3 → re-run score.py.
   Class 2   → fresh judge (anti-anchoring).

3. Ratchet: keep iff new score STRICTLY > old on the same cases; else git revert.

4. Roll up: if kept, also re-run the macro task(s) that exercise this skill (e.g. a
   project-detector change → macro T01/T02 which start at Phase 0) to confirm the skill's
   improvement didn't regress the orchestration. Log to BOTH results.tsv files.
```

### Why the roll-up matters (the two layers talking)
A skill can score higher in isolation and still hurt the pipeline (e.g. `project-detector` gets
more precise but slower, or emits a field the downstream MIU planner mis-reads). Step 4 is the
guard: **a per-skill win is provisional until the macro harness agrees.** This is the micro→macro
hand-off you asked for, made concrete.

---

## Honest limits specific to this layer

- **Class 1 fixtures are synthetic.** A mini fixture repo isn't a real codebase; a skill can ace
  fixtures and still trip on a messy real repo. Grow `cases/` from real repos you hit, the way
  `TASKS.md` says to grow the macro suite — never edit a case to match current output (Rule-19
  tautology).
- **Programmatic exact-match can be too strict.** `project-detector` emitting `"react"` when the
  expected is `"vite"` for a Vite-React app may be defensibly correct. The scorer flags
  field-level diffs; a human (or the thin rubric) adjudicates genuinely-ambiguous fields rather
  than the script failing the whole case. Keep ambiguous fields out of the hard-scored set or
  mark them `soft` in `expected/`.
- **Don't over-fit a skill to its own eval.** Same reward-hacking risk as the macro layer: a
  skill can grow to pass cases without getting better. The roll-up (Step 4) and a periodic real
  repo are the defense.
```
