#!/usr/bin/env python3
"""privacy_lint -- hard gate for anything bound for git.

Blocks (exit 1) when text contains secrets, credentials, emails, phone numbers,
prices, IPs, payment-provider IDs, absolute user paths, bundle IDs, unknown
domains, common given names or any term from ~/.claude/learning/private-terms.txt.
With --public (the engineering-craft mirror) CJK text is blocked too.

Modes (pick one):
  --files F [F ...]        scan whole files
  --stdin                  scan stdin
  --git-range A..B         scan lines ADDED between two commits (pre-push)
  --git-worktree           scan uncommitted + untracked changes vs HEAD
  --repo DIR               repo for the git modes (default: cwd)

A line containing `privacy-lint: allow` is skipped (use sparingly; say why on
the same line). Exit codes: 0 clean, 1 findings, 2 usage/git error.
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import redact  # noqa: E402

ALLOW_MARK = "privacy-lint: allow"
# The lint's own word lists and its deliberately-dirty test fixtures.
DEFAULT_EXCLUDES = ("*learning-watcher/given-names.txt", "*learning-watcher/tests/*")


def _git(repo: str, *args: str) -> str:
    return subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True, text=True).stdout


def _added_lines(diff: str):
    file = None
    lineno = 0
    for line in diff.splitlines():
        if line.startswith("+++ "):
            file = line[6:] if line.startswith("+++ b/") else line[4:]
            continue
        if line.startswith("@@"):
            # @@ -a,b +c,d @@
            try:
                plus = line.split("+", 1)[1].split(" ", 1)[0]
                lineno = int(plus.split(",")[0]) - 1
            except (IndexError, ValueError):
                lineno = 0
            continue
        if line.startswith("+") and not line.startswith("+++"):
            lineno += 1
            yield file or "?", lineno, line[1:]
        elif not line.startswith("-"):
            lineno += 1


def _file_lines(paths):
    for p in paths:
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    yield p, i, line.rstrip("\n")
        except (IsADirectoryError, FileNotFoundError):
            continue


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--files", nargs="+")
    g.add_argument("--stdin", action="store_true")
    g.add_argument("--git-range")
    g.add_argument("--git-worktree", action="store_true")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--public", action="store_true", help="also block CJK text (public mirror)")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--exclude", action="append", help="glob of paths to skip (repeatable)")
    a = ap.parse_args(argv)

    try:
        if a.files:
            lines = _file_lines(a.files)
        elif a.stdin:
            lines = (("<stdin>", i, l.rstrip("\n")) for i, l in enumerate(sys.stdin, 1))
        elif a.git_range:
            lines = _added_lines(_git(a.repo, "diff", "--no-color", "--unified=0", a.git_range))
        else:
            diff = _git(a.repo, "diff", "--no-color", "--unified=0", "HEAD")
            untracked = [f for f in _git(a.repo, "ls-files", "--others", "--exclude-standard").splitlines() if f]
            lines = list(_added_lines(diff)) + list(_file_lines([os.path.join(a.repo, f) for f in untracked]))
    except subprocess.CalledProcessError as e:
        print(f"privacy-lint: git failed: {e.stderr.strip()}", file=sys.stderr)
        return 2

    excludes = DEFAULT_EXCLUDES + tuple(a.exclude or ())
    filtered = ((f, n, t) for f, n, t in lines
                if ALLOW_MARK not in t
                and not any(fnmatch.fnmatch(f, pat) or fnmatch.fnmatch(os.path.abspath(f), pat) for pat in excludes))
    hits = list(redact.iter_hits(filtered, public=a.public))
    if not hits:
        if not a.quiet:
            print("privacy-lint: clean")
        return 0
    print(f"privacy-lint: {len(hits)} finding(s) — this text must not reach git:", file=sys.stderr)
    for f, n, rule, match in hits[:200]:
        shown = match if len(match) <= 60 else match[:57] + "..."
        print(f"  {f}:{n}: [{rule}] {shown}", file=sys.stderr)
    if len(hits) > 200:
        print(f"  ... and {len(hits) - 200} more", file=sys.stderr)
    print("Fix: rewrite generically (no names, domains, prices, keys), or add a public domain to "
          "domain-allowlist.txt. Last resort: `privacy-lint: allow <why>` on the line.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
