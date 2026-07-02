#!/usr/bin/env bash
# co-review-nudge.sh — OPT-IN session-start nudge for /dev-pipeline:co-review.
#
# Sourced by ~/.claude/hooks/session-start.sh (or run standalone). Does NOTHING unless the
# current project opted in with `touch .claude/co-review/enabled`. When enabled, it does a
# lightweight, fail-safe cursor-compare per channel and prints a CO-REVIEW PENDING directive
# if another agent left new input since our last cursor. It NEVER auto-runs the command and
# NEVER fails the session start (all errors swallowed). See CLAUDE.md Rule 21.

# Resolve the project root (the dir that holds .claude/); tolerate being sourced from anywhere.
_cr_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
[ -f "$_cr_root/.claude/co-review/enabled" ] || return 0 2>/dev/null || exit 0

_cr_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Iterate channel configs (<channel>.json, excluding the .cursor.json siblings).
for _cfg in "$_cr_root"/.claude/co-review/*.json; do
  [ -e "$_cfg" ] || continue
  case "$_cfg" in *.cursor.json) continue ;; esac
  command -v jq >/dev/null 2>&1 || continue

  _ch="$(jq -r '.channel // empty' "$_cfg" 2>/dev/null)"
  [ -n "$_ch" ] || continue
  _cur="$_cr_root/.claude/co-review/${_ch}.cursor.json"
  _pending=0
  _detail=""

  # Each source: is there input newer than our cursor?
  while IFS=$'\t' read -r _sid _adapter _pr _bot _docpath; do
    [ -n "$_sid" ] || continue
    case "$_adapter" in
      gh-pr-bot)
        command -v gh >/dev/null 2>&1 || continue
        [ "${_pr:-0}" != "0" ] && [ -n "${_pr:-}" ] || continue
        _c="$(jq -r --arg s "$_sid" '.sources[$s].cursor // "1970-01-01T00:00:00Z"' "$_cur" 2>/dev/null || echo '1970-01-01T00:00:00Z')"
        _repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || continue
        _n="$(gh api "repos/$_repo/pulls/$_pr/comments" --jq "[.[] | select(.user.login==\"$_bot\") | select(.created_at > \"$_c\")] | length" 2>/dev/null || echo 0)"
        # Also count submitted PR REVIEWS, not just inline comments — a review-only pass
        # (approve/comment with no inline threads) would otherwise never surface the nudge,
        # even though the gh-pr-bot adapter itself treats reviews as review input too.
        _nr="$(gh api "repos/$_repo/pulls/$_pr/reviews" --jq "[.[] | select(.user.login==\"$_bot\") | select(.submitted_at > \"$_c\")] | length" 2>/dev/null || echo 0)"
        _n=$(( ${_n:-0} + ${_nr:-0} ))
        if [ "${_n:-0}" -gt 0 ] 2>/dev/null; then _pending=1; _detail="${_detail} ${_sid}(+${_n} on PR#${_pr})"; fi
        ;;
      doc)
        [ -n "${_docpath:-}" ] && [ -f "$_cr_root/$_docpath" ] || continue
        _c="$(jq -r --arg s "$_sid" '.sources[$s].cursor // empty' "$_cur" 2>/dev/null)"
        if [ -n "$_c" ]; then
          _n="$(git -C "$_cr_root" log --oneline "${_c}..HEAD" -- "$_docpath" 2>/dev/null | wc -l | tr -d ' ')"
        else
          _n=1  # never synced → treat as pending
        fi
        if [ "${_n:-0}" -gt 0 ] 2>/dev/null; then _pending=1; _detail="${_detail} ${_sid}(doc updated)"; fi
        ;;
    esac
  done < <(jq -r '.sources[] | [.id, .adapter, (.pr//0|tostring), (.botLogin//""), (.path//"")] | @tsv' "$_cfg" 2>/dev/null)

  if [ "$_pending" = "1" ]; then
    printf '──────────────────────────────────────────────\n'
    printf '🤝 CO-REVIEW PENDING — channel %s\n' "$_ch"
    printf '   New review input since your last pass:%s\n' "$_detail"
    printf '   Run  /dev-pipeline:co-review %s  to integrate.\n' "$_ch"
    printf '   (suggestion only — not auto-run; disable with rm .claude/co-review/enabled)\n'
    printf '──────────────────────────────────────────────\n'
  fi
done

unset _cr_root _cr_now _cfg _ch _cur _pending _detail _sid _adapter _pr _bot _docpath _c _repo _n _nr
return 0 2>/dev/null || exit 0
