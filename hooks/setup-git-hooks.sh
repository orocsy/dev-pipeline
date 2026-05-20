#!/usr/bin/env bash
# dev-pipeline — install the plugin's hooks into a target repo.
#
# Usage:
#   bash <plugin>/hooks/setup-git-hooks.sh              # installs into $PWD
#   bash <plugin>/hooks/setup-git-hooks.sh /path/to/repo
#
# Design — chain via .next, self-detecting hooks:
#   - Each dev-pipeline hook starts with a "is this a dev-pipeline-managed
#     repo?" check (presence of .claude/pipeline-state.json). On non-managed
#     repos, the hook chains to <hook>.next (if installed) and exits cleanly.
#   - This makes the hooks SAFE to install globally via core.hooksPath.
#   - At install time, if a foreign hook already exists at the target, it is
#     renamed to <name>.next; dev-pipeline's hook self-detects and chains.
#   - Identical hooks (cmp -s) → skipped. dev-pipeline hooks (marker on line 2)
#     get updated in place, never re-chained.
#
# Idempotent. Self-contained — every hook body ships inside this plugin.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_REPO="${1:-$PWD}"

if [[ ! -d "$TARGET_REPO/.git" ]] && ! git -C "$TARGET_REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "❌ Not a git repository: $TARGET_REPO"
  echo "   Run from inside a git repo, or pass a path: setup-git-hooks.sh /path/to/repo"
  exit 1
fi

# Honour core.hooksPath if set (e.g. user-global hooks under ~/.config/git/hooks).
CONFIGURED_HOOKS_PATH="$(git -C "$TARGET_REPO" config --get core.hooksPath || true)"
if [[ -n "$CONFIGURED_HOOKS_PATH" ]]; then
  if [[ "$CONFIGURED_HOOKS_PATH" = /* ]]; then
    HOOKS_DIR="$CONFIGURED_HOOKS_PATH"
  else
    HOOKS_DIR="$TARGET_REPO/$CONFIGURED_HOOKS_PATH"
  fi
  mkdir -p "$HOOKS_DIR"
  echo "→ Using configured core.hooksPath: $HOOKS_DIR"
else
  HOOKS_DIR="$TARGET_REPO/.git/hooks"
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
INSTALLED=()

# A hook is "owned by dev-pipeline" if it carries this marker on line 2.
MARKER="# dev-pipeline"

is_dev_pipeline_hook() {
  [[ -f "$1" ]] && head -2 "$1" 2>/dev/null | grep -q "$MARKER"
}

install_hook() {
  local name="$1"
  local source="$SCRIPT_DIR/$name"
  local target="$HOOKS_DIR/$name"

  if [[ ! -f "$source" ]]; then
    echo "  ⚠️  $name source missing at $source (skipped)"
    return
  fi

  # Case 1: target absent → simple install.
  if [[ ! -f "$target" ]]; then
    cp "$source" "$target"
    chmod +x "$target"
    INSTALLED+=("$name (installed)")
    return
  fi

  # Case 2: target is already a dev-pipeline hook → check if up-to-date.
  if is_dev_pipeline_hook "$target"; then
    if cmp -s "$source" "$target"; then
      INSTALLED+=("$name (already current)")
    else
      cp "$source" "$target"
      chmod +x "$target"
      INSTALLED+=("$name (updated)")
    fi
    return
  fi

  # Case 3: target is a foreign hook → preserve it as .next (the dev-pipeline
  # hook self-chains via NEXT_HOOK at run time).
  local chained="$target.next"
  if [[ -f "$chained" ]]; then
    # Existing .next must be from a prior install — back it up to avoid
    # silently overwriting.
    mv "$chained" "$chained.backup.$STAMP"
  fi
  mv "$target" "$chained"
  chmod +x "$chained" 2>/dev/null || true

  cp "$source" "$target"
  chmod +x "$target"

  INSTALLED+=("$name (installed; previous hook preserved as $(basename "$chained"))")
}

echo "→ Installing dev-pipeline hooks into $HOOKS_DIR"
install_hook pre-commit
install_hook pre-push
install_hook post-commit

echo ""
echo "✅ dev-pipeline hooks active"
for line in "${INSTALLED[@]}"; do
  echo "   • $line"
done

cat <<'EOF'

Override env vars (incidents only — every override is audit-logged):
   REVIEWED=1 git push                       skip review-blessed-SHA gate
   DEV_PIPELINE_SKIP_DOC_GUARD=1 git push    skip doc-update guard
   git commit --no-verify                    skip pre-commit lint/typecheck

After any override, run /dev-pipeline:review retroactively.

Note: hooks self-detect dev-pipeline-managed repos (via .claude/pipeline-state.json).
On non-managed repos they pass through to any chained .next hook silently.
EOF
