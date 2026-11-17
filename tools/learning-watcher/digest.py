#!/usr/bin/env python3
"""learning-watcher digest -- deterministic, size-capped summary for consolidation.

Reads events/*.jsonl, keeps the entries not yet consolidated, and writes ONE
markdown digest (default <= 24,000 chars, roughly 6k tokens). The LLM
consolidation step reads only this digest, never transcripts or the journal,
which is what caps its input tokens.

Also writes state/recipe-stats.json: per-recipe outcomes over the last 30
days (all entries, consolidated or not), used to propose recipe changes.

  digest.py --out digests/2026-11-18.md --ids-out digests/2026-11-18.ids
  digest.py --mark-consolidated digests/2026-11-18.ids
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

HOME = os.path.expanduser("~")
LW_HOME = os.environ.get("LW_HOME", os.path.join(HOME, ".claude", "learning"))


def load_events(days: int | None = None) -> list[dict]:
    out = []
    cutoff = None
    if days:
        cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%S")
    for p in sorted(glob.glob(os.path.join(LW_HOME, "events", "*.jsonl"))):
        with open(p, encoding="utf-8") as fh:
            for line in fh:
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if cutoff and (ev.get("end") or ev.get("captured", "")) < cutoff:
                    continue
                out.append(ev)
    return out


def consolidated_ids() -> set[str]:
    path = os.path.join(LW_HOME, "state", "consolidated.json")
    try:
        with open(path, encoding="utf-8") as fh:
            return set(json.load(fh).get("ids", []))
    except (FileNotFoundError, ValueError):
        return set()


def mark_consolidated(ids_file: str) -> int:
    path = os.path.join(LW_HOME, "state", "consolidated.json")
    have = consolidated_ids()
    with open(ids_file, encoding="utf-8") as fh:
        new = {l.strip() for l in fh if l.strip()}
    # keep the set bounded: ids embed offsets, not dates, so keep the newest 20k
    merged = sorted(have | new)[-20000:]
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"ids": merged, "updated": datetime.now(timezone.utc).isoformat()}, fh)
    os.replace(tmp, path)
    return len(new - have)


def recipe_of(ev: dict) -> str:
    ann = ev.get("recipe_announced") or {}
    if ann:
        return max(ann, key=ann.get)
    return ev.get("recipe_inferred") or "ad-hoc"


def recipe_stats(events: list[dict]) -> dict:
    by_session: dict[str, dict] = {}
    for ev in events:
        s = by_session.setdefault(ev["session"], {"recipes": Counter(), "announced": False, "corrections": 0,
                                                  "errors": 0, "reverts": 0, "interrupts": 0, "commits": 0,
                                                  "recaps": 0, "review": 0, "project": ev["project"]})
        r = recipe_of(ev)
        s["recipes"][r] += 1
        s["announced"] |= bool(ev.get("recipe_announced"))
        s["corrections"] += len(ev.get("corrections", []))
        s["errors"] += ev.get("errors_total", 0)
        s["reverts"] += len(ev.get("reverts", []))
        s["interrupts"] += ev.get("interrupts", 0)
        s["commits"] += len(ev.get("commits", []))
        s["recaps"] += len(ev.get("recaps", []))
        s["review"] += sum((ev.get("review_findings") or {}).values())
    stats: dict[str, dict] = {}
    for s in by_session.values():
        rid = s["recipes"].most_common(1)[0][0]
        st = stats.setdefault(rid, {"sessions": 0, "announced": 0, "corrections": 0, "errors": 0, "reverts": 0,
                                    "interrupts": 0, "commits": 0, "completed": 0, "review_findings": 0,
                                    "projects": Counter()})
        st["sessions"] += 1
        st["announced"] += int(s["announced"])
        for k in ("corrections", "errors", "reverts", "interrupts", "commits"):
            st[k] += s[k]
        st["review_findings"] += s["review"]
        st["completed"] += int(s["recaps"] > 0 or s["commits"] > 0)
        st["projects"][s["project"]] += 1
    for st in stats.values():
        n = max(st["sessions"], 1)
        st["per_session"] = {k: round(st[k] / n, 2) for k in ("corrections", "errors", "reverts", "interrupts")}
        st["completion_rate"] = round(st["completed"] / n, 2)
        st["projects"] = len(st["projects"])  # count only; names stay out of anything shared
    return stats


def build(events: list[dict], stats: dict, max_chars: int) -> str:
    projects = Counter(e["project"] for e in events)
    stack = Counter()
    skills = Counter()
    for e in events:
        stack.update(e.get("stack") or {})
        skills.update(e.get("skills") or {})
        skills.update({f"agent:{k}": v for k, v in (e.get("agents") or {}).items()})
    # recurring errors across sessions
    err = defaultdict(lambda: {"n": 0, "sessions": set(), "sample": "", "projects": set()})
    for e in events:
        for sig, n, sample in e.get("error_sigs", []):
            key = re.sub(r"`[^`]*`", lambda m: "`" + " ".join(m.group(0).strip("`").split()[:2]) + "`", sig)
            rec = err[key]
            rec["n"] += n
            rec["sessions"].add(e["session"])
            rec["projects"].add(e["project"])
            rec["sample"] = rec["sample"] or sample
    recurring = sorted(err.items(), key=lambda kv: (-len(kv[1]["sessions"]), -kv[1]["n"]))

    sections: list[tuple[str, list[str]]] = []
    first = min((e.get("start") or e["captured"]) for e in events)[:10]
    last = max((e.get("end") or e["captured"]) for e in events)[:10]
    head = [
        f"# Learning digest — {datetime.now(timezone.utc):%Y-%m-%d}",
        "",
        f"{len(events)} journal entries from {len({e['session'] for e in events})} sessions, {first} → {last}.",
        "Projects (local names; NEVER copy into a repo): " + ", ".join(f"{p} ×{n}" for p, n in projects.most_common()),
        "Stack signals: " + ", ".join(f"{k} {v}" for k, v in stack.most_common(14)),
        "",
    ]
    sections.append(("Skills and commands used", [f"- {k} ×{v}" for k, v in skills.most_common(30)] or ["- none"]))

    rows = ["| recipe | sessions | announced | completion | corrections/s | errors/s | reverts/s | interrupts/s |",
            "|---|---|---|---|---|---|---|---|"]
    for rid, st in sorted(stats.items(), key=lambda kv: -kv[1]["sessions"]):
        ps = st["per_session"]
        rows.append(f"| {rid} | {st['sessions']} | {st['announced']} | {st['completion_rate']} | {ps['corrections']} | "
                    f"{ps['errors']} | {ps['reverts']} | {ps['interrupts']} |")
    sections.append(("Recipe outcomes, last 30 days (ad-hoc = no dev-pipeline command used)", rows))

    rec_lines = []
    for sig, r in recurring[:25]:
        rec_lines.append(f"- {sig} — {r['n']}× in {len(r['sessions'])} session(s), {len(r['projects'])} project(s): \"{r['sample']}\"")
    sections.append(("Recurring problems (tool errors grouped by command)", rec_lines or ["- none"]))

    corr = []
    for e in events:
        for c in e.get("corrections", []):
            corr.append(f"- [{e['project']} · {recipe_of(e)}] \"{c}\"")
    sections.append(("User corrections (what the user had to say to put the agent right)", corr or ["- none"]))

    other = []
    for e in events:
        for r in e.get("reverts", []):
            other.append(f"- revert/reset [{e['project']}]: `{r}`")
        for d in e.get("denials", []):
            other.append(f"- declined tool call [{e['project']}]: {d}")
        if e.get("interrupts"):
            other.append(f"- interrupted ×{e['interrupts']} [{e['project']} · {recipe_of(e)}]")
        if e.get("review_findings"):
            other.append(f"- review findings [{e['project']}]: " + ", ".join(f"{k} ×{v}" for k, v in e["review_findings"].items()))
        if e.get("compactions", 0) >= 2:
            other.append(f"- {e['compactions']} context compactions in one burst [{e['project']}] (long session)")
    sections.append(("Other friction", other or ["- none"]))

    wins = []
    for e in events:
        for r in e.get("recaps", []):
            wins.append(f"- [{e['project']} · {recipe_of(e)}] {r}")
        for g in e.get("green_after_red", []):
            wins.append(f"- green after red [{e['project']}]: {g}")
        for p in e.get("praise", []):
            wins.append(f"- user praise [{e['project']}]: \"{p}\"")
    sections.append(("What went well (recaps, fixes that turned tests green, praise)", wins or ["- none"]))

    commits = []
    for e in events:
        for c in e.get("commits", []):
            commits.append(f"- [{e['project']}] {c}")
    sections.append(("Commit subjects (what actually shipped)", commits or ["- none"]))

    # Fit to budget: trim the largest section by 20% at a time, keep every heading.
    budget = max_chars - len("\n".join(head)) - 400
    full = {t: len(ls) for t, ls in sections}

    def size(secs):
        return sum(len(t) + 6 + sum(len(l) + 1 for l in ls) for t, ls in secs)

    while size(sections) > budget:
        shrinkable = [k for k, (_, ls) in enumerate(sections) if len(ls) > 3]
        if not shrinkable:
            break
        i = max(shrinkable, key=lambda k: sum(len(l) for l in sections[k][1]))
        t, ls = sections[i]
        sections[i] = (t, ls[: max(3, int(len(ls) * 0.8))])
    sections = [(t, ls + ([f"- … {full[t] - len(ls)} more not shown"] if len(ls) < full[t] else []))
                for t, ls in sections]
    body = head[:]
    for t, ls in sections:
        body += [f"## {t}", ""] + ls + [""]
    text = "\n".join(body)
    return text[:max_chars]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out")
    ap.add_argument("--ids-out")
    ap.add_argument("--max-chars", type=int, default=24000)
    ap.add_argument("--max-entries", type=int, default=400, help="oldest pending entries first")
    ap.add_argument("--mark-consolidated")
    a = ap.parse_args(argv)
    if a.mark_consolidated:
        n = mark_consolidated(a.mark_consolidated)
        print(f"marked {n} entr{'y' if n == 1 else 'ies'} consolidated")
        return 0
    done = consolidated_ids()
    pending = [e for e in load_events() if e["id"] not in done]
    pending.sort(key=lambda e: e.get("end") or e["captured"])
    pending = pending[: a.max_entries]
    stats = recipe_stats(load_events(days=30))
    os.makedirs(os.path.join(LW_HOME, "state"), exist_ok=True)
    with open(os.path.join(LW_HOME, "state", "recipe-stats.json"), "w", encoding="utf-8") as fh:
        json.dump({"generated": datetime.now(timezone.utc).isoformat(), "window_days": 30, "recipes": stats}, fh, indent=1)
    if not pending:
        print("0 pending entries")
        return 0
    text = build(pending, stats, a.max_chars)
    if a.out:
        os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(text)
    else:
        print(text)
    if a.ids_out:
        with open(a.ids_out, "w", encoding="utf-8") as fh:
            fh.write("\n".join(e["id"] for e in pending) + "\n")
    print(f"{len(pending)} pending entries -> {a.out or 'stdout'} ({len(text)} chars)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
