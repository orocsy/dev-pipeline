#!/usr/bin/env python3
"""Render recipes/recipes.json into the router's tables.

  python3 tools/render-recipes.py          # rewrite the generated blocks
  python3 tools/render-recipes.py --check  # exit 1 if a block is stale (tests/recipes.test.sh)

Blocks live between `<!-- recipes:<name>:begin -->` and `<!-- recipes:<name>:end -->`:
  CLAUDE.md                      compact  (recipe | when | short flow; commands shown without the dev-pipeline: prefix)
  skills/skill-router/SKILL.md   full     (+ skips, escalate, done when, learned notes)
"""
from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECIPES = os.path.join(ROOT, "recipes", "recipes.json")


def cell(s: str) -> str:
    return s.replace("|", "\\|").replace("\n", " ")


def flow(r: dict) -> str:
    return " → ".join(r["flow"])


def compact(data: dict) -> str:
    rows = ["| Recipe | When | Flow |", "|---|---|---|"]
    for r in data["recipes"]:
        rows.append(f"| `{r['id']}` | {cell(r['when'])} | {cell(r.get('short') or flow(r))} |")
    return "\n".join(rows)


def full(data: dict) -> str:
    out = ["Selection:", ""]
    out += [f"{i}. {s}" for i, s in enumerate(data["selection"], 1)]
    out += ["", "| Recipe (legacy type) | Flow | Skips | Escalate | Done when |", "|---|---|---|---|---|"]
    for r in data["recipes"]:
        esc = "; ".join(r.get("escalate") or []) or "—"
        out.append(f"| `{r['id']}` ({r['legacy_type']}) | {cell(flow(r))} | {cell(r['skips'])} | {cell(esc)} | {cell(r['done_when'])} |")
    learned = [(r["id"], n) for r in data["recipes"] for n in r.get("learned") or []]
    if learned:
        out += ["", "Learned notes (added by the learning watcher, merged by a person):", ""]
        out += [f"- `{rid}` ({n.get('date', '?')}, {n.get('evidence', '?')}): {n.get('note', '')}" for rid, n in learned]
    return "\n".join(out)


TARGETS = [
    ("CLAUDE.md", "compact", compact),
    (os.path.join("skills", "skill-router", "SKILL.md"), "full", full),
]


def main() -> int:
    check = "--check" in sys.argv
    with open(RECIPES, encoding="utf-8") as fh:
        data = json.load(fh)
    stale = []
    for rel, name, fn in TARGETS:
        path = os.path.join(ROOT, rel)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        rx = re.compile(rf"(<!-- recipes:{name}:begin -->\n)(?:.*?\n)?(<!-- recipes:{name}:end -->)", re.S)
        if not rx.search(text):
            print(f"{rel}: no recipes:{name} block", file=sys.stderr)
            return 1
        new = rx.sub(lambda m: m.group(1) + fn(data) + "\n" + m.group(2), text)
        if new != text:
            stale.append(rel)
            if not check:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(new)
    if check and stale:
        print("stale recipe tables: " + ", ".join(stale) + " — run python3 tools/render-recipes.py", file=sys.stderr)
        return 1
    print("recipe tables " + ("up to date" if not stale else "rewritten: " + ", ".join(stale)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
