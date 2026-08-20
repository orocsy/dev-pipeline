#!/usr/bin/env bash
# dev-pipeline SessionStart hook — Rule 5 (auto-resume) made real.
#
# Registered via hooks/hooks.json. stdout becomes session context, so keep it
# SHORT and high-signal. Must never fail the session: every step is guarded,
# exit is always 0. Runs from the session's cwd.

set +e

# ── 1. Pipeline state (the resume signal) ────────────────────────────────────
#
# Tracked docs are the authority and must work in a fresh clone. The local pointer is
# gitignored by design, so checking it first (and doing nothing when absent) made every
# cross-agent handoff depend on machine-local state. Agents then guessed from the newest
# plan file and invented competing MIU schemes.
#
# Resolve the tracked execution record by the CURRENT BRANCH DECLARED INSIDE THE DOC.
# Do not guess from filenames: real repositories contain both EXECUTION.md and
# <feature>-execution.md, and the docs directory slug can differ from the branch slug.
CUR_BRANCH="$(git branch --show-current 2>/dev/null)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
POINTER_PATH="$REPO_ROOT/.claude/pipeline-state.json"
set +e
TRACKED_EXECUTION="$(cd "$REPO_ROOT" && bash "$SCRIPT_DIR/../tools/resolve-feature-doc.sh" execution "" "$CUR_BRANCH")"
TRACKED_RC=$?
set -e
if [[ "$TRACKED_RC" != "0" && "$TRACKED_RC" != "1" ]]; then
  echo "[dev-pipeline] TRACKED HANDOFF AMBIGUOUS — resolver failed closed (rc=$TRACKED_RC). Fix duplicate/conflicting Branch declarations; pointer fallback is forbidden."
  exit 0
fi
POINTER_VALID=0
bash "$SCRIPT_DIR/../tools/pipeline-pointer-valid.sh" "$POINTER_PATH" "$CUR_BRANCH" 2>/dev/null && POINTER_VALID=1
if [[ -z "$TRACKED_EXECUTION" && "$POINTER_VALID" == "1" ]]; then
  POINTER_TASK="$(jq -r '.task // empty' "$POINTER_PATH" 2>/dev/null)"
  TRACKED_EXECUTION="$(cd "$REPO_ROOT" && bash "$SCRIPT_DIR/../tools/resolve-feature-doc.sh" execution "$POINTER_TASK" "" 2>/dev/null || true)"
fi

if [[ -n "$TRACKED_EXECUTION" ]]; then
  TRACKED_EXECUTION_PATH="$TRACKED_EXECUTION"
  [[ "$TRACKED_EXECUTION_PATH" != /* ]] && TRACKED_EXECUTION_PATH="$REPO_ROOT/$TRACKED_EXECUTION_PATH"
  DOC_STATUS="$(sed -n 's/^Status:[[:space:]]*//p' "$TRACKED_EXECUTION_PATH" 2>/dev/null | head -1)"
  DOC_PHASE="$(sed -n 's/^\*\*Current phase:\*\*[[:space:]]*`\([^`]*\)`.*/\1/p' "$TRACKED_EXECUTION_PATH" 2>/dev/null | head -1)"
  DOC_MIU="$(sed -n 's/^\*\*Current\/next MIU:\*\*[[:space:]]*//p' "$TRACKED_EXECUTION_PATH" 2>/dev/null | head -1)"
  [[ -z "$DOC_STATUS" ]] && DOC_STATUS="status not stated"
  [[ -z "$DOC_PHASE" ]] && DOC_PHASE="unknown"
  [[ -z "$DOC_MIU" ]] && DOC_MIU="not stated"
  echo "[dev-pipeline] TRACKED HANDOFF: branch=$CUR_BRANCH phase=$DOC_PHASE status=$DOC_STATUS miu=$DOC_MIU source=$TRACKED_EXECUTION — this tracked record outranks local pointers and other plans."
elif [[ "$POINTER_VALID" == "1" ]] && command -v jq >/dev/null 2>&1; then
  STATE="$(jq -r '"task=" + (.task // "?") + " branch=" + (.branch // "?") + " phase=" + (.phase // "?") + " miu=" + (.currentMiu // "none") + "(" + (.currentMiuStatus // "-") + ")"' "$POINTER_PATH" 2>/dev/null)"
  if [[ -n "$STATE" && "$STATE" != *"task=? branch=?"* ]]; then
    echo "[dev-pipeline] POINTER-ONLY PIPELINE: $STATE — tracked execution handoff not found. Do not invent a plan; run /dev-pipeline:sync to create/reconcile the portable record."
  fi
elif [[ -f "$POINTER_PATH" ]]; then
  echo "[dev-pipeline] STALE POINTER IGNORED — branch/timestamp/remote check failed. Resolve the tracked handoff for the current branch or run /dev-pipeline:sync; do not use its task/MIU fields."
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
if [[ -d .claude/co-review && -f "$SCRIPT_DIR/co-review-nudge.sh" ]]; then
  bash "$SCRIPT_DIR/co-review-nudge.sh" 2>/dev/null | head -5
fi

exit 0
