#!/usr/bin/env bash
# Resolve one feature document without guessing from an unrelated newest plan.
# Usage: resolve-feature-doc.sh <execution|breakdown> [task] [branch]
set -euo pipefail

KIND="${1:-}"
TASK="${2:-}"
# `${3:-default}` treats an explicitly empty third argument as missing, which makes it
# impossible for a caller with a VALIDATED planning pointer to request task-only lookup.
# `${3-default}` defaults only when the argument is omitted.
BRANCH="${3-$(git branch --show-current 2>/dev/null || true)}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

case "$KIND" in
  execution)
    NAMES=("EXECUTION.md" "execution.md")
    SUFFIX="-execution.md"
    ;;
  breakdown)
    NAMES=("MIU_BREAKDOWN.md" "miu-breakdown.md")
    SUFFIX="-miu-breakdown.md"
    ;;
  *)
    echo "usage: $0 <execution|breakdown> [task] [branch]" >&2
    exit 2
    ;;
esac

[[ -d docs ]] || exit 1

# 1. Branch-declared execution record. This is the portable identity when the docs
#    directory slug differs from the branch slug (catalog-category-expansion vs
#    feat/catalog-category-design). The declaration MUST be the exact `Branch:` field;
#    a prose mention or `Previous Branch:` does not establish authority. Ambiguity fails
#    closed instead of selecting the first path alphabetically.
if [[ -n "$BRANCH" ]]; then
  MATCHES=()
  while IFS= read -r EXECUTION; do
    DECLARATION_COUNT=0
    REQUESTED_COUNT=0
    while IFS= read -r DECLARED; do
      if [[ -n "$DECLARED" ]]; then
        DECLARATION_COUNT=$((DECLARATION_COUNT + 1))
        [[ "$DECLARED" == "$BRANCH" ]] && REQUESTED_COUNT=$((REQUESTED_COUNT + 1))
      fi
    done < <(sed -n 's/^Branch:[[:space:]]*`\([^`]*\)`[[:space:]]*\.*[[:space:]]*$/\1/p' "$EXECUTION" 2>/dev/null)
    if (( REQUESTED_COUNT > 0 && DECLARATION_COUNT > 1 )); then
      echo "ambiguous tracked handoff: $EXECUTION declares '$BRANCH' plus another Branch field" >&2
      exit 3
    fi
    if (( REQUESTED_COUNT == 1 )); then
      MATCHES+=("$EXECUTION")
    fi
  done < <(find docs -type f \( -iname 'execution.md' -o -iname '*-execution.md' \) 2>/dev/null | sort)

  if (( ${#MATCHES[@]} > 1 )); then
    echo "ambiguous tracked handoff: branch '$BRANCH' is declared by:" >&2
    printf '  %s\n' "${MATCHES[@]}" >&2
    exit 3
  fi
  if (( ${#MATCHES[@]} == 1 )); then
    EXECUTION="${MATCHES[0]}"
    [[ ! -L "$EXECUTION" ]] || exit 1
    DIR="$(dirname "$EXECUTION")"
    DIR_REAL="$(cd "$DIR" && pwd -P)"
    DOCS_REAL="$(cd docs && pwd -P)"
    case "$DIR_REAL/" in "$DOCS_REAL/"*) ;; *) exit 1 ;; esac
    if [[ "$KIND" == "execution" ]]; then
      echo "$EXECUTION"
      exit 0
    fi
    for NAME in "${NAMES[@]}"; do
      [[ -f "$DIR/$NAME" && ! -L "$DIR/$NAME" ]] && { echo "$DIR/$NAME"; exit 0; }
    done
    MATCH="$(find "$DIR" -maxdepth 1 -type f -iname "*$SUFFIX" 2>/dev/null | sort | head -1)"
    [[ -n "$MATCH" && ! -L "$MATCH" ]] && { echo "$MATCH"; exit 0; }
    exit 1
  fi
fi

# 2. Exact task directory is secondary and only safe when the caller deliberately
#    supplies no branch identity. Consumers may do this ONLY after validating the local
#    pointer (planning/detached flow). A stale task can never override a current branch.
if [[ -z "$BRANCH" && "$TASK" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && -d "docs/$TASK" ]]; then
  TASK_DIR="docs/$TASK"
  [[ ! -L "$TASK_DIR" ]] || exit 1
  TASK_REAL="$(cd "$TASK_DIR" 2>/dev/null && pwd -P)"
  DOCS_REAL="$(cd docs && pwd -P)"
  case "$TASK_REAL/" in "$DOCS_REAL/"*) ;; *) exit 1 ;; esac
  for NAME in "${NAMES[@]}"; do
    [[ -f "$TASK_DIR/$NAME" && ! -L "$TASK_DIR/$NAME" ]] && { echo "$TASK_DIR/$NAME"; exit 0; }
  done
  MATCH="$(find "$TASK_DIR" -maxdepth 1 -type f -iname "*$SUFFIX" 2>/dev/null | sort | head -1)"
  [[ -n "$MATCH" ]] && { echo "$MATCH"; exit 0; }
fi

exit 1