#!/usr/bin/env bash
# worktree-reclaim.sh — SessionStart sweep: reclaim agent worktrees whose PR
# has MERGED. Born from a real incident: 3.6 GB of merged-PR worktrees
# (node_modules and all) silently accumulated under .claude/worktrees/ across
# crashed/ended sessions, invisible to Finder and to post-merge-only cleanup.
#
# DELETION POLICY (the whole point — read before editing):
#   AUTO-DELETE requires ALL of:
#     G1  the worktree's branch has a MERGED PR (gh, per-call timeout)
#     G2  zero uncommitted changes in the worktree
#     G3  the local branch tip EQUALS the merged PR's headRefOid — nothing
#         landed on the branch after (or outside) what the PR merged. This is
#         squash-merge-proof, where "commits reachable from main" never holds.
#     G4  the directory physically resolves INSIDE <main-root>/.claude/worktrees/
#         (the only tree this hook owns). Everything else — sibling clones,
#         /tmp checkouts, codex dirs — is REPORT-ONLY, never deleted.
#   Any gate unknown (gh missing, timeout, no PR found) => report-only.
#   The hook must never block a session: no set -e; every failure degrades
#   to silence or a one-line report.
#
# rm -rf SAFETY (defense in depth, in order):
#   1. `git worktree remove` runs FIRST — git's own checks + deregistration.
#      Its exit code is NOT trusted for the data (it chokes on node_modules
#      with "Directory not empty"), only for the deregistration.
#   2. The leftover path is then re-verified: physical realpath (symlinks
#      refused), inside the owned prefix, not /, not $HOME, not a repo root,
#      minimum path depth, and NO LONGER present in `git worktree list`.
#   3. Only then: `rm -rf --` on the canonical path, in the background
#      (node_modules trees take tens of seconds; the hook has a 15s budget).
#
# Env (test hooks): WTR_SYNC_RM=1 run rm in foreground; WTR_MAX_CHECKS=N cap
# gh-verified candidates per run (default 3); WTR_GH_TIMEOUT secs (default 5).

set -uo pipefail

MAX_CHECKS="${WTR_MAX_CHECKS:-3}"
GH_TIMEOUT="${WTR_GH_TIMEOUT:-5}"

# macOS ships no `timeout` (coreutils installs gtimeout). Fall back to a bare
# run rather than silently disabling the hook — the gh call is the only
# network hop and gh has its own connect timeouts.
run_bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout "$GH_TIMEOUT" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$GH_TIMEOUT" "$@"
  else "$@"
  fi
}

# ── locate the MAIN worktree root (works when CWD is itself a worktree) ──
common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
case "$common_dir" in
  */.git) MAIN_ROOT="${common_dir%/.git}" ;;
  *)      exit 0 ;;  # bare/odd layout — not our territory
esac
[ -d "$MAIN_ROOT" ] || exit 0
MAIN_ROOT=$(cd "$MAIN_ROOT" && pwd -P) || exit 0
OWNED_PREFIX="$MAIN_ROOT/.claude/worktrees"
PWD_PHYS=$(pwd -P)

# ── parse worktrees (porcelain: stable machine format) ──────────────────
# Arrays kept index-aligned.
paths=(); branches=()
cur_path=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*)  cur_path="${line#worktree }" ;;
    "branch refs/heads/"*)
      b="${line#branch refs/heads/}"
      if [ -n "$cur_path" ]; then paths+=("$cur_path"); branches+=("$b"); fi
      cur_path="" ;;
    "detached")    cur_path="" ;;  # detached worktrees are never auto-touched
  esac
done < <(git -C "$MAIN_ROOT" worktree list --porcelain 2>/dev/null)

[ "${#paths[@]}" -gt 0 ] || exit 0

