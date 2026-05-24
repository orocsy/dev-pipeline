---
description: Sweep per-project `.learnings/JOURNAL.md` files, classify entries as new-pattern vs refinement, fold into the engineering-craft repo, commit + push to the public mirror. Auto-scheduled via launchd every 2 days (see ~/Library/LaunchAgents/com.luxebook.consolidate-lessons.plist). Safe to run manually any time.
argument-hint: [--dry-run] [--repo <path>]
---

# /dev-pipeline:consolidate-lessons

You are running the **consolidation pass** that turns raw journal entries (captured automatically by the post-commit hook on review-fix commits) into refined patterns inside the engineering-craft repo.

This is the missing automation piece the engineering-craft README has been claiming since 2026-05-12. Don't break the promise.

---

## Inputs

- **Journal sources**: every `<repo>/.learnings/JOURNAL.md` under `~/projects/*/`. Each entry is unconsolidated unless it carries a `<!-- consolidated: YYYY-MM-DD -->` marker.
- **Target repo**: `~/projects/engineering-craft` (override with `--repo <path>`). If absent, clone via `git clone https://github.com/orocsy/engineering-craft.git ~/projects/engineering-craft`.
- **Existing categories**: read `~/projects/engineering-craft/categories/` to learn what rules already exist; classify new entries as refinements or new patterns relative to those.

## Flags

- `--dry-run` — do everything except commit + push. Print proposed changes.
- `--repo <path>` — alternate engineering-craft clone location (default `~/projects/engineering-craft`).

---

## Procedure

### Step 1 — Locate or clone the target repo

```bash
TARGET="${REPO:-$HOME/projects/engineering-craft}"
if [[ ! -d "$TARGET/.git" ]]; then
  git clone https://github.com/orocsy/engineering-craft.git "$TARGET"
fi
git -C "$TARGET" fetch origin && git -C "$TARGET" checkout main && git -C "$TARGET" pull --ff-only
```

If the pull fails (local divergence), STOP and report: "engineering-craft local clone has divergent commits. Resolve manually before consolidating." Do not force-push.

### Step 2 — Collect unconsolidated journal entries

For each `~/projects/*/.learnings/JOURNAL.md`:
- Parse entries (each starts with `## [JNL-<sha7>-<YYYYMMDD>]`)
- Skip entries with `<!-- consolidated: ... -->`
- Build a list `[{repo, sha, date, subject, body, files_changed}]`

If the list is empty, print `No unconsolidated entries since last run.` and exit cleanly.

### Step 3 — Classify each entry against existing categories

Read `~/projects/engineering-craft/INDEX.md` and `~/projects/engineering-craft/categories/*.md` to build a map of existing patterns.

For each entry, decide:

| Verdict | What it means | Action |
|---|---|---|
| `new-pattern` | The entry describes a defensive lesson NOT already in engineering-craft | Create a new `.md` file under `categories/<category>/<slug>.md` with the lesson + SHA citation |
| `refinement` | The entry adds nuance / a new example / a counter-case to an existing pattern | Append an `Example` or `Counter-case` block to the existing rule's file, citing the new SHA |
| `noise` | The entry is too project-specific or doesn't generalize | Skip; still mark consolidated so we don't re-evaluate it next run |

Be conservative — when in doubt, prefer `noise` over a low-quality `new-pattern`. The repo's value is in curation, not volume.

### Step 4 — Apply changes

For `new-pattern`:
- Determine category from the entry's domain (concurrency, multi-tenant, env-vars, time-and-timezone, design-system-drift, etc.)
- Create `categories/<category>/<kebab-slug>.md` with the template at the end of this command
- Update `INDEX.md` with the new entry under its category
- Update `categories/<category>/README.md` if it has a TOC

