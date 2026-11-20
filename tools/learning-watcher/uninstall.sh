#!/bin/bash
# Turn the learning watcher off for good: unload both launchd agents, remove
# their plists and our pre-push privacy gates. Journal, digests and reports in
# ~/.claude/learning are KEPT unless you pass --purge.
#
#   bash tools/learning-watcher/uninstall.sh [--keep-git-hooks] [--purge]
set -uo pipefail
LW_HOME="${LW_HOME:-$HOME/.claude/learning}"
AGENTS="$HOME/Library/LaunchAgents"
KEEP_HOOKS=0; PURGE=0
for a in "$@"; do case "$a" in --keep-git-hooks) KEEP_HOOKS=1;; --purge) PURGE=1;; esac; done

for L in com.dev-pipeline.learning-watcher.capture com.dev-pipeline.learning-watcher.consolidate; do
  launchctl bootout "gui/$(id -u)/$L" >/dev/null 2>&1 && echo "unloaded $L"
  rm -f "$AGENTS/$L.plist"
done

if [[ $KEEP_HOOKS -eq 0 ]]; then
  # shellcheck disable=SC1091
  [[ -f "$LW_HOME/config.env" ]] && source "$LW_HOME/config.env"
  for repo in "${LW_EC_REPO:-$HOME/.claude/skills/engineering-craft}" "${LW_DP_REPO:-}"; do
    [[ -n "$repo" && -e "$repo/.git" ]] || continue
    hook="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/hooks/pre-push"
    if [[ -f "$hook" ]] && grep -q learning-watcher-privacy-gate "$hook"; then
      rm -f "$hook" && echo "removed privacy gate from $repo"
    fi
  done
fi

# The inbox worktrees belong to the two repos; drop the checkouts, keep the branches.
for wt in "$LW_HOME"/inbox/*; do
  [[ -e "$wt/.git" ]] || continue
  if [[ -z "$(git -C "$wt" status --porcelain)" ]]; then
    git -C "$wt" worktree remove "$wt" && echo "removed inbox checkout $wt (branch learning/inbox kept)"
  else
    echo "kept $wt: it has uncommitted changes"
  fi
done

# The desktop app's scheduled task calls bin/consolidate.sh; PAUSED makes it a no-op
# until the task itself is deleted in the app (a script cannot unregister it).
mkdir -p "$LW_HOME" && touch "$LW_HOME/PAUSED"
if [[ -d "$HOME/.claude/scheduled-tasks/learning-watcher-consolidate" ]]; then
  echo "ACTION: delete the desktop scheduled task 'Learning watcher: daily consolidation'"
  echo "        (Claude app → Scheduled in the sidebar). Until then it finds PAUSED and does nothing."
fi

if [[ $PURGE -eq 1 ]]; then
  rm -rf "$LW_HOME" && echo "purged $LW_HOME"
else
  echo "data kept in $LW_HOME (pass --purge to delete it)"
fi
