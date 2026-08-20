#!/usr/bin/env bash
# Print the unique tracked criteria documents for the current feature, one per line.
# Authority: current branch declaration first; a local pointer contributes task/breakdown
# only when pipeline-pointer-valid.sh accepts it. All returned files share one directory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POINTER="${1:-.claude/pipeline-state.json}"
BRANCH="${2:-$(git branch --show-current 2>/dev/null || true)}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

POINTER_VALID=0
bash "$ROOT/tools/pipeline-pointer-valid.sh" "$POINTER" "$BRANCH" 2>/dev/null && POINTER_VALID=1
TASK=""
POINTER_BREAKDOWN=""
if [[ "$POINTER_VALID" == "1" ]]; then
  TASK="$(jq -r '.task // empty' "$POINTER" 2>/dev/null)"
  POINTER_BREAKDOWN="$(jq -r '.docs.breakdown // empty' "$POINTER" 2>/dev/null)"
  [[ "$TASK" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || TASK=""
  if [[ -n "$POINTER_BREAKDOWN" ]]; then
    case "$POINTER_BREAKDOWN" in
      docs/*) ;;
      *) POINTER_BREAKDOWN="" ;;
    esac
    [[ -L "$POINTER_BREAKDOWN" ]] && POINTER_BREAKDOWN=""
  fi
fi

set +e
EXECUTION="$(bash "$ROOT/tools/resolve-feature-doc.sh" execution "" "$BRANCH")"
EXECUTION_RC=$?
set -e
[[ "$EXECUTION_RC" == "0" || "$EXECUTION_RC" == "1" ]] || exit "$EXECUTION_RC"
if [[ -z "$EXECUTION" && "$POINTER_VALID" == "1" ]]; then
  EXECUTION="$(bash "$ROOT/tools/resolve-feature-doc.sh" execution "$TASK" "")"
fi
[[ -n "$EXECUTION" && -f "$EXECUTION" ]] || exit 1
FEATURE_DIR="$(dirname "$EXECUTION")"

BREAKDOWN=""
FEATURE_REAL="$(cd "$FEATURE_DIR" && pwd -P)"
if [[ -n "$POINTER_BREAKDOWN" && -f "$POINTER_BREAKDOWN" && "$(dirname "$POINTER_BREAKDOWN")" == "$FEATURE_DIR" ]]; then
  POINTER_BREAKDOWN_REAL="$(cd "$(dirname "$POINTER_BREAKDOWN")" && pwd -P)/$(basename "$POINTER_BREAKDOWN")"
  case "$POINTER_BREAKDOWN_REAL" in "$FEATURE_REAL/"*) BREAKDOWN="$POINTER_BREAKDOWN" ;; esac
fi
if [[ -z "$BREAKDOWN" ]]; then
  set +e
  BREAKDOWN="$(bash "$ROOT/tools/resolve-feature-doc.sh" breakdown "" "$BRANCH")"
  BREAKDOWN_RC=$?
  set -e
  [[ "$BREAKDOWN_RC" == "0" || "$BREAKDOWN_RC" == "1" ]] || exit "$BREAKDOWN_RC"
fi
if [[ -z "$BREAKDOWN" && "$POINTER_VALID" == "1" ]]; then
  BREAKDOWN="$(bash "$ROOT/tools/resolve-feature-doc.sh" breakdown "$TASK" "" 2>/dev/null || true)"
fi
{
  printf '%s\n' "$EXECUTION"
  [[ -n "$BREAKDOWN" && -f "$BREAKDOWN" && "$(dirname "$BREAKDOWN")" == "$FEATURE_DIR" ]] && printf '%s\n' "$BREAKDOWN"
  find "$FEATURE_DIR" -maxdepth 1 -type f \( -iname '*-plan.md' -o -iname 'task_plan.md' -o -iname 'SPEC.md' -o -iname 'ISSUE.md' \) 2>/dev/null
} | awk 'NF && !seen[$0]++' | sort