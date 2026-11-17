#!/bin/bash
# learning-watcher consolidate -- the slow, LLM step. Run daily by launchd.
#
# 1. digest.py builds a size-capped digest of journal entries not yet consolidated.
#    Fewer than LW_MIN_ENTRIES pending -> exit without calling a model ($0).
# 2. Prepares `learning/inbox` worktrees of engineering-craft and dev-pipeline
#    under $LW_HOME/inbox/ (the live checkouts and their branches are never touched).
# 3. Runs `claude -p` with a hard dollar cap (--max-budget-usd), a turn cap, no
#    shell, and write access only to the two inbox worktrees + $LW_HOME.
# 4. Runs privacy_lint on each inbox diff. Clean -> commit LOCALLY on learning/inbox.
#    Any finding -> the diff is saved to $LW_HOME/rejected/ and discarded.
#    Nothing is ever pushed: Nina reviews, merges and pushes.
# 5. Marks the digest's entries consolidated and posts a macOS notification.
#
# Usage: consolidate.sh [--force] [--dry-run]   (--dry-run: digest only, no model)
set -uo pipefail

LW_HOME="${LW_HOME:-$HOME/.claude/learning}"
BIN="$LW_HOME/bin"
# shellcheck disable=SC1091
[[ -f "$LW_HOME/config.env" ]] && source "$LW_HOME/config.env"
LW_BUDGET_USD="${LW_BUDGET_USD:-0.75}"
LW_MAX_TURNS="${LW_MAX_TURNS:-40}"
LW_MODEL="${LW_MODEL:-sonnet}"
LW_MIN_ENTRIES="${LW_MIN_ENTRIES:-5}"
LW_MAX_CHANGES="${LW_MAX_CHANGES:-5}"
LW_DIGEST_CHARS="${LW_DIGEST_CHARS:-24000}"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
EC_REPO="${LW_EC_REPO:-$HOME/.claude/skills/engineering-craft}"
DP_REPO="${LW_DP_REPO:-$(cd "$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline" 2>/dev/null && pwd -P)}"

FORCE=0; DRY=0
for a in "$@"; do case "$a" in --force) FORCE=1;; --dry-run) DRY=1;; esac; done

DATE="$(date +%Y-%m-%d)"
LOG="$LW_HOME/logs/consolidate.log"
mkdir -p "$LW_HOME"/{digests,reports,rejected,logs,inbox,state}
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$LOG"; }
notify() { [[ -n "${LW_NO_NOTIFY:-}" ]] && return 0; osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true; }

