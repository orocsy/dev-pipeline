# dev-pipeline · Self-Evaluation Harness

> **The problem this solves.** You improve dev-pipeline by assigning it real tasks, watching what
> it does poorly, and patching the plugin. That loop has no **measurement** — even when a run
> completes every task, you can't tell whether your last patch made the pipeline *better* or just
> *bigger*. The `CHANGELOG.md` is a list of changes with **no number attached to any of them**.
>
> This folder adds the missing number. It does **not** replace your judgement — it gives your
> judgement a scoreboard and a ratchet.

---

## Why this design (and why not SkillOpt or Darwin off-the-shelf)

The 2026 self-improving-skill tools share one engine: **propose a change → measure on held-out
data → keep only if a real score rises, else revert.** The measurement *is* the engine; the
optimizer just turns the crank. dev-pipeline has no measurement yet, so the first job is to build
it — not to pick an optimizer.

Neither published tool drops in, because dev-pipeline is a **plugin** (agent + 9 skills + 27
commands + hooks), not a single `SKILL.md`:

- **Microsoft SkillOpt** (arXiv 2605.23904) optimises one `best_skill.md` against a **benchmark
  with a scoring function**. dev-pipeline has no benchmark (its quality is a judgement call) and
  no single file to optimise. Wrong philosophy, wrong unit.
- **Darwin** (`github.com/alchaincyf/darwin-skill`) is **rubric-driven + human-in-the-loop** —
  the right philosophy when "good" is subjective — but it scores **one `SKILL.md` at a time** and
  has no concept of the *orchestration* (routing, gates, delegation) that actually makes a
  pipeline good or bad. Right philosophy, wrong unit.

So this harness takes **Darwin's loop shape** and **SkillLens's validated rubric dimensions**, and
adapts the unit from "one skill file" to "**a run of the whole plugin, scored from its
transcript**". That is the part neither tool gives you.

What we borrowed, precisely:

| Idea | From | Where it lives here |
|---|---|---|
| Validation-gated acceptance (keep only if score strictly rises) | SkillOpt / Darwin ratchet / your own Rule 8 & 19 | `RUBRIC.md` "the ratchet"; this README's loop |
| Rubric-driven scoring, no benchmark needed | Darwin | `RUBRIC.md` |
| Human-in-the-loop checkpoints | Darwin (its key differentiator) | Step 5 below; judge's LOW-confidence flags |
| The 3 dimensions that predict *utility* not readability | SkillLens (arXiv 2605.23899) | `RUBRIC.md` D1–D3 |
| Independent judge; fresh each round; "readable ≠ useful" | SkillLens (unguided judge = 46.4%; rubric → 73.8%) | `judge.md` |
| Frozen held-out test set; never rewrite tests to match code | SkillLens / your Rule 19 | `TASKS.md` freeze discipline |

Full research write-up (verified against primary sources): see the companion report
`self-improving-skills-research.md` produced alongside this harness.

---

## The files

| File | What it is |
|---|---|
| `RUBRIC.md` | 7 scored dimensions (D1–D3 content quality from SkillLens; D4–D7 orchestration/protocol adherence from `CLAUDE.md`). 0–10 × weight → /100, with a strict-improvement ratchet. |
| `TASKS.md` | 11 frozen, held-out tasks across the routing table, each with the **expected protocol** and the **traps** a bad run falls into. The judge's ground truth. |
| `judge.md` | An **independent** sub-agent spec that scores one run transcript against the rubric. Fresh each round; evidence-bound; flags low-confidence calls. |
| `results.tsv` | The scoreboard — one row per (task, judge run). This is the number the CHANGELOG never had. |
| `runs/` | Where you save run transcripts (`<task-id>__<plugin-sha>.md`). Create as needed. |

---

## The loop (run this whenever you change the plugin)

```
0. Establish a baseline (once per task you care about)
   - Run dev-pipeline on a TASKS.md task in a normal session.
   - Save the transcript to evals/runs/<task-id>__<sha>.md.
   - Launch the judge (judge.md) → record the total in results.tsv (decision = "baseline").

1. Make ONE change to the plugin
   - Patch a skill/command/agent to fix the weakest dimension the judge flagged.
   - One change at a time, so the delta is attributable (mirrors RUBRIC.md "one change, one delta").

2. Re-run the affected tasks
   - Only the tasks the change could plausibly touch (e.g. a spec-elicitor edit → T01, T03, T08).
   - Save new transcripts under the new plugin SHA.

3. Score with FRESH judges
   - Launch judge.md as a NEW sub-agent per (task) — do not reuse a judge across old/new for the
     same task (anti-anchoring; the judge must not know which version it's reading).

4. Apply the ratchet
   - keep  if mean(new) STRICTLY > mean(old) on the shared task set → commit the change.
   - revert otherwise → `git revert` (NOT reset --hard; preserve history — your own Rule 18 spirit).
   - Log both outcomes to results.tsv (a rejected change is data too).

5. Human checkpoint (the Darwin differentiator)
   - Read the judge's "Top 2 weaknesses" and any LOW-confidence flags.
   - YOU decide whether the next change targets the same weakness or moves on.
   - The judge is ~73.8% reliable, not an oracle — for D5/D7 (gates, deploy safety), trust your
     read over a borderline score.
```

### One-line decision rule
> Keep a plugin change **iff** a fresh, independent, rubric-bound judge scores it **strictly
> higher on the same frozen task(s)** than the version before it. Everything else is `git revert`.

---

## How to invoke the judge

In a session with this repo connected:

```
Launch the skill-eval-judge agent (evals/judge.md).
Task: T03.
Transcript: evals/runs/T03__<sha>.md.
Plugin SHA: <sha>.
Score it against evals/RUBRIC.md and return the score card.
```

Do this as a **separate sub-agent / fresh context** from whatever wrote the plugin change — the
independence is the point (SkillLens: a same-context unguided judge is *worse than a coin flip*).

---

## Honest limits (so you calibrate the scoreboard correctly)

1. **The judge is ~73.8% reliable, not exact.** Treat totals as a **signal with noise**, not a
   verdict. A +0.3 delta is inside the noise; look for clear, repeated movement and read the
   evidence column, not just the number. This is why Step 5 keeps a human in the loop.
2. **Transcript scoring measures the orchestration, not the runtime.** It catches "skipped the
   conflict gate," "faked a passed review," "didn't delegate to spec-elicitor." It does **not**
   verify the user code actually built/deployed — that needs the live-sandbox layer (a future
   extension; the harness is structured to allow it: add `runs/` artifacts from real executions
   and an output-quality dimension group).
3. **Reward-hacking is possible here too.** A change can lift a score by padding a file to tick
   rubric boxes without adding executable value. The judge is told to withhold points for this,
   but you should spot-check that score gains correspond to real behaviour gains — not longer docs.
4. **The suite is small and frozen on purpose.** 11 tasks won't cover everything; add tasks as new
   failure modes appear (that's the healthy version of growth). Never edit a task to match what the
   pipeline already does — that's the Rule-19 tautology turned on the eval.

---

## Relationship to the rest of dev-pipeline

This harness is **dev-pipeline's own gates, pointed at itself.** The plugin already enforces
"validate before you accept" on *user* code (Rule 8 pre-push review, Rule 19 "tests that change
behaviour aren't proof," the `.last-reviewed-sha` ratchet). The CHANGELOG is your manual evolution
log. `evals/` closes the loop: it puts a **measured, ratcheted, independently-judged** gate in
front of changes to the **plugin itself**, so the evolution log stops being a list of *changes* and
becomes a list of *improvements*.
