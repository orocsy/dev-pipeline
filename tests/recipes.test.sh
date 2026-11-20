#!/usr/bin/env bash
# recipes/recipes.json is well-formed, covers the required task types, names only
# commands that exist, and the router tables rendered from it are current.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import json, os, re, sys
root = sys.argv[1]
data = json.load(open(os.path.join(root, "recipes", "recipes.json")))
ids = [r["id"] for r in data["recipes"]]
assert len(ids) == len(set(ids)), "duplicate recipe ids"
required = {"feature", "enhancement", "prd-digest", "ui-design-round", "review-only", "test-only",
            "bug-fix", "hotfix", "docs-sync", "contract-change"}
missing = required - set(ids)
assert not missing, f"missing required recipes: {sorted(missing)}"
assert ids[-1] == "feature", "feature (full pipeline) must be the last resort"
for r in data["recipes"]:
    for k in ("id", "title", "legacy_type", "when", "flow", "short", "skips", "escalate", "done_when", "infer_from", "learned"):
        assert k in r, f"{r.get('id')}: missing {k}"
    for step in r["flow"] + [r["short"]]:
        for cmd in re.findall(r"/dev-pipeline:([a-z-]+)", step):
            assert os.path.isfile(os.path.join(root, "commands", cmd + ".md")), f"{r['id']}: no command {cmd}"
        for cmd in re.findall(r"`/([a-z-]+)", step):
            assert os.path.isfile(os.path.join(root, "commands", cmd + ".md")), f"{r['id']}: no command {cmd} (short)"
    for esc in r["escalate"]:
        target = esc.split("->")[-1].strip().split()[0] if "->" in esc else None
        assert target is None or target in ids, f"{r['id']}: escalates to unknown {target}"
unknown = set(data["infer_order"]) - set(ids)
assert not unknown, f"infer_order has unknown ids {unknown}"
print(f"ok: {len(ids)} recipes")
PY
python3 "$ROOT/tools/render-recipes.py" --check
grep -q 'Recipe: <id>' "$ROOT/CLAUDE.md"
grep -q 'PHASE −1: Recipe check' "$ROOT/commands/dev-pipeline.md"
echo "PASS: recipes"
