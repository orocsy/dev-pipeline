# SKILL_EVAL · project-detector

**Class:** 1 — Deterministic (SkillOpt-style benchmark; the skill has a checkable correct answer).
**Skill under test:** `skills/project-detector/SKILL.md`
**What "good" means:** given a repo, the emitted `project-profile.json` correctly names the stack,
structure, and deploy targets — the downstream pipeline trusts these fields and must not re-ask.

---

## How it's scored

Primarily **programmatic** (a hard number), with a thin rubric only for the parts a diff can't judge.

### Programmatic (the score that ratchets) — `score.py`
- `cases/<id>/` is a mini fixture repo. `expected/<id>.json` is its known-correct profile.
- The skill is run on each fixture; its output profile is saved to `runs/<plugin-sha>/<id>.json`.
- `python3 score.py --batch runs/<plugin-sha>/` produces per-case + mean totals.
- **Hard fields** (top-level keys in `expected/`): exact match (strings case-insensitive; arrays
  set-equal). **Soft fields** (`_soft`): defensible alternatives, scored leniently. **`_ignore`**:
  not scored (timestamps, downstream-only fields).
- Score = `100 × (0.85·hard + 0.15·soft)`.

### Thin rubric (human/judge, not auto-scored) — only two things the diff can't see
1. **Ambiguity handling.** When a field is genuinely unpinnable (e.g. Node version not in
   `package.json`), did the skill emit **one targeted question** after detection rather than a
   generic "what stack?" — per the skill's own Output Contract? (Pass/Fail note.)
2. **No over-asking.** Did it avoid asking for anything it *could* have detected? (Pass/Fail note.)

These two are logged as notes on the run, not folded into the number — they rarely change and a
regression on them is obvious.

---

## Cases (frozen — grow, don't edit to match output)

| id | fixture | exercises |
|----|---------|-----------|
| 01 | Next.js App Router + Vercel + Prisma/Postgres + Vitest + Playwright + eslint/prettier | the full happy path; multi-signal repo |
| 02 | Vite + React SPA (no `next`) + Netlify + Vitest | react-without-next branch; vite-vs-react soft call |
| 03 | NestJS + Fly.io + Drizzle + Jest | backend framework; fly target; drizzle ORM |
| 04 | Turborepo monorepo (pnpm): web(Next/Vercel) + api(Nest/Fly) | monorepo detection; multi-target |
| 05 | Python FastAPI + Dockerfile | non-Node language; generic-docker target wording |
| 06 | Rust + docker-compose | non-Node; compose-vs-docker soft call; framework=none |

**Coverage intent:** every major branch of the skill's Detection Order + both deploy-detection
steps. Add a case whenever the skill misses a real repo in the wild (that's the healthy growth);
never relax an `expected/` value just because the skill currently disagrees (Rule-19 tautology).

---

## How to run a real baseline / round

```
# 1. Produce candidate outputs by running the skill on each fixture.
#    (In a session: point dev-pipeline / project-detector at cases/<id>/ and save its
#     emitted project-profile.json to runs/<plugin-sha>/<id>.json — same basename as expected/.)

# 2. Score the batch.
python3 score.py --batch runs/<plugin-sha>/

# 3. Log mean + per-case to results.tsv with the plugin SHA.

# 4. Ratchet: after editing project-detector/SKILL.md, re-run the SAME cases; keep only if the
#    mean STRICTLY rises (and no individual case regresses without a logged reason). Else git revert.

# 5. Roll up: a kept change should also be checked at the macro layer — run evals/TASKS.md T01/T02
#    (both start at Phase 0 where this skill fires) to confirm the orchestration didn't regress.
```

Self-check the scorer any time: `python3 score.py --selftest` (asserts perfect=100 > wrong).

---

## Known soft edges (so you don't chase false regressions)
- `framework` for a Vite-React app: `"react"` and `"vite"` are both defensible → soft.
- `deployTargets` wording: `"docker"` vs `"generic docker"`, `"docker-compose"` vs `"local docker
  compose"` → soft. If you want these hard, pin one canonical token in the skill's Output Contract
  first, then tighten `expected/`.
- Monorepo per-package `framework`/`packages` shape: the skill's contract leaves this list-shaped;
  scored soft until the contract pins an exact schema.