For `refinement`:
- Edit the existing rule's file in-place
- Add a new `## Example — <date> (<short repo>:<sha7>)` section quoting the commit message + 2-3 line code snippet (extract from the commit's diff)

For `noise`:
- No file change; just the journal marker

### Step 5 — Mark consolidated in each source journal

For every entry processed (any verdict), edit the source `JOURNAL.md` in place: insert `<!-- consolidated: YYYY-MM-DD verdict=<verdict> -->` immediately under the entry's heading. Never delete journal entries — the source-of-truth audit trail stays intact.

### Step 6 — Commit + push (skip on `--dry-run`)

```bash
cd "$TARGET"
git add categories/ INDEX.md
COUNT_NEW=<count of new-pattern>
COUNT_REFINED=<count of refinement>
COUNT_NOISE=<count of noise>

git commit -m "$(cat <<EOF
chore(consolidate): fold $COUNT_NEW patterns + $COUNT_REFINED refinements from $(date -u +%Y-%m-%d)

Source repos:
$(echo "$REPOS_TOUCHED" | sed 's/^/  - /')

Skipped as noise: $COUNT_NOISE
Run: /dev-pipeline:consolidate-lessons
EOF
)"

git push origin main
```

Then commit the journal markers BACK into the source repos (don't push them — let the user push at their normal cadence):
- For each project that had entries consolidated, `git -C <repo> add .learnings/JOURNAL.md` is intentionally NOT auto-committed. Print instead: "Journal markers staged but uncommitted in <N> projects; commit at your convenience."

Actually — to avoid mucking with project working trees from a background-ish command, just edit the JOURNAL.md files in place but DO NOT stage them. The user will commit naturally on next touch.

### Step 7 — Report

Print summary:

```
✓ Consolidation complete

  Source journals scanned: <N>
  Entries processed:       <total>
  → new patterns added:    <count> (files: <list>)
  → refinements applied:   <count> (files: <list>)
  → noise (skipped):       <count>

  engineering-craft pushed: <sha> → https://github.com/orocsy/engineering-craft
  Next scheduled run:       <date> (launchd com.luxebook.consolidate-lessons)
```

---

## New-pattern file template

When creating a new `categories/<category>/<slug>.md`:

```markdown
# <Title — imperative voice, e.g. "Always re-validate slot availability inside the serializable tx">

**Category**: <category-name>
**First seen**: <YYYY-MM-DD> in `<repo>` (`<sha7>`)
**Risk**: <P0/P1/P2 — what breaks if you ignore this>

## The Lesson

<2–4 sentences. What's the pitfall, what's the right pattern. Code-agnostic where possible.>

## Why It Happens

<1–2 sentences on the failure mode. Why the wrong thing looks right.>

## The Fix

```<language>
// ❌ Wrong — <one-line label>
<3–6 line snippet showing the anti-pattern>

// ✅ Right — <one-line label>
<3–6 line snippet showing the correct pattern>
```

## Examples

- <YYYY-MM-DD> (`<repo>:<sha7>`) — <one-line summary of the fix that taught us this>

## See also

- <link to sibling rule if any>
```

---

## Anti-patterns (do NOT do these)

- ❌ Auto-pushing engineering-craft if `git pull --ff-only` failed — surface the divergence, don't force-resolve.
- ❌ Marking entries consolidated WITHOUT actually evaluating them (i.e. don't fake the verdict to clear the backlog).
- ❌ Creating a `new-pattern` file with fewer than 3 sentences in "The Lesson" section — that's a sign the source entry didn't generalize. Mark `noise`.
- ❌ Editing the consolidated-marker on entries already marked — once consolidated, leave it.
- ❌ Bumping into entries that look critical and quietly skipping — if anything feels wrong, STOP and ask the user.

---

## When this runs

- **Scheduled**: launchd plist `com.luxebook.consolidate-lessons` fires every 2 days at 9am, runs a sweep script that COUNTS unconsolidated entries and posts a macOS notification (`23 new entries in 8 repos — run /dev-pipeline:consolidate-lessons`). The actual consolidation is interactive because classification needs LLM judgment.
- **Manual**: any time, with or without `--dry-run`.
- **End of feature**: `/dev-pipeline:learn` may suggest invoking this if it just promoted a learning that looks generalizable.

The scheduled job does NOT auto-run `claude -p` — that path is brittle for an LLM-judgment task. Notification + interactive is the deliberate design.
