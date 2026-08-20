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
echo one > "$REPO/file"
git -C "$REPO" add file
git -C "$REPO" commit -qm first
git -C "$REPO" push -qu origin feat/right

mkdir -p "$REPO/.claude"
cat > "$REPO/.claude/pipeline-state.json" <<'EOF'
{"branch":"feat/right","updatedAt":"2999-01-01T00:00:00.500Z"}
EOF
(cd "$REPO" && bash "$ROOT/tools/pipeline-pointer-valid.sh")

# Wrong branch is stale even when its timestamp is new.
cat > "$REPO/.claude/pipeline-state.json" <<'EOF'
{"branch":"feat/wrong","updatedAt":"2999-01-01T00:00:00Z"}
EOF
if (cd "$REPO" && bash "$ROOT/tools/pipeline-pointer-valid.sh"); then
  echo "FAIL: wrong-branch pointer accepted" >&2
  exit 1
fi

# Correct branch but timestamp older than HEAD is stale.
cat > "$REPO/.claude/pipeline-state.json" <<'EOF'
{"branch":"feat/right","updatedAt":"2000-01-01T00:00:00Z"}
EOF
if (cd "$REPO" && bash "$ROOT/tools/pipeline-pointer-valid.sh"); then
  echo "FAIL: old pointer accepted" >&2
  exit 1
fi

# Detached HEAD is valid only when it is exactly the pointer branch's remote SHA.
git -C "$REPO" checkout -q --detach HEAD
cat > "$REPO/.claude/pipeline-state.json" <<'EOF'
{"branch":"feat/right","updatedAt":"2999-01-01T00:00:00.500Z"}
EOF
(cd "$REPO" && bash "$ROOT/tools/pipeline-pointer-valid.sh")
echo two >> "$REPO/file"
git -C "$REPO" add file
git -C "$REPO" commit -qm detached-ahead
if (cd "$REPO" && bash "$ROOT/tools/pipeline-pointer-valid.sh"); then
  echo "FAIL: detached HEAD ahead of pointer branch accepted" >&2
  exit 1
fi

# Failed fetch plus a stale cached tracking ref is uncertainty and must fail closed.
git -C "$REPO" checkout -q feat/right
cat > "$REPO/.claude/pipeline-state.json" <<'EOF'
{"branch":"feat/right","updatedAt":"2999-01-01T00:00:00.500Z"}
EOF
git -C "$REPO" remote set-url origin "$TMP/missing-remote.git"
if (cd "$REPO" && bash "$ROOT/tools/pipeline-pointer-valid.sh"); then
  echo "FAIL: stale cached remote ref accepted after fetch failure" >&2
  exit 1
fi

echo "PASS: pointer validity rejects wrong branches and timestamps older than HEAD"