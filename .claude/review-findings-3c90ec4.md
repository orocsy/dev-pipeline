# Review findings — 3c90ec4 (fix/craft-gates-fire-automatically)

Base: b6d29e9..HEAD · 5 files, +231/-3 · reviewed 2026-08-06T03:58:47Z

Triggers fired (STEP 1.5): verification-integrity · progressive-degradation ·
collected-constraint · tooling-footguns. Dependency closure surfaced the sibling
gate-commands family (validate/deliver/pr-review/fix-review).

| # | Severity | File:Line | Reviewer | Issue | Resolution |
|---|----------|-----------|----------|-------|------------|
| 1 | P1 | templates/*.template.mjs | STEP 1.7 dogfood | All 7 gates exited 1 when their target was absent (no .github/workflows, no .ts, no config) — byte-identical to "violations found". A false RED; as specified in STEP 1.7 this would hard-block every repo lacking the surface. | FIXED — engineering-craft 1296bc0: absent target → exit 0 + "NOT APPLICABLE — …". Verified both directions (7 N/A cases exit 0; luxebook/nutribuddy/coachflow real defects still exit 1). |
| 2 | P2 | commands/validate.md | D.5 external-review-class (family) | STEP 1.7 added to review.md only. validate.md does NOT invoke review — it is a peer gate chain — so the gates never fire on the validate-then-commit path. Textbook family-addition: added a member without checking the siblings. | FIXED — validate.md STEP 2.7 added, referencing review STEP 1.7 for severity/baseline so the two cannot drift. |
| 3 | P3 | commands/review.md:105-134 | verification-integrity | The new triggers match their own documentation: a doc that merely *mentions* `<form` or `test.skip(` fires them. Self-matching is why this diff showed hits for progressive-degradation and collected-constraint. | ACCEPTED — cost is a spurious category load (cheap); the alternative, path-excluding `commands/*.md`, would blind the greps to real changes in shipped docs. |
| 4 | P3 | commands/review.md:127 | deep | `grep -P` (PCRE lookahead in the `as T` trigger) is unavailable on macOS/BSD grep; that one line silently matches nothing there. | ACCEPTED for now — degrades to a missed trigger, not a false pass; the D.5 reviewer covers the same class by prompt. Noted for a follow-up rewrite without lookahead. |

Gate results on this repo: pipeline-causality N/A · form-degradation clean ·
skip-policy clean · trust-boundary N/A · catalog-integrity PASS (12 frontmatter warnings,
pre-existing deploy-delivery rules).

Verdict: 0 open P1, 0 open P2 → BLESS.
