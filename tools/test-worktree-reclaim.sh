#!/usr/bin/env bash
# Sandboxed matrix for hooks/worktree-reclaim.sh. Builds a throwaway git repo
# under mktemp with real worktrees + a stubbed `gh`, then asserts each
# deletion-policy cell. NEVER touches a real repo: the hook derives everything
# from CWD, which is pinned inside the sandbox for every invocation.
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd -P)
HOOK="$HERE/hooks/worktree-reclaim.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }

SBX=$(mktemp -d /tmp/wtr-test.XXXXXX)
trap 'rm -rf "$SBX"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok  - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# ── stub gh: returns $GH_STUB_HEAD as the merged PR's headRefOid ──────────
mkdir -p "$SBX/bin"
cat > "$SBX/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${GH_STUB_HEAD:-}"
EOF
chmod +x "$SBX/bin/gh"
export PATH="$SBX/bin:$PATH"

# ── sandbox repo with one commit ─────────────────────────────────────────
REPO="$SBX/repo"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

make_wt() { # name branch
  git -C "$REPO" worktree add -q "$REPO/.claude/worktrees/$1" -b "$2" >/dev/null 2>&1
}
run_hook() { ( cd "$REPO" && WTR_SYNC_RM=1 WTR_MAX_CHECKS=10 bash "$HOOK" ); }

echo "== G: no extra worktrees -> silent, exit 0 =="
OUT=$(run_hook); RC=$?
check "exit 0"        '[ "$RC" = 0 ]'
check "no output"     '[ -z "$OUT" ]'

echo "== A: merged + clean + tip==headRefOid + owned -> DELETED =="
make_wt a-merged wt/a
mkdir -p "$REPO/.claude/worktrees/a-merged/node_modules/x"   # deep tree like real life
TIP=$(git -C "$REPO" rev-parse wt/a)
OUT=$(GH_STUB_HEAD="$TIP" run_hook)
check "dir removed"          '[ ! -e "$REPO/.claude/worktrees/a-merged" ]'
check "deregistered"         '! git -C "$REPO" worktree list | grep -q a-merged'
check "reports reclaim"      'echo "$OUT" | grep -q "reclaimed 1"'
check "branch ref survives"  'git -C "$REPO" rev-parse -q --verify wt/a >/dev/null'

echo "== B: merged + DIRTY -> kept, report =="
make_wt b-dirty wt/b
echo x > "$REPO/.claude/worktrees/b-dirty/junk.txt"
TIP=$(git -C "$REPO" rev-parse wt/b)
OUT=$(GH_STUB_HEAD="$TIP" run_hook)
check "dir kept"             '[ -d "$REPO/.claude/worktrees/b-dirty" ]'
check "uncommitted report"   'echo "$OUT" | grep -q "uncommitted"'
rm -f "$REPO/.claude/worktrees/b-dirty/junk.txt"

echo "== C: merged but tip != PR head (post-merge commits) -> kept, report =="
TIP_OLD=$(git -C "$REPO" rev-parse wt/b)
git -C "$REPO/.claude/worktrees/b-dirty" -c user.email=t@t -c user.name=t commit -q --allow-empty -m extra
OUT=$(GH_STUB_HEAD="$TIP_OLD" run_hook)
check "dir kept"             '[ -d "$REPO/.claude/worktrees/b-dirty" ]'
check "beyond-PR report"     'echo "$OUT" | grep -q "beyond its merged PR"'

echo "== D: no merged PR -> silent, kept =="
OUT=$(GH_STUB_HEAD="" run_hook)
check "dir kept"             '[ -d "$REPO/.claude/worktrees/b-dirty" ]'
check "silent about it"      '! echo "$OUT" | grep -q b-dirty'

echo "== E: merged + clean but OUTSIDE owned prefix -> report-only, kept =="
git -C "$REPO" worktree add -q "$SBX/external-wt" -b wt/e >/dev/null 2>&1
TIP=$(git -C "$REPO" rev-parse wt/e)
OUT=$(GH_STUB_HEAD="$TIP" run_hook)
check "external dir kept"    '[ -d "$SBX/external-wt" ]'
check "manual-reclaim advice" 'echo "$OUT" | grep -q "OUTSIDE .claude/worktrees"'
git -C "$REPO" worktree remove --force "$SBX/external-wt" >/dev/null 2>&1 || true

echo "== F: rm-guard unit tests (function extracted, driven directly) =="
GUARD="$SBX/guard.sh"
{ echo 'MAIN_ROOT="$1"; OWNED_PREFIX="$2"; HOME="${HOME}"; WTR_SYNC_RM=1'
  echo 'git() { command git "${@:2}"; }'   # neutralize -C MAIN_ROOT reregistration check safely below
} > "$GUARD"
# extract the real function verbatim so the test can never drift from the code
sed -n '/^safe_rm_leftover()/,/^}$/p' "$HOOK" >> "$GUARD"
VICTIM="$SBX/victim"; mkdir -p "$VICTIM"; touch "$VICTIM/data"
LINK="$REPO/.claude/worktrees/evil-link"; ln -s "$VICTIM" "$LINK"
( cd "$REPO"; bash -c "source '$GUARD' '$REPO' '$REPO/.claude/worktrees'; safe_rm_leftover '$LINK'" ) && G_RC=0 || G_RC=$?
check "symlink refused (rc!=0)"  '[ "$G_RC" != 0 ]'
check "victim untouched"         '[ -f "$VICTIM/data" ]'
( cd "$REPO"; bash -c "source '$GUARD' '$REPO' '$REPO/.claude/worktrees'; safe_rm_leftover '$SBX/victim'" ) && G_RC=0 || G_RC=$?
check "outside-prefix refused"   '[ "$G_RC" != 0 ] && [ -f "$VICTIM/data" ]'
( cd "$REPO"; bash -c "source '$GUARD' '$REPO' '$REPO/.claude/worktrees'; safe_rm_leftover '/'" ) && G_RC=0 || G_RC=$?
check "root refused"             '[ "$G_RC" != 0 ]'
rm -f "$LINK"

