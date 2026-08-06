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
# Rate-limit a REFRESH, never a REPAIR. A missing/empty skill left un-cloned for up to
# 24h because a marker was written earlier means a whole day of sessions with no craft
# priors and no gates — the limit exists to avoid needless fetches on a healthy
# checkout, not to defer first setup.
EC_HEALTHY=0
[[ -d "$EC_SKILL/categories" ]] && EC_HEALTHY=1
if (( NOW - LAST > 86400 )) || (( EC_HEALTHY == 0 )); then
  if [[ -d "$EC_SKILL/.git" ]]; then
    # Record the outcome so a persistently failing pull (diverged local commits,
    # offline, auth) becomes visible instead of silently re-attempting forever. The
    # `&& echo marker` form swallowed every failure: the marker simply never advanced,
    # which is indistinguishable from "not due yet".
    ( if git -C "$EC_SKILL" pull --ff-only -q >/dev/null 2>&1; then
        echo "$NOW" > "$MARKER"; rm -f "$MARKER.fail"
      else
        # Write ONCE and keep the first failure's timestamp. Overwriting on every
        # session start refreshed the mtime, so the >24h staleness test below could
        # never fire and a permanently failing checkout stayed silent indefinitely.
        [[ -f "$MARKER.fail" ]] || echo "$NOW" > "$MARKER.fail"
      fi ) &
  else
    # Covers BOTH "absent" and "present but not a git checkout".
    #
    # The previous `elif [[ ! -d "$EC_SKILL" ]]` left the third state — the
    # directory exists and is NOT a repo — with no branch, so the refresh was a
    # silent no-op. It stayed that way for a month: the loaded skill sat 25 rules
    # and three whole categories behind the published catalog while every session
    # believed it was current. A refresh that cannot report its own failure is
    # indistinguishable from one that is working.
    # SERIALIZED. This branch moves the live skill directory aside and swaps a fresh
    # clone into its place. Two sessions starting together would both pass the
    # `-d .git` test, both mkdir their own temp clone, and race on the mv — the loser
    # can leave the skill at `$EC_SKILL.old` and nothing at `$EC_SKILL`, i.e. a
    # destructive repair that DELETES the catalog it was meant to refresh. Concurrent
    # sessions are the normal case here, not the edge case.
    ( LOCK="$HOME/.claude/.engineering-craft-refresh.lock"
      if ! mkdir "$LOCK" 2>/dev/null; then
        # Another session owns the swap. Stale-lock guard: if the owner died, the
        # directory would block every future refresh forever.
        if [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]]; then
          rmdir "$LOCK" 2>/dev/null || true
        fi
        exit 0
      fi
      trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
      TMP="$(mktemp -d)"
      # Same remote as setup-machine and review's bootstrap. Cloning upstream over a
      # configured fork replaced its catalog and then deleted the moved-aside copy —
      # fork-specific rules gone, with no error.
      if git clone -q --depth 1 "${ENGINEERING_CRAFT_REPO:-https://github.com/orocsy/engineering-craft.git}" "$TMP/ec" >/dev/null 2>&1 \
         && [[ -d "$TMP/ec/categories" ]]; then
        rm -rf "$EC_SKILL.old"
        [[ -e "$EC_SKILL" ]] && mv "$EC_SKILL" "$EC_SKILL.old"
        if mv "$TMP/ec" "$EC_SKILL"; then
          [[ -f "$EC_SKILL.old/.public-mirror-config" ]] && cp "$EC_SKILL.old/.public-mirror-config" "$EC_SKILL/"
          rm -rf "$EC_SKILL.old"
          echo "$NOW" > "$MARKER"
        else
          # Swap failed after the move-aside — restore rather than leave nothing.
          [[ -d "$EC_SKILL.old" ]] && mv "$EC_SKILL.old" "$EC_SKILL"
        fi
      fi
      rm -rf "$TMP" ) &
  fi
fi

# Staleness is reported, not just repaired: the repair is async and rate-limited,
# so a session that starts against a stale copy must be told rather than left to
# assume the catalog it can see is the catalog that exists.
#
# Reported for BOTH failure shapes. The first cut only entered this block when
# `$EC_SKILL/categories` existed, so the worst case — no skill at all, or a clone
# that died leaving an empty directory — printed nothing and read as healthy.
if [[ ! -d "$EC_SKILL/categories" ]]; then
  echo "[dev-pipeline] engineering-craft skill is MISSING or empty at $EC_SKILL — the craft priors and gates are unavailable this session. A refresh was queued; if it keeps failing: git clone --depth 1 https://github.com/orocsy/engineering-craft.git $EC_SKILL"
else
  if [[ -f "$MARKER.fail" ]] && [[ -n "$(find "$MARKER.fail" -maxdepth 0 -mmin +1440 2>/dev/null)" ]]; then
    echo "[dev-pipeline] engineering-craft refresh has been FAILING for >24h (see: git -C $EC_SKILL pull --ff-only). The loaded catalog may be behind."
  fi
  # Both layouts: categories/<cat>/rules/<slug>.md AND categories/<cat>/<slug>.md
  # (the shape consolidate-lessons produces). A legacy-only glob under-counted a
  # freshly-synced catalog and advised deleting it — see commands/detect.md.
  EC_RULES=$(find "$EC_SKILL/categories" -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${EC_RULES:-0}" -lt 60 ]]; then
    echo "[dev-pipeline] engineering-craft skill looks stale (${EC_RULES} rules; expected 70+). A refresh was queued — re-check next session, or: rm -rf $EC_SKILL && git clone --depth 1 https://github.com/orocsy/engineering-craft.git $EC_SKILL"
  fi
fi

# ── 3. Co-review nudge (opt-in channel; Rule 21 — suggestion only) ──────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d .claude/co-review && -f "$SCRIPT_DIR/co-review-nudge.sh" ]]; then
  bash "$SCRIPT_DIR/co-review-nudge.sh" 2>/dev/null | head -5
fi

exit 0
