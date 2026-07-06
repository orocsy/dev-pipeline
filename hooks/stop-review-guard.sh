#!/usr/bin/env bash
# dev-pipeline Stop hook — Rule 2/8 made deterministic.
#
# Blocks the turn from ending while a post-commit AUTO-REVIEW DIRECTIVE is
# unsatisfied: .claude/.auto-review-pending exists AND the current HEAD is not
# blessed (.claude/.last-reviewed-sha != HEAD). Prose rules depend on the model
# noticing; this hook doesn't.
#
# Loop safety: reads stdin JSON; if stop_hook_active is true (we already blocked
# once this turn), always allow the stop — never trap the session in a loop.
# Fail-open on every error path: a broken guard must not brick turn-ending.

set +e

INPUT="$(cat 2>/dev/null)"

# Already continued once because of this hook? Let the turn end.
if printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

# Not a git repo / not a dev-pipeline-managed repo → nothing to guard.
[[ -f .claude/pipeline-state.json ]] || exit 0
[[ -f .claude/.auto-review-pending ]] || exit 0

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)"
[[ -n "$HEAD_SHA" ]] || exit 0

BLESSED=""; [[ -f .claude/.last-reviewed-sha ]] && BLESSED="$(tr -d '[:space:]' < .claude/.last-reviewed-sha)"
if [[ "$BLESSED" == "$HEAD_SHA" ]]; then
  # Blessed — the pending marker is satisfied; clean it up and allow the stop.
  rm -f .claude/.auto-review-pending
  exit 0
fi

PENDING_SHA="$(awk '{print $2}' .claude/.auto-review-pending 2>/dev/null | head -c 12)"
cat <<EOF
{"decision": "block", "reason": "dev-pipeline Stop guard: commit ${PENDING_SHA} has a pending AUTO-REVIEW DIRECTIVE and HEAD is not blessed (.claude/.last-reviewed-sha mismatch). Run /dev-pipeline:review now to bless HEAD (or, for a genuine incident, log an override per docs/RULES.md Emergency Override) — then end the turn."}
EOF
exit 0
