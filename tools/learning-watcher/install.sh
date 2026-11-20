#!/bin/bash
# Install or refresh the learning watcher. Idempotent: re-run after pulling
# dev-pipeline to update the installed copy.
#
#   bash tools/learning-watcher/install.sh [--no-launchd] [--no-git-hooks] [--seed-terms FILE]
#
# What it does:
#   * copies the runtime into ~/.claude/learning/bin (launchd runs that copy, so a
#     branch switch in the plugin checkout can never break the scheduler)
#   * creates config.env and private-terms.txt (kept if present; mode 600)
#   * loads two launchd agents: capture every 15 min, consolidate daily 07:30
#   * installs the pre-push privacy gate in engineering-craft and dev-pipeline
# Turn it off: see README.md ("Turning it off").
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$SRC/../.." && pwd -P)"
LW_HOME="${LW_HOME:-$HOME/.claude/learning}"
BIN="$LW_HOME/bin"
AGENTS="$HOME/Library/LaunchAgents"
LABEL_CAPTURE="com.dev-pipeline.learning-watcher.capture"
LABEL_CONSOLIDATE="com.dev-pipeline.learning-watcher.consolidate"
EC_REPO="${LW_EC_REPO:-$HOME/.claude/skills/engineering-craft}"
DP_REPO="${LW_DP_REPO:-$REPO}"
DO_LAUNCHD=1; DO_HOOKS=1; SEED=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-launchd) DO_LAUNCHD=0;;
    --no-git-hooks) DO_HOOKS=0;;
    --seed-terms) SEED="$2"; shift;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
  shift
done

mkdir -p "$BIN" "$LW_HOME"/{state,journal,events,logs,digests,reports,rejected,inbox}
chmod 700 "$LW_HOME"
for f in capture.py redact.py privacy_lint.py digest.py consolidate.sh consolidate-prompt.md \
         given-names.txt domain-allowlist.txt sources.json; do
  cp "$SRC/$f" "$BIN/$f"
done
cp "$SRC/git-hooks/pre-push-privacy" "$BIN/pre-push-privacy"
cp "$REPO/recipes/recipes.json" "$BIN/recipes.json"
chmod +x "$BIN"/*.py "$BIN/consolidate.sh" "$BIN/pre-push-privacy"
echo "$REPO" > "$BIN/SOURCE"

PY="$(command -v python3 || echo /usr/bin/python3)"
CLAUDE="$(command -v claude || echo "$HOME/.local/bin/claude")"

if [[ ! -f "$LW_HOME/config.env" ]]; then
  cat > "$LW_HOME/config.env" <<EOF
# learning watcher settings (sourced by consolidate.sh; capture reads LW_* from launchd env)
LW_BUDGET_USD=0.75        # hard cap per consolidation run (claude -p --max-budget-usd)
LW_MAX_TURNS=40           # hard cap on agent turns per run
LW_MODEL=sonnet           # model for consolidation
LW_MIN_ENTRIES=5          # fewer pending journal entries -> skip the model call entirely
LW_MAX_CHANGES=5          # files changed per repo per run
LW_DIGEST_CHARS=24000     # digest size cap (~6k tokens of input)
CLAUDE_BIN=$CLAUDE
LW_EC_REPO=$EC_REPO
LW_DP_REPO=$DP_REPO
LW_EC_BASE=${LW_EC_BASE:-main}   # branch the learning/inbox worktrees start from
LW_DP_BASE=${LW_DP_BASE:-main}
EOF
fi

if [[ ! -f "$LW_HOME/private-terms.txt" ]]; then
  {
    echo "# Private terms for the learning watcher. NEVER commit this file."
    echo "# [always]   redacted from the local journal AND blocked from git"
    echo "# [git-only] kept in the local journal (useful context) but blocked from git:"
    echo "#            project, product, client and company names, domains, IDs."
    echo "# One term per line, case-insensitive, whole word."
    echo "[always]"
    git config --global user.name 2>/dev/null || true
    id -F 2>/dev/null || true
    echo "$USER"
    echo "[git-only]"
    [[ -n "$SEED" && -f "$SEED" ]] && grep -v '^\s*#' "$SEED" || true
  } | awk 'NF && !seen[$0]++' > "$LW_HOME/private-terms.txt"
fi
chmod 600 "$LW_HOME/private-terms.txt" "$LW_HOME/config.env"

write_plist() {  # label, program-args-xml, schedule-xml, runatload
  cat > "$AGENTS/$1.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array>$2</array>
  $3
  <key>RunAtLoad</key><$4/>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>LW_HOME</key><string>$LW_HOME</string>
  </dict>
  <key>StandardOutPath</key><string>$LW_HOME/logs/$1.out</string>
  <key>StandardErrorPath</key><string>$LW_HOME/logs/$1.err</string>
</dict>
</plist>
EOF
}

if [[ $DO_LAUNCHD -eq 1 ]]; then
  mkdir -p "$AGENTS"
  write_plist "$LABEL_CAPTURE" "<string>$PY</string><string>$BIN/capture.py</string>" \
    "<key>StartInterval</key><integer>900</integer>" true
  write_plist "$LABEL_CONSOLIDATE" "<string>/bin/bash</string><string>$BIN/consolidate.sh</string>" \
    "<key>StartCalendarInterval</key><dict><key>Hour</key><integer>7</integer><key>Minute</key><integer>30</integer></dict>" false
  for L in "$LABEL_CAPTURE" "$LABEL_CONSOLIDATE"; do
    launchctl bootout "gui/$(id -u)/$L" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$AGENTS/$L.plist"
  done
  echo "launchd: $LABEL_CAPTURE (every 15 min) and $LABEL_CONSOLIDATE (daily 07:30) loaded"
fi

install_hook() {  # repo public(true|false)
  local repo="$1" pub="$2" hooks
  [[ -e "$repo/.git" ]] || { echo "skip hook: $repo is not a git checkout"; return; }
  hooks="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/hooks"
  mkdir -p "$hooks"
  if [[ -f "$hooks/pre-push" ]] && ! grep -q learning-watcher-privacy-gate "$hooks/pre-push"; then
    echo "WARNING: $hooks/pre-push exists and is not ours — privacy gate NOT installed there. Chain $BIN/pre-push-privacy from it by hand."
    return
  fi
  cp "$BIN/pre-push-privacy" "$hooks/pre-push"
  chmod +x "$hooks/pre-push"
  git -C "$repo" config learning-watcher.public "$pub"
  echo "privacy gate: $hooks/pre-push (public=$pub)"
}
if [[ $DO_HOOKS -eq 1 ]]; then
  install_hook "$EC_REPO" true
  install_hook "$DP_REPO" false
fi

echo "installed runtime: $BIN (from $REPO)"
echo "data: $LW_HOME  ·  off switch: touch $LW_HOME/PAUSED  ·  uninstall: bash $SRC/uninstall.sh"
