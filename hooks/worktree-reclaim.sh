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
  elif command -v perl >/dev/null 2>&1; then
    # perl ships on every macOS; alarm+exec is the classic portable watchdog,
    # so a machine with neither coreutils timeout nor gtimeout still gets a
    # bounded call instead of an unbounded gh hanging every session start.
    perl -e 'alarm shift; exec @ARGV' "$GH_TIMEOUT" "$@"
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
reports_pre=()
paths=(); branches=()
cur_path=""; cur_branch=""; cur_locked=0
flush_entry() {
  [ -n "$cur_path" ] || return 0
  if [ "$cur_locked" = "1" ]; then
    # A LOCKED worktree is another session's explicit "hands off" (git
    # worktree lock) — record with a sentinel so it is reported, never gated.
    paths+=("$cur_path"); branches+=("(locked)")
  elif [ -n "$cur_branch" ]; then
    paths+=("$cur_path"); branches+=("$cur_branch")
  fi
  cur_path=""; cur_branch=""; cur_locked=0
}
while IFS= read -r line; do
  case "$line" in
    "worktree "*)  flush_entry; cur_path="${line#worktree }" ;;
    "branch refs/heads/"*) cur_branch="${line#branch refs/heads/}" ;;
    "detached")
      # Detached worktrees are never auto-touched, but they must not vanish
      # from the sweep either — an owned detached worktree eating disk would
      # otherwise stay invisible forever. Record with a sentinel branch.
      cur_branch="(detached)" ;;
    "locked"|"locked "*) cur_locked=1 ;;
    "prunable"|"prunable "*)
      # Stale registration (dir gone / unreachable mount). REPORT it; never
      # auto-prune — `git worktree prune` is repo-wide and would also expire
      # out-of-scope registrations (e.g. a temporarily unmounted volume).
      [ -n "$cur_path" ] && reports_pre+=("worktree-reclaim: stale registration $cur_path (prunable: ${line#prunable}) — run 'git worktree prune' manually if intended")
      cur_path=""; cur_branch=""; cur_locked=0 ;;
    "") flush_entry ;;
  esac
done < <(git -C "$MAIN_ROOT" worktree list --porcelain 2>/dev/null)
flush_entry

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
reports=("${reports_pre[@]+"${reports_pre[@]}"}")

# Rotate the scan start across sessions: with more candidates than the per-run
# gh budget, a stable retained prefix (unmerged/dirty) would otherwise consume
# the cap on EVERY session start and later worktrees would never be checked.
# The offset lives under the GIT COMMON DIR, never in the checkout — a state
# file inside the working tree would dirty every target repo's `git status`
# on every session start.
OFFSET_FILE="$common_dir/worktree-reclaim-offset"
total=${#paths[@]}
start=$(cat "$OFFSET_FILE" 2>/dev/null) || start=0
case "$start" in ''|*[!0-9]*) start=0 ;; esac
[ "$total" -gt 0 ] && start=$(( start % total )) || start=0

# Global deadline (seconds of script runtime): the hook runner enforces its own
# hard timeout; stopping the gh portion early keeps the sweep's tail (reports,
# prune, offset) inside the budget instead of being killed mid-flight silently.
DEADLINE="${WTR_DEADLINE:-12}"

# Arithmetic for-loop, not `seq`: builtin, so it cannot vanish on a lean PATH,
# and an empty substitution can't silently turn the sweep into a no-op.
for (( k = 0; k < total; k++ )); do
  i=$(( (start + k) % total ))
  wt="${paths[$i]}"; br="${branches[$i]}"

  # skip the main worktree and wherever this session lives
  wt_phys=$(cd "$wt" 2>/dev/null && pwd -P) || continue
  [ "$wt_phys" = "$MAIN_ROOT" ] && continue
  case "$PWD_PHYS" in "$wt_phys"|"$wt_phys"/*) continue ;; esac

  owned=0
  case "$wt_phys" in "$OWNED_PREFIX"/?*) owned=1 ;; esac

  # Detached/locked worktrees: never gate-checked, never deleted — but owned
  # ones are surfaced so they can't silently eat disk forever. LOCKED is
  # another session's explicit hands-off (git worktree lock).
  case "$br" in
    "(detached)"|"(locked)")
      [ "$owned" = "1" ] && reports+=("worktree-reclaim: $wt_phys is ${br} — never auto-touched; inspect/remove manually")
      continue ;;
  esac

  # budget: per-run gh cap AND a global deadline (leave tail-work headroom)
  if [ "$checked" -ge "$MAX_CHECKS" ] || [ "${SECONDS:-0}" -ge "$DEADLINE" ]; then
    reports+=("worktree-reclaim: $wt_phys not checked this session (cap $MAX_CHECKS / deadline ${DEADLINE}s)")
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

  # A merged PR does not prove the branch is FINISHED: the same head can also
  # carry an OPEN PR to a different base. Fail-closed on lookup failure.
  open_count=$(run_bounded gh pr list --head "$br" --state open \
                 --json number --jq 'length' 2>/dev/null); op_rc=$?
  if [ "$op_rc" != "0" ]; then
    reports+=("worktree-reclaim: open-PR lookup failed for $br (rc=$op_rc) — $wt_phys left as-is")
    continue
  fi
  if [ "${open_count:-0}" -gt 0 ]; then
    reports+=("worktree-reclaim: $br also has an OPEN PR — kept ($wt_phys)")
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

  # all gates green — attempt NON-FORCE removal: git re-verifies cleanliness
  # and lock state AT THE MOMENT OF REMOVAL, closing the race where another
  # live session wrote files after our status check. Refusal (still
  # registered afterwards) = keep, fail-closed. Note: git may deregister yet
  # fail to delete deep trees like node_modules ("Directory not empty") —
  # that is what the guarded leftover delete below is for.
  git -C "$MAIN_ROOT" worktree remove "$wt_phys" >/dev/null 2>&1
  post_listing=$(git -C "$MAIN_ROOT" worktree list --porcelain 2>/dev/null) || post_listing=""
  if [ -z "$post_listing" ] || grep -Fxq "worktree $wt_phys" <<<"$post_listing"; then
    reports+=("worktree-reclaim: $wt_phys refused non-force removal (dirty/locked since check, or state unknown) — kept")
    continue
  fi
  safe_rm_leftover "$wt_phys" && reclaimed=$((reclaimed + 1)) \
    || reports+=("worktree-reclaim: $wt_phys deregistered but leftover data NOT removed (guard refused)")
done

# NO global `git worktree prune` here — it has no path selector and would also
# expire out-of-scope registrations (see the prunable REPORT in the parser).

# Advance the rotation so next session's sweep starts where this one's gh
# budget ran out. Written ONLY when there was something beyond the main
# worktree to rotate over — a bare repo must not grow state files from merely
# opening a session. Lives in the git common dir, so it never dirties status.
if [ "$total" -gt 1 ]; then
  echo $(( (start + (checked > 0 ? checked : 1)) % total )) > "$OFFSET_FILE" 2>/dev/null || true
fi

[ "$reclaimed" -gt 0 ] && echo "worktree-reclaim: reclaimed $reclaimed merged worktree(s) under .claude/worktrees (data removal continues in background)"
for r in "${reports[@]+"${reports[@]}"}"; do echo "$r"; done
exit 0
