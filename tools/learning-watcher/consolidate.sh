#!/bin/bash
# learning-watcher consolidate -- the slow, model step. Two runners, one per day:
#
#   consolidate.sh              launchd, daily 07:30: digest -> inbox worktrees ->
#                               `claude -p` (hard dollar + turn cap, no shell) ->
#                               privacy gate -> LOCAL commit. Needs a signed-in CLI.
#   consolidate.sh --prepare    for a signed-in session (the desktop app's scheduled
#                               task): digest + inbox worktrees, then prints the filled
#                               prompt path. The session does the model work itself.
#   consolidate.sh --finalize   after --prepare: privacy gate -> LOCAL commit -> mark
#                               the entries consolidated -> report + notification.
#
# Whichever runner gets there first does the day; the other sees state/last-run-date and
# stops. Fewer than LW_MIN_ENTRIES pending entries -> no model work at all.
# Nothing is ever pushed: a person reviews learning/inbox, merges and pushes.
#
# Flags: --force (ignore the entry minimum and today's stamp), --dry-run (digest only).
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

MODE=run; FORCE=0; DRY=0
for a in "$@"; do case "$a" in
  --force) FORCE=1;; --dry-run) DRY=1;; --prepare) MODE=prepare;; --finalize) MODE=finalize;;
esac; done

DATE="$(date +%Y-%m-%d)"
LOG="$LW_HOME/logs/consolidate.log"
STAMP="$LW_HOME/state/last-run-date"
SESSION="$LW_HOME/state/session-run.env"     # written by --prepare, read by --finalize
mkdir -p "$LW_HOME"/{digests,reports,rejected,logs,inbox,state}
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [$MODE] $*" >> "$LOG"; }
notify() { [[ -n "${LW_NO_NOTIFY:-}" ]] && return 0; osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true; }
say() { echo "$*"; }