[[ -e "$LW_HOME/PAUSED" ]] && { log "paused"; exit 0; }
LOCK="$LW_HOME/state/consolidate.lock.d"
mkdir "$LOCK" 2>/dev/null || { log "another run holds $LOCK"; exit 0; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

DIGEST="$LW_HOME/digests/$DATE.md"
IDS="$LW_HOME/digests/$DATE.ids"
rm -f "$IDS"
python3 "$BIN/digest.py" --out "$DIGEST" --ids-out "$IDS" --max-chars "$LW_DIGEST_CHARS" >>"$LOG" 2>&1
PENDING=$( [[ -f "$IDS" ]] && grep -c . "$IDS" || echo 0 )
if [[ "$PENDING" -lt "$LW_MIN_ENTRIES" && "$FORCE" -eq 0 ]]; then
  log "skip: $PENDING pending entries (< $LW_MIN_ENTRIES); no model call"
  exit 0
fi
if [[ "$DRY" -eq 1 ]]; then log "dry-run: digest at $DIGEST ($PENDING entries)"; echo "$DIGEST"; exit 0; fi

# ---- the model needs a signed-in CLI (the desktop app's sign-in does not carry over)
if [[ -z "${ANTHROPIC_API_KEY:-}${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] && \
   ! "$CLAUDE_BIN" auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
  log "skip: claude CLI is not signed in; $PENDING entries stay pending"
  notify "Learning watcher" "Daily consolidation is waiting: run 'claude auth login' once in a terminal. Capture keeps working."
  echo "claude CLI not signed in — run: claude auth login"
  exit 0
fi

# ---- inbox worktrees: learning/inbox, based on the repo's local main ---------
prepare_inbox() {  # repo name base-branch
  local repo="$1" name="$2" base="$3" wt="$LW_HOME/inbox/$2"
  [[ -d "$repo/.git" || -f "$repo/.git" ]] || { log "missing repo $repo"; return 1; }
  if [[ ! -e "$wt/.git" ]]; then
    git -C "$repo" worktree prune >/dev/null 2>&1
    if git -C "$repo" show-ref -q --verify refs/heads/learning/inbox; then
      git -C "$repo" worktree add -q "$wt" learning/inbox >>"$LOG" 2>&1 || return 1
    else
      git -C "$repo" worktree add -q -b learning/inbox "$wt" "$base" >>"$LOG" 2>&1 || return 1
    fi
  fi
  # Nothing waiting for review -> start again from the current base.
  if [[ -z "$(git -C "$wt" status --porcelain)" && -z "$(git -C "$wt" log --oneline "$base..HEAD" 2>/dev/null)" ]]; then
    git -C "$wt" reset -q --hard "$base" >>"$LOG" 2>&1
  fi
  [[ -z "$(git -C "$wt" status --porcelain)" ]] || { log "$name inbox has uncommitted changes; leaving it alone"; return 1; }
}
prepare_inbox "$EC_REPO" engineering-craft "${LW_EC_BASE:-main}" || { notify "Learning watcher" "engineering-craft inbox not ready — see $LOG"; exit 1; }
prepare_inbox "$DP_REPO" dev-pipeline "${LW_DP_BASE:-main}" || { notify "Learning watcher" "dev-pipeline inbox not ready — see $LOG"; exit 1; }
EC="$LW_HOME/inbox/engineering-craft"; DP="$LW_HOME/inbox/dev-pipeline"
REPORT="$LW_HOME/reports/$DATE.md"

PROMPT="$(sed -e "s|{{DIGEST}}|$DIGEST|g" -e "s|{{STATS}}|$LW_HOME/state/recipe-stats.json|g" \
  -e "s|{{SOURCES}}|$BIN/sources.json|g" -e "s|{{EC}}|$EC|g" -e "s|{{DP}}|$DP|g" \
  -e "s|{{REPORT}}|$REPORT|g" -e "s|{{DATE}}|$DATE|g" -e "s|{{MAX_CHANGES}}|$LW_MAX_CHANGES|g" \
  "$BIN/consolidate-prompt.md")"

log "run: $PENDING entries, model=$LW_MODEL budget=\$$LW_BUDGET_USD turns=$LW_MAX_TURNS"
cd "$LW_HOME" || exit 1
"$CLAUDE_BIN" -p "$PROMPT" \
  --model "$LW_MODEL" --max-budget-usd "$LW_BUDGET_USD" --max-turns "$LW_MAX_TURNS" \
  --no-session-persistence --permission-mode acceptEdits \
  --add-dir "$EC" --add-dir "$DP" \
  --allowedTools "Read" "Write" "Edit" "Glob" "Grep" "WebSearch" "WebFetch" \
  --disallowedTools "Bash" "Agent" "Task" \
  --output-format json > "$LW_HOME/logs/consolidate-$DATE.json" 2>>"$LOG"
RC=$?
COST="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(round(d.get("total_cost_usd") or d.get("cost_usd") or 0,4))' "$LW_HOME/logs/consolidate-$DATE.json" 2>/dev/null || echo "?")"
log "claude exit=$RC cost_usd=$COST"

# ---- privacy gate, then a LOCAL commit ---------------------------------------
SUMMARY=""
gate_and_commit() {  # worktree name public-flag
  local wt="$1" name="$2" pub="$3"
  [[ -n "$(git -C "$wt" status --porcelain)" ]] || { SUMMARY+="$name: no change. "; return; }
  if python3 "$BIN/privacy_lint.py" --git-worktree --repo "$wt" $pub >>"$LOG" 2>&1; then
    git -C "$wt" add -A
    git -C "$wt" commit -q -m "learn(auto): consolidation $DATE from $PENDING journal entries

Written by the learning watcher (tools/learning-watcher). Privacy lint passed.
Local only: review, then merge into main and push yourself." >>"$LOG" 2>&1
    SUMMARY+="$name: $(git -C "$wt" diff --stat HEAD~1 | tail -1 | sed 's/^ *//'). "
  else
    local patch="$LW_HOME/rejected/$DATE-$name.patch"
    { git -C "$wt" diff; git -C "$wt" ls-files --others --exclude-standard | sed 's/^/untracked: /'; } > "$patch"
    git -C "$wt" checkout -q -- . && git -C "$wt" clean -qfd
    SUMMARY+="$name: REJECTED by privacy lint (saved $patch). "
    log "$name rejected by privacy lint -> $patch"
  fi
}
gate_and_commit "$EC" engineering-craft --public
gate_and_commit "$DP" dev-pipeline ""

# Mark the entries done whenever the model actually ran (a budget stop still
# produced a reviewed result); an auth or launch failure leaves them pending.
if grep -q '"type": *"result"' "$LW_HOME/logs/consolidate-$DATE.json" 2>/dev/null; then
  python3 "$BIN/digest.py" --mark-consolidated "$IDS" >>"$LOG" 2>&1
else
  SUMMARY+="Model did not run (exit $RC) — entries stay pending. "
fi
log "done: $SUMMARY"
notify "Learning watcher" "$SUMMARY Report: reports/$DATE.md"
echo "$SUMMARY"
