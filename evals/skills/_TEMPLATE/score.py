#!/usr/bin/env python3
"""
Generic per-skill scorer STUB (Class 1 / Class 3).

Two scoring modes are provided; pick one for your skill and delete the other.
For the field-match reference implementation, see ../project-detector/score.py — copy it if your
skill emits a structured profile/spec and you want hard field-level matching with soft fields.

  MODE A — field-match   : candidate JSON vs expected JSON, hard/soft/ignore keys (see project-detector).
  MODE B — detection TP/FP: for skills that FLAG things (e.g. cross-file-reasoning). expected =
           {"should_catch":[...], "should_not_flag":[...]}, candidate = {"flagged":[...]}.
           Scores precision/recall/F1 over the flag sets.

Usage:
    python3 score.py --batch runs/<plugin-sha>/      # each <case>.json matched to expected/ by name
    python3 score.py --selftest
"""
import argparse, json, os, glob


# ───────────────────────── MODE B: detection TP/FP ─────────────────────────
def score_detection(expected, candidate):
    should_catch = {x.lower() for x in expected.get("should_catch", [])}
    should_not   = {x.lower() for x in expected.get("should_not_flag", [])}
    flagged      = {x.lower() for x in candidate.get("flagged", [])}

    tp = len(flagged & should_catch)
    fn = len(should_catch - flagged)
    fp = len(flagged & should_not) + len(flagged - should_catch - should_not)

    precision = tp / (tp + fp) if (tp + fp) else (1.0 if tp == 0 and fp == 0 else 0.0)
    recall    = tp / (tp + fn) if (tp + fn) else 1.0
    f1        = (2 * precision * recall / (precision + recall)) if (precision + recall) else 0.0
    return {
        "tp": tp, "fp": fp, "fn": fn,
        "precision": round(100 * precision, 1),
        "recall": round(100 * recall, 1),
        "total": round(100 * f1, 1),   # F1 is the ratchet number
    }


def print_detection(name, r):
    print(f"\n## {name}")
    print(f"  TP={r['tp']} FP={r['fp']} FN={r['fn']}  "
          f"precision={r['precision']}% recall={r['recall']}%  ||  F1 TOTAL {r['total']}/100")
    return r["total"]


def load(p):
    with open(p) as f:
        return json.load(f)


def run_batch(expected_dir, cand_dir):
    totals = []
    for exp_path in sorted(glob.glob(os.path.join(expected_dir, "*.json"))):
        name = os.path.basename(exp_path)
        cand_path = os.path.join(cand_dir, name)
        if not os.path.exists(cand_path):
            print(f"\n## {name}\n  (no candidate at {cand_path} — SKIPPED)"); continue
        totals.append(print_detection(name, score_detection(load(exp_path), load(cand_path))))
    if totals:
        print(f"\n=== MEAN over {len(totals)} cases: {round(sum(totals)/len(totals),1)}/100 ===")
    return totals


def selftest():
    exp = {"should_catch": ["env-var-MISSING", "route-mismatch"], "should_not_flag": ["style-nit"]}
    perfect = {"flagged": ["env-var-MISSING", "route-mismatch"]}
    sloppy  = {"flagged": ["env-var-MISSING", "style-nit"]}  # 1 miss + 1 false positive
    p = print_detection("perfect", score_detection(exp, perfect))
    s = print_detection("sloppy",  score_detection(exp, sloppy))
    assert p == 100.0 and s < p, "selftest failed"
    print("\nASSERTIONS PASSED (perfect=100 > sloppy)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    if a.selftest:
        selftest()
    elif a.batch:
        run_batch(os.path.join(here, "expected"), a.batch)
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
