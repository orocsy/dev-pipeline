#!/usr/bin/env bash
# Exit 0 only when the local pointer belongs to the current branch, its remote branch
# exists, and its timestamp is at least as new as HEAD. Pointer content is disposable;
# any uncertainty means callers must resolve tracked docs instead.
set -euo pipefail

POINTER="${1:-.claude/pipeline-state.json}"
CURRENT_BRANCH="${2:-$(git branch --show-current 2>/dev/null || true)}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

[[ -f "$POINTER" ]] || exit 1
command -v jq >/dev/null 2>&1 || exit 1

PTR_BRANCH="$(jq -r '.branch // empty' "$POINTER" 2>/dev/null)"
PTR_UPDATED="$(jq -r '.updatedAt // empty' "$POINTER" 2>/dev/null)"
[[ -n "$PTR_BRANCH" ]] || exit 1
# Detached HEAD has no branch name; the pointer may provide it only when HEAD is exactly on
# that remote branch. A named current branch must still match exactly.
if [[ -n "$CURRENT_BRANCH" ]]; then
	[[ "$PTR_BRANCH" == "$CURRENT_BRANCH" ]] || exit 1
fi
# Remote existence is a load-bearing check. Network/auth uncertainty fails closed rather
# than accepting a stale cached tracking ref for a branch deleted remotely.
git fetch origin --prune --quiet >/dev/null 2>&1 || exit 1
git rev-parse --verify "origin/$PTR_BRANCH" >/dev/null 2>&1 || exit 1
if [[ -z "$CURRENT_BRANCH" ]]; then
	[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$PTR_BRANCH")" ]] || exit 1
fi

# JavaScript's toISOString() includes fractional seconds; BSD date's `%S` parser does not.
# Normalize only the optional fractional component while preserving the canonical UTC form.
PTR_UPDATED_NORMALIZED="$(printf '%s' "$PTR_UPDATED" | sed -E 's/\.[0-9]+Z$/Z/')"
PTR_UPDATED_EPOCH=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$PTR_UPDATED_NORMALIZED" +%s 2>/dev/null || date -d "$PTR_UPDATED_NORMALIZED" +%s 2>/dev/null || echo 0)
HEAD_EPOCH=$(git show -s --format=%ct HEAD 2>/dev/null || echo 0)
[[ "${PTR_UPDATED_EPOCH:-0}" -ge "${HEAD_EPOCH:-0}" ]]