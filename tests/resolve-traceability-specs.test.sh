#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REMOTE="$TMP/remote.git"
REPO="$TMP/repo"
git init -q --bare "$REMOTE"
git clone -q "$REMOTE" "$REPO"
git -C "$REPO" config user.email test@example.test
git -C "$REPO" config user.name test
git -C "$REPO" switch -q -c feat/right
mkdir -p "$REPO/docs/right" "$REPO/docs/wrong" "$REPO/.claude"
cat > "$REPO/docs/right/EXECUTION.md" <<'EOF'
Status: complete.
Branch: `feat/right`
EOF
touch "$REPO/docs/right/MIU_BREAKDOWN.md" "$REPO/docs/right/task_plan.md"
cat > "$REPO/docs/wrong/EXECUTION.md" <<'EOF'
Status: active.
Branch: `feat/wrong`
EOF
touch "$REPO/docs/wrong/MIU_BREAKDOWN.md" "$REPO/docs/wrong/SPEC.md"
git -C "$REPO" add docs
git -C "$REPO" commit -qm init
git -C "$REPO" push -qu origin feat/right

# Same-branch but stale pointer attempts to inject the wrong breakdown.
cat > "$REPO/.claude/pipeline-state.json" <<EOF
{"task":"wrong","branch":"feat/right","updatedAt":"2000-01-01T00:00:00Z","docs":{"breakdown":"docs/wrong/MIU_BREAKDOWN.md"}}
EOF
OUTPUT="$(cd "$REPO" && bash "$ROOT/tools/resolve-traceability-specs.sh")"
grep -Fq 'docs/right/EXECUTION.md' <<<"$OUTPUT"
grep -Fq 'docs/right/MIU_BREAKDOWN.md' <<<"$OUTPUT"
grep -Fq 'docs/right/task_plan.md' <<<"$OUTPUT"
if grep -Fq 'docs/wrong/' <<<"$OUTPUT"; then
  echo "FAIL: traceability included the stale pointer's unrelated feature" >&2
  exit 1
fi
[[ "$(printf '%s\n' "$OUTPUT" | sort -u | wc -l | tr -d ' ')" == "3" ]]

echo "PASS: traceability specs are unique and confined to the branch-matched feature directory"

# A documented single-MIU fix may have EXECUTION + ISSUE and no breakdown.
FIX_REPO="$TMP/fix-repo"
FIX_REMOTE="$TMP/fix-remote.git"
git init -q --bare "$FIX_REMOTE"
git clone -q "$FIX_REMOTE" "$FIX_REPO"
git -C "$FIX_REPO" config user.email test@example.test
git -C "$FIX_REPO" config user.name test
git -C "$FIX_REPO" switch -q -c fix/one
mkdir -p "$FIX_REPO/docs/one"
cat > "$FIX_REPO/docs/one/EXECUTION.md" <<'EOF'
Status: implementing one fix.
Branch: `fix/one`
EOF
touch "$FIX_REPO/docs/one/ISSUE.md"
git -C "$FIX_REPO" add docs
git -C "$FIX_REPO" commit -qm fix
git -C "$FIX_REPO" push -qu origin fix/one
FIX_OUTPUT="$(cd "$FIX_REPO" && bash "$ROOT/tools/resolve-traceability-specs.sh")"
grep -Fq 'docs/one/EXECUTION.md' <<<"$FIX_OUTPUT"
grep -Fq 'docs/one/ISSUE.md' <<<"$FIX_OUTPUT"
if grep -qi 'breakdown' <<<"$FIX_OUTPUT"; then
  echo "FAIL: no-breakdown fix flow invented a breakdown" >&2
  exit 1
fi

echo "PASS: traceability supports a tracked single-MIU fix without a breakdown"