#!/usr/bin/env python3
"""
project-detector eval scorer (Class 1 — deterministic).

Scores a candidate project-profile.json (what the skill produced for a fixture case)
against the known-correct expected/<case>.json. Produces a per-field breakdown and a
hard accuracy %, so a change to skills/project-detector/SKILL.md can be ratcheted:
keep only if the score strictly rises on the SAME cases.

Expected-file convention (see expected/*.json):
  - Top-level scalar/array keys      -> HARD scored.
      * strings: case-insensitive exact match.
      * arrays : set equality (order-independent), case-insensitive.
      * bools  : exact.
  - "_soft": { field: "alt1|alt2" }  -> SOFT scored. The candidate value (string or any
      element of a candidate array) must match one alternative (case-insensitive substring/
      regex-alt). A soft miss is reported but counts at half weight, not a hard fail —
      these are the genuinely-debatable fields (frameworkVersion phrasing, vite-vs-react).
  - "_ignore": [ ... ]               -> not scored (timestamps, free-form, downstream-only).

Scoring:
    hard_score  = correct_hard_fields / total_hard_fields
    soft_score  = soft_matches / total_soft_fields           (0 if none)
    total       = 100 * (HARD_WEIGHT*hard_score + SOFT_WEIGHT*soft_score)
                  with weights renormalised if a case has no soft fields.

Usage:
    # score one candidate against one expected file
    python3 score.py --expected expected/01-next-vercel-prisma.json --candidate /path/to/profile.json

    # score a whole directory of candidates named <case>.json against expected/
    python3 score.py --batch runs/<plugin-sha>/      # each file matched to expected/ by name

    # self-test the scorer with a deliberately-wrong candidate
    python3 score.py --selftest
"""
import argparse, json, os, re, sys, glob

HARD_WEIGHT = 0.85
SOFT_WEIGHT = 0.15


def _norm(v):
    return v.strip().lower() if isinstance(v, str) else v


def _as_set(v):
    if v is None:
        return set()
    if isinstance(v, list):
        return {_norm(x) for x in v}
    return {_norm(v)}


def _soft_match(candidate_val, alt_spec):
    """alt_spec is like 'next|nestjs|turborepo'. Candidate matches if any of its
    string values contains/equals any alternative (case-insensitive)."""
    alts = [a.strip().lower() for a in str(alt_spec).split("|")]
    cand_strings = []
    if isinstance(candidate_val, list):
        cand_strings = [str(x).lower() for x in candidate_val]
    elif candidate_val is not None:
        cand_strings = [str(candidate_val).lower()]
    for cs in cand_strings:
        for a in alts:
            if a == "none" or a == "null":
                if candidate_val in (None, "none", "null", "", []):
                    return True
            if a and (a == cs or a in cs or cs in a):
                return True
    # also allow explicit none/null match when candidate truly absent
    if candidate_val in (None, "", []) and any(a in ("none", "null") for a in alts):
        return True
    return False


def score_case(expected, candidate):
    soft = expected.get("_soft", {}) or {}
    ignore = set(expected.get("_ignore", []) or [])
    hard_keys = [k for k in expected.keys()
                 if k not in ("_soft", "_ignore") and k not in ignore]

    rows = []  # (field, kind, expected, got, result)  result in {OK, MISS, SOFT_OK, SOFT_MISS}
    hard_total = hard_correct = 0
    soft_total = soft_correct = 0

    for k in hard_keys:
        exp = expected[k]
        got = candidate.get(k, None)
        if isinstance(exp, list):
            ok = _as_set(exp) == _as_set(got)
        elif isinstance(exp, bool):
            ok = (exp == got)
        else:
            ok = (_norm(exp) == _norm(got))
        hard_total += 1
        hard_correct += 1 if ok else 0
        rows.append((k, "hard", exp, got, "OK" if ok else "MISS"))

    for k, alt in soft.items():
        got = candidate.get(k, None)
        ok = _soft_match(got, alt)
        soft_total += 1
        soft_correct += 1 if ok else 0
        rows.append((k, "soft", alt, got, "SOFT_OK" if ok else "SOFT_MISS"))

    hard_score = (hard_correct / hard_total) if hard_total else 1.0
    soft_score = (soft_correct / soft_total) if soft_total else None

    if soft_score is None:
        total = 100.0 * hard_score
    else:
        total = 100.0 * (HARD_WEIGHT * hard_score + SOFT_WEIGHT * soft_score)

    return {
        "hard_total": hard_total, "hard_correct": hard_correct,
        "soft_total": soft_total, "soft_correct": soft_correct,
        "hard_pct": round(100 * hard_score, 1),
        "soft_pct": (round(100 * soft_score, 1) if soft_score is not None else None),
        "total": round(total, 1),
        "rows": rows,
    }