echo "== H: gh unavailable -> report, never delete =="
make_wt h-nogh wt/h
OUT=$( ( cd "$REPO" && WTR_SYNC_RM=1 PATH="/usr/bin:/bin" bash "$HOOK" ) )
check "dir kept"             '[ -d "$REPO/.claude/worktrees/h-nogh" ]'
check "gh-unavailable report" 'echo "$OUT" | grep -q "gh unavailable"'

echo "== I: untracked file hidden by status.showUntrackedFiles=no -> still kept =="
make_wt i-hidden wt/i
echo secret > "$REPO/.claude/worktrees/i-hidden/user-file.txt"
git -C "$REPO/.claude/worktrees/i-hidden" config status.showUntrackedFiles no
TIP=$(git -C "$REPO" rev-parse wt/i)
OUT=$(GH_STUB_HEAD="$TIP" run_hook)
check "dir kept despite config"  '[ -d "$REPO/.claude/worktrees/i-hidden" ]'
check "user file survives"       '[ -f "$REPO/.claude/worktrees/i-hidden/user-file.txt" ]'
check "reported as uncommitted"  'echo "$OUT" | grep -q "uncommitted"'
git -C "$REPO/.claude/worktrees/i-hidden" config --unset status.showUntrackedFiles
rm -f "$REPO/.claude/worktrees/i-hidden/user-file.txt"

echo "== J: gh FAILS (rc!=0) -> lookup-failure report, kept (not silent no-PR) =="
cat > "$SBX/bin/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$SBX/bin/gh"
OUT=$(run_hook)
check "dir kept"                 '[ -d "$REPO/.claude/worktrees/i-hidden" ]'
check "lookup-failure report"    'echo "$OUT" | grep -q "PR lookup failed"'
cat > "$SBX/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${GH_STUB_HEAD:-}"
EOF
chmod +x "$SBX/bin/gh"

echo "== K: capped sweep rotates its start across runs (no starvation) =="
rm -f "$REPO/.git/worktree-reclaim-offset"
( cd "$REPO" && WTR_SYNC_RM=1 WTR_MAX_CHECKS=1 GH_STUB_HEAD="" bash "$HOOK" >/dev/null )
OFF1=$(cat "$REPO/.git/worktree-reclaim-offset" 2>/dev/null)
( cd "$REPO" && WTR_SYNC_RM=1 WTR_MAX_CHECKS=1 GH_STUB_HEAD="" bash "$HOOK" >/dev/null )
OFF2=$(cat "$REPO/.git/worktree-reclaim-offset" 2>/dev/null)
check "offset persisted (in .git, not the checkout)" '[ -n "$OFF1" ]'
check "offset advances"          '[ "$OFF2" != "$OFF1" ]'
check "no reclaim artifact in checkout" '! git -C "$REPO" status --porcelain 2>/dev/null | grep -q "worktree-reclaim"'

echo "== M: DETACHED owned worktree -> reported, never gate-checked or deleted =="
git -C "$REPO" worktree add -q --detach "$REPO/.claude/worktrees/m-detached" >/dev/null 2>&1
OUT=$(GH_STUB_HEAD="" run_hook)
check "detached dir kept"        '[ -d "$REPO/.claude/worktrees/m-detached" ]'
check "detached reported"        'echo "$OUT" | grep -q "DETACHED"'
git -C "$REPO" worktree remove --force "$REPO/.claude/worktrees/m-detached" >/dev/null 2>&1 || true

echo "== O: global deadline stops gh checks, reports the remainder =="
OUT=$( ( cd "$REPO" && WTR_SYNC_RM=1 WTR_DEADLINE=0 GH_STUB_HEAD="" bash "$HOOK" ) )
check "deadline report emitted"  'echo "$OUT" | grep -q "deadline"'
check "nothing deleted"          '[ -d "$REPO/.claude/worktrees/i-hidden" ]'

echo "== L: rm-guard refuses when the worktree listing itself FAILS =="
PLAIN="$REPO/.claude/worktrees/plain-dir"; mkdir -p "$PLAIN"; touch "$PLAIN/data"
# harness git shim mangles args -> listing fails -> guard must fail closed
( cd "$REPO"; bash -c "source '$GUARD' '$REPO' '$REPO/.claude/worktrees'; safe_rm_leftover '$PLAIN'" ) && G_RC=0 || G_RC=$?
check "refused on listing failure" '[ "$G_RC" != 0 ]'
check "dir survives"               '[ -f "$PLAIN/data" ]'
rm -rf "$PLAIN"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
