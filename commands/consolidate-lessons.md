---
description: Sweep per-project `.learnings/JOURNAL.md` files, classify entries as new-pattern vs refinement, fold into the engineering-craft repo, commit + push to the public mirror. Auto-scheduled via launchd every 2 days (see ~/Library/LaunchAgents/com.engineering-craft.consolidation-reminder.plist). Safe to run manually any time.
argument-hint: "[--dry-run] [--repo <path>]"
---

# /dev-pipeline:consolidate-lessons

You are running the **consolidation pass** that turns raw journal entries (captured automatically by the post-commit hook on review-fix commits) into refined patterns inside the engineering-craft repo.

This is the missing automation piece the engineering-craft README has been claiming since 2026-05-12. Don't break the promise.

---

## Inputs

- **Journal sources**: every `<repo>/.learnings/JOURNAL.md` under `~/projects/*/`. Each entry is unconsolidated unless it carries a `<!-- consolidated: YYYY-MM-DD -->` marker.
- **Target repo**: resolve in this order:
  1. `--repo <path>` flag (explicit override always wins)
  2. `MIRROR_DIR` from `~/.claude/skills/engineering-craft/.public-mirror-config` if that file exists (this is what `bootstrap/install.sh` writes when the engineering-craft fresh-machine bootstrap has been run)
  3. Default: `~/.claude/external-mirrors/engineering-craft` (matches the bootstrap's `MIRROR_DIR` convention so things just work on machines that ran the bootstrap)
  4. Last-resort fallback for ad-hoc setups: `~/projects/engineering-craft`

  If none of the above directories contain a `.git`, clone via `git clone https://github.com/orocsy/engineering-craft.git <chosen-path>`.
- **Existing categories**: read `$TARGET/categories/` (the resolved target — see Step 1) to learn what rules already exist; classify new entries as refinements or new patterns relative to those.

## Flags

- `--dry-run` — do everything except commit + push. Print proposed changes.
- `--repo <path>` — alternate engineering-craft clone location. Default is resolved by the Step 1 chain (bootstrap's `.public-mirror-config` → `~/.claude/external-mirrors/engineering-craft` → legacy `~/projects/engineering-craft`).

---

## Procedure

### Step 1 — Locate or clone the target repo

```bash
# Resolution order: --repo flag > .public-mirror-config > bootstrap default > legacy fallback
if [[ -n "${REPO:-}" ]]; then
  TARGET="$REPO"
elif [[ -f "$HOME/.claude/skills/engineering-craft/.public-mirror-config" ]]; then
  TARGET="$(grep -E '^MIRROR_DIR=' "$HOME/.claude/skills/engineering-craft/.public-mirror-config" | cut -d= -f2- | tr -d '"')"
elif [[ -d "$HOME/.claude/external-mirrors/engineering-craft/.git" ]]; then
  TARGET="$HOME/.claude/external-mirrors/engineering-craft"
else
  TARGET="$HOME/projects/engineering-craft"  # legacy fallback for ad-hoc clones
fi

if [[ ! -d "$TARGET/.git" ]]; then
  mkdir -p "$(dirname "$TARGET")"
  git clone https://github.com/orocsy/engineering-craft.git "$TARGET"
fi
git -C "$TARGET" fetch origin && git -C "$TARGET" checkout main && git -C "$TARGET" pull --ff-only

# The plugin itself is the CANONICAL home for cross-file-seam lessons.
# Resolve its path too — Step 4 may append to it, and Step 4.5 publishes it.
PLUGIN_DIR="$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline"
FAILURE_MODES="$PLUGIN_DIR/skills/cross-file-reasoning/FAILURE_MODES.md"
```

If the pull fails (local divergence), STOP and report: "engineering-craft local clone has divergent commits. Resolve manually before consolidating." Do not force-push.

### Step 2 — Collect unconsolidated journal entries

For each `~/projects/*/.learnings/JOURNAL.md`:
- Parse entries (each starts with `## [JNL-<sha7>-<YYYYMMDD>]`)
- Skip entries with `<!-- consolidated: ... -->`
- Build a list `[{repo, sha, date, subject, body, files_changed}]`

If the list is empty, print `No unconsolidated entries since last run.` and exit cleanly.

### Step 3 — Classify each entry against existing categories

Read `$TARGET/INDEX.md` and `$TARGET/categories/*.md` to build a map of existing patterns.

For each entry, decide:

| Verdict | What it means | Action |
|---|---|---|
| `cross-file` | The entry is a cross-file-seam failure mode (see the routing note below) | Canonical home is `$FAILURE_MODES` in the plugin — append there if new, no-op if already present. Do NOT touch an engineering-craft category. Mirrored to `cross-file-seams` in Step 4.5. |
| `new-pattern` | A NON-cross-file defensive lesson NOT already in engineering-craft | Create a new `.md` file under `categories/<category>/<slug>.md` with the lesson + SHA citation |
| `refinement` | The entry adds nuance / a new example / a counter-case to an existing pattern | Append an `Example` or `Counter-case` block to the existing rule's file, citing the new SHA |
| `noise` | The entry is too project-specific or doesn't generalize | Skip; still mark consolidated so we don't re-evaluate it next run |

Be conservative — when in doubt, prefer `noise` over a low-quality `new-pattern`. The repo's value is in curation, not volume.

**Cross-file-seam entries route to the plugin, NOT to an engineering-craft category.** `$FAILURE_MODES` (the `cross-file-reasoning` skill's catalog) is the single CANONICAL home for cross-file-seam failure modes — env-var empty-string collapse, framework-prefix doubling, SDK-option-unverified, conditional coupling, in-tx fire-and-forget, wrapper-lifecycle, mock drift, single-place-fix blindness, etc. engineering-craft's `categories/cross-file-seams/` is a GENERATED mirror of that file (published in Step 4.5), so do NOT create or refine a cross-file rule directly under any engineering-craft category. Instead, for an entry classified as a cross-file seam:

- **Verdict `cross-file`** (a 4th verdict, alongside new-pattern/refinement/noise): the lesson is a cross-file seam.
  - If `$FAILURE_MODES` already contains the general form (it usually will — the skill appends live mid-trace) → no write needed; mark the journal entry consolidated with `verdict=cross-file-already`.
  - If it's genuinely new → append a new numbered entry to `$FAILURE_MODES` (Pattern / Anti-pattern / Correct / Examples — match the existing format) and update that file's Index. Mark the journal entry `verdict=cross-file-new`.
- **Do NOT** also write it into `config-drift` / `grep-for-siblings` / etc. Those hand-authored categories own the DEEPER, broader treatment of adjacent topics (e.g. the full 4-consumer rule); the cross-file catalog owns the operational seam check. One fact, one home. Cross-link, don't copy.

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

For `cross-file`:
- Handled against `$FAILURE_MODES` per the routing note above (append-if-new, else no-op). The mirror into engineering-craft happens in Step 4.5, not here.

### Step 4.5 — Publish the cross-file catalog to the mirror (one-way)

`$FAILURE_MODES` is canonical; engineering-craft's `cross-file-seams` category is its published mirror. Regenerate the mirror from the canonical file every run (cheap, idempotent — a no-op commit if nothing changed):

```bash
MIRROR_DIR="$TARGET/categories/cross-file-seams"
mkdir -p "$MIRROR_DIR"

# 1. Copy the canonical catalog verbatim, with a generated-by banner prepended.
{
  echo "<!-- GENERATED — DO NOT EDIT."
  echo "     Canonical source: dev-pipeline plugin skills/cross-file-reasoning/FAILURE_MODES.md"
  echo "     Published by /dev-pipeline:consolidate-lessons on $(date -u +%Y-%m-%d)."
  echo "     Hand-edits here are overwritten on the next consolidation. Edit the plugin instead. -->"
  echo ""
  cat "$FAILURE_MODES"
} > "$MIRROR_DIR/FAILURE_MODES.md"

# 2. The category README is hand-authored once (see Step 4.5a) — leave it.
#    Only refresh its "last synced" line.
git -C "$TARGET" add categories/cross-file-seams/
```

If `$FAILURE_MODES` was also appended this run (a `cross-file-new` verdict), commit the PLUGIN repo too — it's the canonical change:

```bash
if ! git -C "$PLUGIN_DIR" diff --quiet -- skills/cross-file-reasoning/FAILURE_MODES.md; then
  git -C "$PLUGIN_DIR" add skills/cross-file-reasoning/FAILURE_MODES.md
  git -C "$PLUGIN_DIR" commit -m "feat(cross-file-reasoning): +<N> failure mode(s) from consolidation $(date -u +%Y-%m-%d)"
  # Push the plugin only if the user's review gate allows; otherwise print a reminder.
  git -C "$PLUGIN_DIR" push origin main 2>&1 || echo "⚠ plugin push deferred — push $PLUGIN_DIR manually"
fi
```

**Step 4.5a (first run only)**: if `categories/cross-file-seams/README.md` does not exist, create it as a hand-authored category index (generated marker + what's here + cross-links to the deeper `config-drift` / `grep-for-siblings` categories). It is NOT regenerated after that — only `FAILURE_MODES.md` inside the category is.

### Step 5 — Mark consolidated in each source journal

For every entry processed (any verdict), edit the source `JOURNAL.md` in place: insert `<!-- consolidated: YYYY-MM-DD verdict=<verdict> -->` immediately under the entry's heading. Never delete journal entries — the source-of-truth audit trail stays intact.

### Step 6 — Commit + push (skip on `--dry-run`)

```bash
cd "$TARGET"
git add categories/ INDEX.md   # categories/ includes the regenerated cross-file-seams mirror
COUNT_NEW=<count of new-pattern>
COUNT_REFINED=<count of refinement>
COUNT_NOISE=<count of noise>
COUNT_XFILE=<count of cross-file-new>   # mirrored from the plugin's canonical catalog

git commit -m "$(cat <<EOF
chore(consolidate): fold $COUNT_NEW patterns + $COUNT_REFINED refinements + $COUNT_XFILE cross-file from $(date -u +%Y-%m-%d)

Source repos:
$(echo "$REPOS_TOUCHED" | sed 's/^/  - /')

Cross-file mirror regenerated from dev-pipeline FAILURE_MODES.md.
Skipped as noise: $COUNT_NOISE
Run: /dev-pipeline:consolidate-lessons
EOF
)"

git push origin main
```

(The plugin repo's own commit — when a `cross-file-new` entry was appended to the canonical `$FAILURE_MODES` — already happened in Step 4.5. This Step 6 commit is the engineering-craft side only.)

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
  → cross-file (canonical): <count> appended to plugin FAILURE_MODES.md; mirror regenerated
  → noise (skipped):       <count>

  engineering-craft pushed: <sha> → https://github.com/orocsy/engineering-craft
  Next scheduled run:       <date> (launchd com.engineering-craft.consolidation-reminder)
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

- **Scheduled**: launchd plist `com.engineering-craft.consolidation-reminder` fires every 2 days (`StartInterval=172800`, counted from load — not a fixed wall-clock time), runs a sweep script that COUNTS unconsolidated entries and posts a macOS notification (`23 new entries in 8 repos — run /dev-pipeline:consolidate-lessons`). The actual consolidation is interactive because classification needs LLM judgment. The plist body is installed by engineering-craft's `bootstrap/install.sh` and points at this plugin's `hooks/consolidate-lessons-notify.sh`.
- **Manual**: any time, with or without `--dry-run`.
- **End of feature**: `/dev-pipeline:learn` may suggest invoking this if it just promoted a learning that looks generalizable.

The scheduled job does NOT auto-run `claude -p` — that path is brittle for an LLM-judgment task. Notification + interactive is the deliberate design.
