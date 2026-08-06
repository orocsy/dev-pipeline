# Review findings — d9f35da (Codex fix round on PR #14)

Base: b6d29e9..HEAD · reviewed 2026-08-06T06:07:06Z
Codex round 1: 5 P1 + 7 P2 — all addressed. Gates run clean (GATE_RC=0).

| # | Sev | File | Source | Issue | Resolution |
|---|-----|------|--------|-------|------------|
| 1 | P1 | commands/review.md, validate.md | codex | `$SRC_DIRS`/`$TEST_DIR`/`GATE_ARGS` referenced, never defined — the gate blocks could not run as written | FIXED — invocation moved to tools/run-craft-gates.sh with real repo-shape detection |
| 2 | P1 | commands/review.md | codex | baseline comparison specified in prose, zero implementing lines | FIXED — real read/write/compare keyed on gate+file:line, `--baseline-write` mode |
| 3 | P1 | commands/review.md | codex | missing individual gate templates undetected (only the dir was checked) | FIXED — per-template existence check → exit 2 |
| 4 | P1 | commands/validate.md | codex | gate results not aggregated into the Phase 8 verdict | FIXED — single GATE_RC folded into the summary |
| 5 | P2 | commands/review.md | codex | no distinct exit state for gate execution errors | FIXED — 0 clean/NA · 1 findings · 2 exec error; a gate exiting 1 with no FAIL lines is now itself an exec error |
| 6 | P2 | commands/{pr-review,fix-review,fix}.md | codex | direct PR-fix family reaches neither validate nor review | FIXED — gates wired into all three |
| 7 | P2 | commands/review.md | codex | GNU-only `grep -P` silently matched nothing on BSD grep | FIXED — three chained linear greps. NOTE: the first replacement (ERE with a bounded repeat before an alternation) HUNG ugrep 7.5 outright — worse than the bug. Caught by running it. |
| 8 | P2 | commands/review.md | codex | dependency-closure imports not resolved to repo paths | FIXED — dirname + extension/index resolution |
| 9 | P2 | hooks/session-start.sh | codex | destructive skill swap unserialized — concurrent sessions could leave NOTHING at $EC_SKILL | FIXED — lockfile + stale-lock guard + restore-on-failure |
| 10 | P2 | hooks/session-start.sh | codex | failed refresh unreported when no categories dir exists | FIXED — missing/empty is now reported explicitly |
| 11 | P2 | commands/review.md | codex | D.5 prompt used a relative category path | FIXED — absolute |
| 12 | P1 | tools/run-craft-gates.sh | self (git binary flag) | embedded NUL byte from a heredoc turned `join(" ")` into `join("\0")` — git treated the script as BINARY, so it would not diff in the PR and Codex could not review it. Latent functional bug too: multi-element proofSteps would join with NUL. Ran clean only because no repo has that config yet. | FIXED — NUL stripped; all touched files swept for NULs |
| 13 | P2 | (gate default) | self (running it) | pipeline-causality's default proofStep `test` is never found inside `pnpm test` by its own anchored matcher → 2 false positives on a correct pipeline | FIXED — runner derives the proof command from the repo lockfile |

Gate run at HEAD: 5 N/A · 2 PASS · 0 findings · 0 exec errors → GATE_RC=0.
Exit contract verified in all three states (missing dir → 2, missing template → 2, luxebook 17 findings → 1, here → 0).

Verdict: 0 open P1, 0 open P2 → BLESS.