[[ -e "$LW_HOME/PAUSED" ]] && { log "paused"; say "NOTHING paused"; exit 0; }
LOCK="$LW_HOME/state/consolidate.lock.d"
mkdir "$LOCK" 2>/dev/null || { log "another run holds $LOCK"; say "NOTHING busy"; exit 0; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

EC="$LW_HOME/inbox/engineering-craft"; DP="$LW_HOME/inbox/dev-pipeline"

# ---- privacy gate, then a LOCAL commit ---------------------------------------
SUMMARY=""
gate_and_commit() {  # worktree name public-flag pending
  local wt="$1" name="$2" pub="$3" pending="$4"
  [[ -n "$(git -C "$wt" status --porcelain)" ]] || { SUMMARY+="$name: no change. "; return; }
  if python3 "$BIN/privacy_lint.py" --git-worktree --repo "$wt" $pub >>"$LOG" 2>&1; then
    git -C "$wt" add -A
    git -C "$wt" commit -q -m "learn(auto): consolidation $DATE from $pending journal entries

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

finish() {  # ids pending ran(1|0)
  # recipes.json may have changed: regenerate the router tables it feeds, so the inbox
  # branch passes tests/recipes.test.sh as committed.
  [[ -f "$DP/tools/render-recipes.py" ]] && python3 "$DP/tools/render-recipes.py" >>"$LOG" 2>&1
  gate_and_commit "$EC" engineering-craft --public "$2"
  gate_and_commit "$DP" dev-pipeline "" "$2"
  if [[ "$3" -eq 1 ]]; then
    python3 "$BIN/digest.py" --mark-consolidated "$1" >>"$LOG" 2>&1
    echo "$DATE" > "$STAMP"
  else
    SUMMARY+="Model did not run — entries stay pending. "
  fi
  log "done: $SUMMARY"
  notify "Learning watcher" "$SUMMARY Report: reports/$DATE.md"
  say "$SUMMARY"
}

if [[ "$MODE" == finalize ]]; then
  [[ -f "$SESSION" ]] || { say "NOTHING no prepared run (run --prepare first)"; exit 1; }
  # shellcheck disable=SC1090
  source "$SESSION"
  finish "$IDS" "$PENDING" 1
  rm -f "$SESSION"
  exit 0
fi

# ---- run / prepare: one consolidation per day --------------------------------
if [[ "$FORCE" -eq 0 && "$(cat "$STAMP" 2>/dev/null)" == "$DATE" ]]; then
  log "skip: already consolidated today"; say "NOTHING already consolidated today"; exit 0
fi
if [[ -f "$SESSION" && -n "$(find "$SESSION" -mmin -360 2>/dev/null)" ]]; then
  log "skip: a session-run is in progress"; say "NOTHING session run in progress"; exit 0
fi
# A prepared run that never finalized (crash, unanswered prompt) leaves edits in an inbox.
# Keep them as a patch and clear the inbox, or every later run would stop at "not ready".
for name in engineering-craft dev-pipeline; do
  wt="$LW_HOME/inbox/$name"
  if [[ -e "$wt/.git" && -n "$(git -C "$wt" status --porcelain)" ]]; then
    patch="$LW_HOME/rejected/$DATE-$name-abandoned.patch"
    { git -C "$wt" diff; git -C "$wt" ls-files --others --exclude-standard | sed 's/^/untracked: /'; } > "$patch"
    git -C "$wt" checkout -q -- . && git -C "$wt" clean -qfd
    log "$name inbox held an unfinished run's edits; saved $patch and cleared it"
  fi
done
rm -f "$SESSION"

DIGEST="$LW_HOME/digests/$DATE.md"
IDS="$LW_HOME/digests/$DATE.ids"
rm -f "$IDS"
python3 "$BIN/digest.py" --out "$DIGEST" --ids-out "$IDS" --max-chars "$LW_DIGEST_CHARS" >>"$LOG" 2>&1
PENDING=$(grep -c . "$IDS" 2>/dev/null || true); PENDING=${PENDING:-0}   # never "0\n0"
if [[ "$PENDING" -lt "$LW_MIN_ENTRIES" && "$FORCE" -eq 0 ]]; then
  log "skip: $PENDING pending entries (< $LW_MIN_ENTRIES); no model call"
  say "NOTHING $PENDING pending entries"
  exit 0
fi
if [[ "$DRY" -eq 1 ]]; then log "dry-run: digest at $DIGEST ($PENDING entries)"; say "$DIGEST"; exit 0; fi

if [[ "$MODE" == run && -z "${ANTHROPIC_API_KEY:-}${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] && \
   ! "$CLAUDE_BIN" auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
  # Not an error: the desktop app's scheduled task (--prepare/--finalize) covers this day.
  log "skip: claude CLI is not signed in; $PENDING entries wait for the scheduled session"
  say "claude CLI not signed in — the desktop scheduled task will consolidate (or run: claude auth login)"
  exit 0
fi

# ---- inbox worktrees: learning/inbox, based on the repo's base branch --------
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
prepare_inbox "$EC_REPO" engineering-craft "${LW_EC_BASE:-main}" || { notify "Learning watcher" "engineering-craft inbox not ready — see $LOG"; say "NOTHING inbox not ready"; exit 1; }
prepare_inbox "$DP_REPO" dev-pipeline "${LW_DP_BASE:-main}" || { notify "Learning watcher" "dev-pipeline inbox not ready — see $LOG"; say "NOTHING inbox not ready"; exit 1; }
REPORT="$LW_HOME/reports/$DATE.md"

PROMPT_FILE="$LW_HOME/state/prompt-$DATE.md"
sed -e "s|{{DIGEST}}|$DIGEST|g" -e "s|{{STATS}}|$LW_HOME/state/recipe-stats.json|g" \
  -e "s|{{SOURCES}}|$BIN/sources.json|g" -e "s|{{EC}}|$EC|g" -e "s|{{DP}}|$DP|g" \
  -e "s|{{REPORT}}|$REPORT|g" -e "s|{{DATE}}|$DATE|g" -e "s|{{MAX_CHANGES}}|$LW_MAX_CHANGES|g" \
  "$BIN/consolidate-prompt.md" > "$PROMPT_FILE"

if [[ "$MODE" == prepare ]]; then
  printf 'IDS=%q\nPENDING=%q\n' "$IDS" "$PENDING" > "$SESSION"
  log "prepared: $PENDING entries, prompt $PROMPT_FILE"
  say "READY $PROMPT_FILE"
  exit 0
fi

log "run: $PENDING entries, model=$LW_MODEL budget=\$$LW_BUDGET_USD turns=$LW_MAX_TURNS"
cd "$LW_HOME" || exit 1
"$CLAUDE_BIN" -p "$(cat "$PROMPT_FILE")" \
  --model "$LW_MODEL" --max-budget-usd "$LW_BUDGET_USD" --max-turns "$LW_MAX_TURNS" \
  --no-session-persistence --permission-mode acceptEdits \
  --add-dir "$EC" --add-dir "$DP" \
  --allowedTools "Read" "Write" "Edit" "Glob" "Grep" "WebSearch" "WebFetch" \
  --disallowedTools "Bash" "Agent" "Task" \
  --output-format json > "$LW_HOME/logs/consolidate-$DATE.json" 2>>"$LOG"
RC=$?
COST="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(round(d.get("total_cost_usd") or d.get("cost_usd") or 0,4))' "$LW_HOME/logs/consolidate-$DATE.json" 2>/dev/null || echo "?")"
log "claude exit=$RC cost_usd=$COST"
# Mark the entries done whenever the model actually ran (a budget stop still produced a
# reviewed result); an auth or launch failure leaves them pending.
RAN=0; grep -q '"type": *"result"' "$LW_HOME/logs/consolidate-$DATE.json" 2>/dev/null && RAN=1
finish "$IDS" "$PENDING" "$RAN"