def print_report(case_name, res):
    print(f"\n## {case_name}")
    print(f"{'field':<16}{'kind':<6}{'expected':<28}{'got':<28}result")
    print("-" * 90)
    for f, kind, exp, got, result in res["rows"]:
        mark = {"OK": "✓", "MISS": "✗", "SOFT_OK": "~✓", "SOFT_MISS": "~✗"}[result]
        print(f"{f:<16}{kind:<6}{str(exp):<28.27}{str(got):<28.27}{mark} {result}")
    sp = f" | soft {res['soft_correct']}/{res['soft_total']} ({res['soft_pct']}%)" if res["soft_total"] else ""
    print(f"  → hard {res['hard_correct']}/{res['hard_total']} ({res['hard_pct']}%){sp}"
          f"  ||  TOTAL {res['total']}/100")
    return res["total"]


def load(p):
    with open(p) as f:
        return json.load(f)


def run_batch(expected_dir, cand_dir):
    totals = []
    for exp_path in sorted(glob.glob(os.path.join(expected_dir, "*.json"))):
        name = os.path.basename(exp_path)
        cand_path = os.path.join(cand_dir, name)
        if not os.path.exists(cand_path):
            print(f"\n## {name}\n  (no candidate at {cand_path} — SKIPPED)")
            continue
        res = score_case(load(exp_path), load(cand_path))
        totals.append(print_report(name, res))
    if totals:
        print(f"\n=== MEAN over {len(totals)} cases: {round(sum(totals)/len(totals),1)}/100 ===")
    return totals


def selftest(here):
    """Score a deliberately-wrong candidate for case 01 to prove the scorer discriminates."""
    exp = load(os.path.join(here, "expected", "01-next-vercel-prisma.json"))
    perfect = {"language": "typescript", "runtime": "node", "framework": "next",
               "router": "app", "monorepo": False, "testFrameworks": ["playwright", "vitest"],
               "linter": "eslint", "formatter": "prettier", "orm": "prisma", "db": "postgres",
               "deployTargets": ["vercel"], "frameworkVersion": "15.x"}
    wrong = {"language": "javascript", "runtime": "node", "framework": "react",
             "router": "pages", "monorepo": True, "testFrameworks": ["jest"],
             "linter": "biome", "formatter": "prettier", "orm": "drizzle", "db": "mysql",
             "deployTargets": ["netlify"], "frameworkVersion": "14"}
    print("### SELF-TEST: perfect candidate (expect 100)")
    p = print_report("01 perfect", score_case(exp, perfect))
    print("\n### SELF-TEST: wrong candidate (expect low)")
    w = print_report("01 wrong", score_case(exp, wrong))
    print(f"\nself-test ok: perfect={p}  wrong={w}  (perfect must be 100 and > wrong)")
    assert p == 100.0, "perfect candidate should score 100"
    assert w < p, "wrong candidate should score below perfect"
    print("ASSERTIONS PASSED")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--expected")
    ap.add_argument("--candidate")
    ap.add_argument("--batch", help="dir of candidate <case>.json files; matched to expected/ by name")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        selftest(here); return
    if args.batch:
        run_batch(os.path.join(here, "expected"), args.batch); return
    if args.expected and args.candidate:
        print_report(os.path.basename(args.expected), score_case(load(args.expected), load(args.candidate)))
        return
    ap.print_help(); sys.exit(1)


if __name__ == "__main__":
    main()
