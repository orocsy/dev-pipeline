#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/docs/catalog-category-expansion" "$REPO/docs/wrong-newer-feature"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.test
git -C "$REPO" config user.name test
git -C "$REPO" switch -q -c feat/catalog-category-design

cat > "$REPO/docs/catalog-category-expansion/EXECUTION.md" <<'EOF'
Status: complete.
Branch: `feat/catalog-category-design`
EOF
touch "$REPO/docs/catalog-category-expansion/MIU_BREAKDOWN.md"

cat > "$REPO/docs/wrong-newer-feature/zzz-execution.md" <<'EOF'
Status: active.
Branch: `feat/wrong`.
Previous Branch: `feat/catalog-category-design`.
EOF
touch "$REPO/docs/wrong-newer-feature/zzz-miu-breakdown.md"

EXECUTION="$(cd "$REPO" && bash "$ROOT/tools/resolve-feature-doc.sh" execution catalog-category-expansion feat/catalog-category-design)"
BREAKDOWN="$(cd "$REPO" && bash "$ROOT/tools/resolve-feature-doc.sh" breakdown catalog-category-expansion feat/catalog-category-design)"
[[ "$EXECUTION" == "docs/catalog-category-expansion/EXECUTION.md" ]]
[[ "$BREAKDOWN" == "docs/catalog-category-expansion/MIU_BREAKDOWN.md" ]]

# Task slug deliberately absent: branch declaration must still recover both siblings.
BRANCH_BREAKDOWN="$(cd "$REPO" && bash "$ROOT/tools/resolve-feature-doc.sh" breakdown missing-task feat/catalog-category-design)"
[[ "$BRANCH_BREAKDOWN" == "docs/catalog-category-expansion/MIU_BREAKDOWN.md" ]]

# A stale task naming a real directory must never override the current branch.
STALE_TASK_BREAKDOWN="$(cd "$REPO" && bash "$ROOT/tools/resolve-feature-doc.sh" breakdown wrong-newer-feature feat/catalog-category-design)"
[[ "$STALE_TASK_BREAKDOWN" == "docs/catalog-category-expansion/MIU_BREAKDOWN.md" ]]

# Duplicate authoritative branch declarations are corruption, not a tie to break by path.
mkdir -p "$REPO/docs/duplicate"
cat > "$REPO/docs/duplicate/EXECUTION.md" <<'EOF'
Status: duplicate.
Branch: `feat/catalog-category-design`.
EOF
if (cd "$REPO" && bash "$ROOT/tools/resolve-feature-doc.sh" execution "" feat/catalog-category-design >/dev/null 2>&1); then
	echo "FAIL: duplicate branch declarations did not fail closed" >&2
	exit 1
fi

# Multiple exact Branch fields inside one file also fail closed.
rm "$REPO/docs/duplicate/EXECUTION.md"
cat >> "$REPO/docs/catalog-category-expansion/EXECUTION.md" <<'EOF'
Branch: `feat/other`
EOF
if (cd "$REPO" && bash "$ROOT/tools/resolve-feature-doc.sh" execution "" feat/catalog-category-design >/dev/null 2>&1); then
	echo "FAIL: conflicting Branch fields inside one doc did not fail closed" >&2
	exit 1
fi

# Malformed metadata in an UNRELATED historical feature does not block the current branch.
sed -i.bak '$d' "$REPO/docs/catalog-category-expansion/EXECUTION.md" && rm -f "$REPO/docs/catalog-category-expansion/EXECUTION.md.bak"
cat >> "$REPO/docs/wrong-newer-feature/zzz-execution.md" <<'EOF'
Branch: `feat/another-old-branch`
EOF
CURRENT="$(cd "$REPO" && bash "$ROOT/tools/resolve-feature-doc.sh" execution "" feat/catalog-category-design)"
[[ "$CURRENT" == "docs/catalog-category-expansion/EXECUTION.md" ]]

# Task lookup is constrained to one safe docs directory slug.
mkdir -p "$REPO/outside"
touch "$REPO/outside/EXECUTION.md"
if (cd "$REPO" && bash "$ROOT/tools/resolve-feature-doc.sh" execution ../outside "" >/dev/null 2>&1); then
	echo "FAIL: task path escaped docs/" >&2
	exit 1
fi

# A safe-looking task slug cannot escape docs through a symlink.
ln -s ../outside "$REPO/docs/safe"
if (cd "$REPO" && bash "$ROOT/tools/resolve-feature-doc.sh" execution safe "" >/dev/null 2>&1); then
	echo "FAIL: task symlink escaped docs/" >&2
	exit 1
fi

# A branch-matched feature cannot supply its canonical breakdown through a symlink.
rm "$REPO/docs/catalog-category-expansion/MIU_BREAKDOWN.md"
ln -s ../../outside/EXECUTION.md "$REPO/docs/catalog-category-expansion/MIU_BREAKDOWN.md"
if (cd "$REPO" && bash "$ROOT/tools/resolve-feature-doc.sh" breakdown "" feat/catalog-category-design >/dev/null 2>&1); then
	echo "FAIL: branch-resolved breakdown symlink escaped the repository" >&2
	exit 1
fi

echo "PASS: resolver selected the branch/task-matched uppercase docs and ignored the newer wrong feature"