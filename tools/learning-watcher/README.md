# Learning watcher

Turns everyday Claude Code work into reusable practice without waiting for a task to "end".
Every 15 minutes it reads what changed in your session transcripts and writes a short,
redacted journal entry: which skills and commands ran, what went wrong (tool errors and
retry loops, reverts, review findings, your corrections, interruptions), and what went
well (recaps, tests that turned green, commits, praise). Once a day a capped model run
folds the new entries into engineering-craft rules, merges in well-known practice for the
stack (Swift/SwiftUI, NestJS, Next.js, …) with sources cited, and proposes changes to the
task recipes. Everything it writes to a repo lands on a local `learning/inbox` branch that
you review; it never pushes.

## Turning it off

| You want | Do this |
|---|---|
| Pause everything now, keep it installed | `touch ~/.claude/learning/PAUSED` (delete the file to resume) |
| Stop only the daily model run | `launchctl bootout gui/$(id -u)/com.dev-pipeline.learning-watcher.consolidate` |
| Remove it (keep the journal) | `bash tools/learning-watcher/uninstall.sh` |
| Remove it and delete all its data | `bash tools/learning-watcher/uninstall.sh --purge` |

The uninstaller unloads both launchd agents, deletes their plists, removes the pre-push
privacy gates it installed, and removes the inbox checkouts. It keeps the `learning/inbox`
branches, so nothing waiting for review is lost.

## How it runs

```
~/.claude/projects/*/*.jsonl ──(every 15 min, launchd, 0 tokens)──► capture.py
        byte cursor per file · redact · one entry per work burst
                     │
                     ▼
~/.claude/learning/journal/<project>.md   (human-readable, local only)
~/.claude/learning/events/YYYY-MM.jsonl   (same entries, structured)
                     │
        (daily 07:30, launchd; skipped when < 5 new entries)
                     ▼
digest.py ──► digests/<date>.md (≤ 24k chars) ──► claude -p (sonnet, dollar cap, ≤ 40 turns, no shell)
                     │
                     ▼
inbox/engineering-craft  + inbox/dev-pipeline   (worktrees on branch learning/inbox)
        privacy_lint.py on the diff → clean: local commit · any hit: diff saved to rejected/, discarded
                     │
                     ▼
reports/<date>.md + a macOS notification. You review, merge into main, push.
```

**Why launchd.** It runs whenever the Mac is on and you are logged in, whether or not a
Claude session, the desktop app or a hook is running, and it catches up after sleep. Hook-based
capture missed work because hooks fire only on particular events in particular sessions;
end-of-task consolidation rarely ran because tasks never really end. The desktop app's
scheduled tasks were the other candidate, but they need the app open and give no hard
spending cap; `claude -p --max-budget-usd` does.

**Cheap by construction.**
- Capture is plain Python, no model: it reads only bytes added since its cursor, skips the
  bulky request records without parsing them, and reads at most 160 MB per run (about a second).
  A session still being written is left until it has been idle 20 minutes, so entries land per
  work burst, not per tick.
- Idempotent: entry IDs are `W-<session>-<byte offset>`; an ID already in `events/` is never
  written twice, so a crash between writing and saving the cursor cannot duplicate an entry.
- Consolidation reads only the digest (capped at 24,000 characters, about 6k tokens), runs a
  smaller model, is hard-capped in dollars and turns, and is skipped entirely when there is
  little new to learn from. Tune it all in `~/.claude/learning/config.env`.

## Privacy

Transcripts contain keys, emails, client names and business details. Two layers keep them out
of anything shared:

1. **Redaction before writing** (`redact.py`). Every excerpt in the journal has keys, tokens,
   credentials, emails, phone numbers, prices, IPs, payment-provider IDs and home paths replaced,
   plus every `[always]` term in `~/.claude/learning/private-terms.txt`. The journal sits in the
   same private folder as the transcripts it came from and is never committed.
2. **A hard gate before git** (`privacy_lint.py`). It refuses any added line containing the
   above, any private term (both sections), a domain that is not on `domain-allowlist.txt`,
   a bundle ID, a user path, or a common given name; for the public engineering-craft mirror it
   also refuses CJK text. It runs on every consolidation diff (a hit discards that repo's whole
   change) and as a **pre-push hook** in engineering-craft and dev-pipeline, so a session pushing
   by hand is checked too. A line you have checked can carry `privacy-lint: allow <why>`;
   `PRIVACY_LINT_SKIP=1 git push` skips the hook for one push.

Add the names that matter to you to `private-terms.txt`: children's and customers' names,
client and company names, domains, product names. `[git-only]` terms stay readable in your
local journal but can never reach a remote.

## Files

| Path | What |
|---|---|
| `capture.py` | transcript → journal (launchd, every 15 min) |
| `redact.py` | tier-1 redaction + tier-2 findings |
| `privacy_lint.py` | the git gate (`--git-range`, `--git-worktree`, `--files`, `--stdin`) |
| `digest.py` | pending entries → capped digest; recipe stats; `--mark-consolidated` |
| `consolidate.sh` + `consolidate-prompt.md` | the daily model run |
| `sources.json` | public references per stack the model prefers and cites |
| `given-names.txt`, `domain-allowlist.txt` | lint word lists |
| `git-hooks/pre-push-privacy` | the pre-push gate |
| `install.sh`, `uninstall.sh` | set up / remove |

Installed copy and data: `~/.claude/learning/` (`bin/`, `journal/`, `events/`, `digests/`,
`reports/`, `rejected/`, `inbox/`, `state/`, `logs/`). launchd runs the copy in `bin/`, so a
branch switch in the plugin checkout cannot break the schedule; re-run `install.sh` after
updating the plugin.

## Recipes

The router picks a recipe from `recipes/recipes.json` and announces `Recipe: <id> — …`.
Capture records the announced recipe (or infers one from the commands used; `ad-hoc` when no
dev-pipeline command ran), and `digest.py` keeps 30-day outcomes per recipe in
`state/recipe-stats.json`: completion rate, corrections, errors, reverts and interruptions per
session. The daily run proposes a recipe change only with evidence from at least 3 sessions,
edits `recipes.json` on the inbox branch and logs it in `recipes/CHANGES.md`. After merging,
run `python3 tools/render-recipes.py` to refresh the router tables.

## Everyday commands

```bash
python3 ~/.claude/learning/bin/capture.py              # capture now
python3 ~/.claude/learning/bin/capture.py --dry-run    # print what it would write
bash ~/.claude/learning/bin/consolidate.sh --dry-run   # build today's digest, no model
bash ~/.claude/learning/bin/consolidate.sh --force     # run consolidation now
tail ~/.claude/learning/logs/capture.log ~/.claude/learning/logs/consolidate.log
git -C ~/.claude/skills/engineering-craft log --oneline main..learning/inbox
```

## Limits

- Detection is heuristic. "User correction" is a short message that starts like one ("no",
  "don't", "why…", "不对", …); praise and approvals are matched the same way. The model step
  is told to treat them as leads, not facts.
- A name the lint has never heard of, written in plain English, can only be caught by
  `private-terms.txt` or by the model following its instructions. Review the inbox diff before
  you push; the gate is a backstop, not a guarantee.
- If the Mac is off at 07:30, launchd runs the missed consolidation on wake.
