#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
HOME_DIR="$TMP/home"
mkdir -p "$REPO/docs/right-feature" "$REPO/docs/newer-but-wrong" "$HOME_DIR/.claude/skills/engineering-craft/categories"

git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.test
git -C "$REPO" config user.name test
git -C "$REPO" switch -q -c feat/right-branch

cat > "$REPO/docs/right-feature/EXECUTION.md" <<'EOF'
# Right Feature Execution
Status: implementation complete; PR green and awaiting merge.
Branch: `feat/right-branch`.

**Current phase:** `deliver`.

**Current/next MIU:** none. MIUs 1–9 are complete.
EOF

# Newer and lexically later on purpose: filename/newest-file fallback must NOT select it.
cat > "$REPO/docs/newer-but-wrong/zzz-execution.md" <<'EOF'
# Wrong Feature Execution
Status: implementation active.
Branch: `feat/wrong-branch`.

**Current phase:** `implement`.

**Current/next MIU:** P1.
EOF

git -C "$REPO" add docs
git -C "$REPO" commit -qm init

OUTPUT="$(cd "$REPO" && HOME="$HOME_DIR" bash "$ROOT/hooks/session-start.sh")"

grep -Fq 'TRACKED HANDOFF: branch=feat/right-branch phase=deliver' <<<"$OUTPUT"
grep -Fq 'MIUs 1–9 are complete' <<<"$OUTPUT"
grep -Fq 'source=docs/right-feature/EXECUTION.md' <<<"$OUTPUT"
if grep -Fq 'P1' <<<"$OUTPUT"; then
  echo "FAIL: selected the unrelated newest plan" >&2
  exit 1
fi

# The hook may start below repository root; tracked handoff resolution stays rooted at git top-level.
SUBDIR_OUTPUT="$(cd "$REPO/docs" && HOME="$HOME_DIR" bash "$ROOT/hooks/session-start.sh")"
grep -Fq 'TRACKED HANDOFF: branch=feat/right-branch phase=deliver' <<<"$SUBDIR_OUTPUT"

# Duplicate branch declarations fail closed and MUST NOT fall through to pointer state.
mkdir -p "$REPO/docs/duplicate" "$REPO/.claude"
cat > "$REPO/docs/duplicate/EXECUTION.md" <<'EOF'
Status: duplicate.
Branch: `feat/right-branch`.
EOF
cat > "$REPO/.claude/pipeline-state.json" <<'EOF'
{"task":"newer-but-wrong","branch":"feat/right-branch","phase":"implement","currentMiu":"P1","updatedAt":"2999-01-01T00:00:00Z"}
EOF
AMBIGUOUS_OUTPUT="$(cd "$REPO" && HOME="$HOME_DIR" bash "$ROOT/hooks/session-start.sh")"
grep -Fq 'TRACKED HANDOFF AMBIGUOUS' <<<"$AMBIGUOUS_OUTPUT"
if grep -Fq 'POINTER-ONLY PIPELINE' <<<"$AMBIGUOUS_OUTPUT"; then
  echo "FAIL: ambiguous tracked handoff fell through to pointer" >&2
  exit 1
fi
rm -rf "$REPO/docs/duplicate" "$REPO/.claude"

echo "PASS: SessionStart resolved the branch-matched tracked handoff without a pointer"

# Planning/main flow: a VALID pointer may supply the exact task when no execution doc
# declares the current branch yet. SessionStart must still surface the TRACKED handoff.
REMOTE="$TMP/planning-remote.git"
PLAN_REPO="$TMP/planning-repo"
git init -q --bare "$REMOTE"
git clone -q "$REMOTE" "$PLAN_REPO"
git -C "$PLAN_REPO" config user.email test@example.test
git -C "$PLAN_REPO" config user.name test
git -C "$PLAN_REPO" switch -q -c main
mkdir -p "$PLAN_REPO/docs/planning-task" "$PLAN_REPO/.claude"
cat > "$PLAN_REPO/docs/planning-task/EXECUTION.md" <<'EOF'
# Planning Task
Status: requirements ready.

**Current phase:** `plan`.

**Current/next MIU:** none; architecture approval required.
EOF
git -C "$PLAN_REPO" add docs
git -C "$PLAN_REPO" commit -qm planning
git -C "$PLAN_REPO" push -qu origin main
cat > "$PLAN_REPO/.claude/pipeline-state.json" <<'EOF'
{"task":"planning-task","branch":"main","updatedAt":"2999-01-01T00:00:00.500Z"}
EOF
PLAN_OUTPUT="$(cd "$PLAN_REPO" && HOME="$HOME_DIR" bash "$ROOT/hooks/session-start.sh")"
grep -Fq 'TRACKED HANDOFF: branch=main phase=plan status=requirements ready.' <<<"$PLAN_OUTPUT"

echo "PASS: SessionStart used a validated pointer only to locate a tracked planning handoff"

# Pointer task traversal cannot escape docs/ even when the pointer is otherwise valid.
mkdir -p "$PLAN_REPO/outside"
cat > "$PLAN_REPO/outside/EXECUTION.md" <<'EOF'
Status: outside.
EOF
cat > "$PLAN_REPO/.claude/pipeline-state.json" <<'EOF'
{"task":"../outside","branch":"main","phase":"implement","currentMiu":"P1","updatedAt":"2999-01-01T00:00:00.500Z"}
EOF
TRAVERSAL_OUTPUT="$(cd "$PLAN_REPO" && HOME="$HOME_DIR" bash "$ROOT/hooks/session-start.sh")"
if grep -Fq 'outside/EXECUTION.md' <<<"$TRAVERSAL_OUTPUT"; then
  echo "FAIL: SessionStart accepted a task path outside docs/" >&2
  exit 1
fi