# ── the guarded delete: every check re-verified at the moment of deletion ──
safe_rm_leftover() {
  local t="$1" phys
  [ -n "$t" ]  || return 1
  [ -e "$t" ]  || return 0            # nothing left — done
  [ -L "$t" ]  && return 1            # never operate through a symlink
  [ -d "$t" ]  || return 1
  phys=$(cd "$t" 2>/dev/null && pwd -P) || return 1
  case "$phys" in
    "$OWNED_PREFIX"/?*) ;;            # strictly INSIDE the owned dir
    *) return 1 ;;
  esac
  [ "$phys" = "/" ] && return 1
  [ "$phys" = "${HOME:-/nonexistent}" ] && return 1
  [ "$phys" = "$MAIN_ROOT" ] && return 1
  # depth guard: owned prefix + at least one real component
  case "$phys" in
    */.claude/worktrees/*/*) : ;;     # deeper is fine
    */.claude/worktrees/*) : ;;       # exactly one component — expected shape
    *) return 1 ;;
  esac
  # must be deregistered from git by now — a live worktree is never rm'd.
  # Capture the listing first, THEN match: piping into `grep -q` lets an early
  # match SIGPIPE git (rc 141), and under pipefail that inverts this guard —
  # the still-registered branch would fall through to rm. A failed listing is
  # equally a refusal (fail-closed): unknown registration state = do not delete.
  local listing
  listing=$(git -C "$MAIN_ROOT" worktree list --porcelain 2>/dev/null) || return 1
  if grep -Fxq "worktree $phys" <<<"$listing"; then
    return 1
  fi
  if [ "${WTR_SYNC_RM:-0}" = "1" ]; then
    rm -rf -- "$phys"
  else
    nohup rm -rf -- "$phys" >/dev/null 2>&1 &
  fi
}

checked=0 reclaimed=0
reports=()

# Rotate the scan start across sessions: with more candidates than the per-run
# gh budget, a stable retained prefix (unmerged/dirty) would otherwise consume
# the cap on EVERY session start and later worktrees would never be checked.
OFFSET_FILE="$MAIN_ROOT/.claude/.worktree-reclaim-offset"
total=${#paths[@]}
start=$(cat "$OFFSET_FILE" 2>/dev/null) || start=0
case "$start" in ''|*[!0-9]*) start=0 ;; esac
[ "$total" -gt 0 ] && start=$(( start % total )) || start=0

for k in $(seq 0 $(( total - 1 ))); do
  i=$(( (start + k) % total ))
  wt="${paths[$i]}"; br="${branches[$i]}"

  # skip the main worktree and wherever this session lives
  wt_phys=$(cd "$wt" 2>/dev/null && pwd -P) || continue
  [ "$wt_phys" = "$MAIN_ROOT" ] && continue
  case "$PWD_PHYS" in "$wt_phys"|"$wt_phys"/*) continue ;; esac

  owned=0
  case "$wt_phys" in "$OWNED_PREFIX"/?*) owned=1 ;; esac

  # budget: only the first N candidates get a gh round-trip
  if [ "$checked" -ge "$MAX_CHECKS" ]; then
    reports+=("worktree-reclaim: $wt_phys not checked this session (per-run cap $MAX_CHECKS)")
    continue
  fi
  checked=$((checked + 1))

  # G1+G3 in one call: merged PR whose headRefOid matches the local tip.
  # A FAILED lookup (auth/network/timeout) is not the same as "no merged PR" —
  # report it, so an operator can tell a genuinely-active branch from a sweep
  # that never completed. Only a SUCCESSFUL empty result stays silent.
  command -v gh >/dev/null 2>&1 || { reports+=("worktree-reclaim: gh unavailable — $wt_phys left as-is"); continue; }
  pr_head=$(run_bounded gh pr list --head "$br" --state merged \
              --json headRefOid --jq '.[0].headRefOid // empty' 2>/dev/null); gh_rc=$?
  if [ "$gh_rc" != "0" ]; then
    reports+=("worktree-reclaim: PR lookup failed for $br (rc=$gh_rc, timeout=124) — $wt_phys left as-is")
    continue
  fi
  [ -n "$pr_head" ] || continue      # confirmed: no merged PR — active work; stay silent

  local_tip=$(git -C "$MAIN_ROOT" rev-parse "refs/heads/$br" 2>/dev/null) || continue
  if [ "$local_tip" != "$pr_head" ]; then
    reports+=("worktree-reclaim: $br has commits beyond its merged PR — kept ($wt_phys)")
    continue
  fi

  # G2: pristine tree. The check must itself SUCCEED (a failed `git status`
  # yields empty output, which must never read as "clean"), and untracked
  # files are requested explicitly — a worktree-local
  # `status.showUntrackedFiles=no` would otherwise hide a user's file from
  # the pristine check and the sweep would delete it.
  wt_status=$(git -C "$wt_phys" status --porcelain --untracked-files=all 2>/dev/null); st_rc=$?
  if [ "$st_rc" != "0" ]; then
    reports+=("worktree-reclaim: status check failed for $wt_phys (rc=$st_rc) — kept")
    continue
  fi
  if [ -n "$wt_status" ]; then
    reports+=("worktree-reclaim: $br PR merged but worktree has uncommitted changes — kept ($wt_phys)")
    continue
  fi

  if [ "$owned" != "1" ]; then
    reports+=("worktree-reclaim: $wt_phys ($br, PR merged, clean) is OUTSIDE .claude/worktrees — reclaim manually: git worktree remove '$wt_phys'")
    continue
  fi

  # all gates green — deregister, then guarded delete of leftovers
  git -C "$MAIN_ROOT" worktree remove --force "$wt_phys" >/dev/null 2>&1
  safe_rm_leftover "$wt_phys" && reclaimed=$((reclaimed + 1)) \
    || reports+=("worktree-reclaim: $wt_phys deregistered but leftover data NOT removed (guard refused)")
done

git -C "$MAIN_ROOT" worktree prune >/dev/null 2>&1

# Advance the rotation so next session's sweep starts where this one's gh
# budget ran out (harmless when everything fit under the cap).
if [ "$total" -gt 0 ]; then
  mkdir -p "$MAIN_ROOT/.claude" 2>/dev/null
  echo $(( (start + (checked > 0 ? checked : 1)) % total )) > "$OFFSET_FILE" 2>/dev/null || true
fi

[ "$reclaimed" -gt 0 ] && echo "worktree-reclaim: reclaimed $reclaimed merged worktree(s) under .claude/worktrees (data removal continues in background)"
for r in "${reports[@]+"${reports[@]}"}"; do echo "$r"; done
exit 0
