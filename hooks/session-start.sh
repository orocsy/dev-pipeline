#!/usr/bin/env bash
# dev-pipeline SessionStart hook — Rule 5 (auto-resume) made real.
#
# Registered via hooks/hooks.json. stdout becomes session context, so keep it
# SHORT and high-signal. Must never fail the session: every step is guarded,
# exit is always 0. Runs from the session's cwd.

set +e

# ── 1. Pipeline state (the resume signal) ────────────────────────────────────
if [[ -f .claude/pipeline-state.json ]] && command -v jq >/dev/null 2>&1; then
  STATE="$(jq -r '"task=" + (.task // "?") + " branch=" + (.branch // "?") + " phase=" + (.phase // "?") + " miu=" + (.currentMiu // "none") + "(" + (.currentMiuStatus // "-") + ")"' .claude/pipeline-state.json 2>/dev/null)"
  if [[ -n "$STATE" && "$STATE" != *"task=? branch=?"* ]]; then
    echo "[dev-pipeline] ACTIVE PIPELINE: $STATE — resume it (Rule 5); do not start a new flow. Verify against docs/<task>/*-execution.md if the pointer looks stale."
  fi
fi

# Pending auto-review from a previous session?
if [[ -f .claude/.auto-review-pending ]]; then
  PENDING_SHA="$(awk '{print $2}' .claude/.auto-review-pending 2>/dev/null | head -c 12)"
  BLESSED="$(tr -d '[:space:]' < .claude/.last-reviewed-sha 2>/dev/null | head -c 12)"
  HEAD_SHA="$(git rev-parse HEAD 2>/dev/null | head -c 12)"
  if [[ -n "$PENDING_SHA" && "$BLESSED" != "$HEAD_SHA" ]]; then
    echo "[dev-pipeline] AUTO-REVIEW PENDING for commit $PENDING_SHA — run /dev-pipeline:review before other work (Rule 2/8)."
  fi
fi

# ── 2. engineering-craft skill refresh (rate-limited: once per 24h) ─────────
EC_SKILL="$HOME/.claude/skills/engineering-craft"
MARKER="$HOME/.claude/.engineering-craft-last-sync"
NOW=$(date +%s)
LAST=0
[[ -f "$MARKER" ]] && LAST=$(cat "$MARKER" 2>/dev/null || echo 0)
if (( NOW - LAST > 86400 )); then
  if [[ -d "$EC_SKILL/.git" ]]; then
    ( git -C "$EC_SKILL" pull --ff-only -q >/dev/null 2>&1 && echo "$NOW" > "$MARKER" ) &
  elif [[ ! -d "$EC_SKILL" ]]; then
    ( git clone -q --depth 1 https://github.com/orocsy/engineering-craft.git "$EC_SKILL" >/dev/null 2>&1 && echo "$NOW" > "$MARKER" ) &
  fi
fi

# ── 3. Co-review nudge (opt-in channel; Rule 21 — suggestion only) ──────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d .claude/co-review && -f "$SCRIPT_DIR/co-review-nudge.sh" ]]; then
  bash "$SCRIPT_DIR/co-review-nudge.sh" 2>/dev/null | head -5
fi

exit 0
