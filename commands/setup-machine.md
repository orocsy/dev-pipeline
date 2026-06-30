---
description: Bootstrap a fresh machine — install engineering-craft + dev-pipeline + spec-forge + hooks + settings + launchd. Idempotent. Use on first run on a new device.
---

# /dev-pipeline:setup-machine

Bootstrap the full Claude Code stack on a fresh machine. This wraps `~/.claude/skills/engineering-craft/bootstrap/install.sh` so you can invoke it from inside Claude Code instead of opening a terminal.

**When to use**:
- First time using Claude Code on a new device
- Suspect a hook/setting got out of sync
- After cloning a fresh checkout of engineering-craft

**Idempotent**: re-running is safe. Skips steps that are already done.

**Platform**: macOS-only for now. The consolidation reminder uses **launchd** (`launchctl`, `~/Library/LaunchAgents`). ⚠️ The wrapped `install.sh` runs under `set -e` with an *unconditional* `launchctl load`, so on Linux it completes the cross-platform steps (skill, plugin, hooks, settings) but then **exits non-zero at the launchd step** — the run looks failed even though the core stack landed. Full Linux support (guard launchd behind a `uname` check + a systemd/cron equivalent) is tracked against `install.sh` in the engineering-craft repo. Until then, treat this command as macOS-only.

---

## STEP 1: Detect what's missing

Check each layer and report. Layers are tagged **REQUIRED** (absence forces setup to run)
or **OPTIONAL** (acceptable to be absent — a lazily-provisioned mirror, a spec-forge you may
not use, launchd on non-macOS). Only a missing REQUIRED layer counts toward the gate, so
re-running on an already-set-up box — or on Linux — correctly reaches "Already set up"
instead of looping the installer:

```bash
REQUIRED_MISSING=0

echo "=== engineering-craft skill (REQUIRED) ==="
# Require the SAME completeness STEP 2 enforces (categories/ AND the installer), so a
# stripped tree with categories but no installer isn't reported "present" and skipped past
# STEP 2's repair path.
if [ -d "$HOME/.claude/skills/engineering-craft/categories" ] && [ -f "$HOME/.claude/skills/engineering-craft/bootstrap/install.sh" ]; then
  echo "✓ present ($(find "$HOME/.claude/skills/engineering-craft/categories" -name '*.md' ! -name 'README.md' ! -name 'INDEX.md' | wc -l | tr -d ' ') rules)"
else
  echo "✗ MISSING or incomplete (need categories/ AND bootstrap/install.sh)"; REQUIRED_MISSING=1
fi

echo "=== engineering-craft mirror (OPTIONAL — provisioned by install.sh in STEP 2) ==="
[ -d "$HOME/.claude/external-mirrors/engineering-craft/.git" ] \
  && echo "✓ present" \
  || echo "○ absent (will be cloned by install.sh in STEP 2)"

echo "=== dev-pipeline plugin (REQUIRED) ==="
# Gate on the plugin manifest, not .git — a copied (non-git) or symlinked plugin is still
# usable; requiring .git would mark a valid install missing forever and loop the gate.
if [ -f "$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline/.claude-plugin/plugin.json" ]; then
  echo "✓ present"
else
  echo "✗ MISSING"; REQUIRED_MISSING=1
fi

echo "=== spec-forge (OPTIONAL — only for /dev-pipeline:scaffold-from-prd) ==="
[ -d "${SPEC_FORGE_DIR:-$HOME/Desktop/projects/spec-forge}/.git" ] \
  && echo "✓ present" \
  || echo "○ absent (skip if not using scaffold-from-prd)"

echo "=== hooks (REQUIRED) ==="
if [ -x "$HOME/.claude/hooks/post-codex-fix-extract-lesson.sh" ]; then
  echo "✓ post-codex-fix-extract-lesson.sh installed"
else
  echo "✗ MISSING"; REQUIRED_MISSING=1
fi
# install.sh writes the marker "# === engineering-craft auto-bootstrap"; a hand-assembled
# hook may instead say "engineering-craft skill bootstrap". Match either so a correctly
# bootstrapped fresh machine isn't seen as missing (which would break idempotency).
if [ -f "$HOME/.claude/hooks/session-start.sh" ] && grep -qE "engineering-craft (auto-bootstrap|skill bootstrap)" "$HOME/.claude/hooks/session-start.sh"; then
  echo "✓ session-start.sh has engineering-craft fragment"
else
  echo "✗ session-start.sh missing fragment"; REQUIRED_MISSING=1
fi
# Hook FILES can exist while settings.json no longer registers them (the exact
# "hook/setting out of sync" case this command repairs) — gate on the registration,
# not just the file, so a drifted settings.json forces STEP 2 to re-merge it.
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -q "session-start.sh" "$SETTINGS" && grep -q "post-codex-fix-extract-lesson.sh" "$SETTINGS"; then
  echo "✓ hooks registered in settings.json"
else
  echo "✗ settings.json missing hook registration (files may exist but aren't wired in)"; REQUIRED_MISSING=1
fi

echo "=== launchd consolidation reminder (REQUIRED on macOS · n/a elsewhere) ==="
if [ "$(uname)" = Darwin ]; then
  # macOS: required — a set-up mac has it loaded; a fresh mac gets it in STEP 2.
  if launchctl list 2>/dev/null | grep -q engineering-craft; then
    echo "✓ loaded"
  else
    echo "✗ not loaded (will be set up in STEP 2)"; REQUIRED_MISSING=1
  fi
else
  echo "○ n/a (launchd is macOS-only)"
fi

echo ""
if [ "$REQUIRED_MISSING" -eq 0 ]; then
  echo "RESULT: all REQUIRED layers present (optional ○ items are fine to leave)."
else
  echo "RESULT: one or more REQUIRED layers missing — proceed to STEP 2."
fi
```

If `REQUIRED_MISSING` is `0` and the user didn't ask to force-reinstall, exit **"Already
set up."** Optional `○` items (mirror not yet cloned, unused spec-forge, launchd on Linux)
do NOT count toward the gate — leaving them absent is correct, which is what keeps re-runs
idempotent. Only a REQUIRED `✗` means continue to STEP 2.

---

## STEP 2: Bootstrap the skill, then run the installer

`install.sh` lives *inside* the engineering-craft skill dir, so it can't clone the skill it
runs from — on a truly fresh machine STEP 1 reports the skill MISSING and a bare
`bash …/install.sh` dies with "No such file or directory" before anything installs.
Clone-or-refresh the skill FIRST, then hand off to the installer for everything else:

```bash
SKILL_DIR="$HOME/.claude/skills/engineering-craft"
REPO="${ENGINEERING_CRAFT_REPO:-https://github.com/orocsy/engineering-craft}"

if [ -d "$SKILL_DIR/categories" ] && [ -f "$SKILL_DIR/bootstrap/install.sh" ]; then
  # Already present AND complete (categories/ + installer) — fast-forward refresh,
  # tolerate failure (offline is fine here). A tree with categories/ but no installer
  # (copied/stripped, or a local deletion) falls through to the re-clone branch so the
  # command can actually repair it, instead of refreshing then bailing at the guard.
  [ -d "$SKILL_DIR/.git" ] && git -C "$SKILL_DIR" pull --ff-only origin main 2>&1 | tail -2 || true
elif [ -d "$SKILL_DIR" ] && [ -n "$(ls -A "$SKILL_DIR" 2>/dev/null)" ]; then
  # Partial/corrupt dir (the "hook/setting out of sync" case) — a bare `git clone`
  # would abort on a non-empty target, so clone aside and swap into place. Clear any
  # leftover temp from an interrupted prior run FIRST so re-runs stay idempotent, and
  # guard the swap so a failed `rm` can't make `mv` nest the clone inside the old dir.
  rm -rf "${SKILL_DIR}.tmp"
  if git clone "$REPO" "${SKILL_DIR}.tmp"; then
    rm -rf "$SKILL_DIR" && [ ! -e "$SKILL_DIR" ] && mv "${SKILL_DIR}.tmp" "$SKILL_DIR"
  else
    rm -rf "${SKILL_DIR}.tmp"; echo "[setup] skill clone failed (offline?) — original left intact"
  fi
else
  mkdir -p "$(dirname "$SKILL_DIR")"
  git clone "$REPO" "$SKILL_DIR"
fi

# Bail unless the skill bootstrap above produced a COMPLETE tree — both the installer
# AND categories/. A partial/corrupt dir (install.sh present but no categories/) whose
# re-clone just failed would otherwise pass a bare -f check and run the installer from
# the broken tree — exactly the incomplete-tree case this command is meant to repair.
if [ ! -f "$SKILL_DIR/bootstrap/install.sh" ] || [ ! -d "$SKILL_DIR/categories" ]; then
  echo "[setup] ✗ engineering-craft bootstrap incomplete — need BOTH bootstrap/install.sh and categories/ in $SKILL_DIR"
  echo "        (skill clone/refresh failed: offline, bad ENGINEERING_CRAFT_REPO, or swap failure)."
  echo "        Fix connectivity / the repo URL and re-run — NOT invoking the installer against a broken tree."
  exit 1
fi

# All three repos (engineering-craft, dev-pipeline, spec-forge) are PUBLIC — default the
# installer to HTTPS so a brand-new device with no SSH key still works. SSH is opt-in.
DEV_PIPELINE_REPO="${DEV_PIPELINE_REPO:-https://github.com/orocsy/dev-pipeline.git}" \
SPEC_FORGE_REPO="${SPEC_FORGE_REPO:-https://github.com/orocsy/spec-forge.git}" \
  bash "$SKILL_DIR/bootstrap/install.sh"
```

Responsibilities:
- **The clone-or-refresh block above** installs/updates the engineering-craft skill — `install.sh` does NOT (it can't clone the dir it lives in).
- **`install.sh`** then handles: dev-pipeline plugin clone, spec-forge clone, hooks copy +
  session-start fragment merge, settings.json hook registration (jq-merged, doesn't
  clobber), launchd plist install + load.

Allowed env overrides (pass to user if asked):
- `ENGINEERING_CRAFT_REPO=<url>` — fork or alternate skill remote
- `SKIP_DEV_PIPELINE=1` — skip dev-pipeline clone
- `SKIP_SPEC_FORGE=1` — skip spec-forge clone
- `SPEC_FORGE_DIR=<path>` — custom spec-forge location
- `DEV_PIPELINE_REPO=<url>` — SSH (`git@…`) or fork URL (default is HTTPS, no auth needed)
- `SPEC_FORGE_REPO=<url>` — SSH (`git@…`) or fork URL (default is HTTPS, no auth needed)

---

## STEP 3: Verify install end-to-end

```bash
# Run hooks
bash "$HOME/.claude/hooks/session-start.sh" 2>&1 | head -10

# Run lint
python3 "$HOME/.claude/skills/engineering-craft/scripts/lint.py" 2>&1 | tail -8

# Confirm launchd (macOS only — no-op on Linux)
launchctl list 2>/dev/null | grep engineering-craft || echo "(launchd check skipped — not macOS, or reminder not loaded)"
```

Expected: SessionStart shows engineering-craft present; lint clean; launchd loaded.

---

## STEP 4: Surface what's available

Once setup is verified, show the user a brief summary:

```
✅ Setup complete.

What you have now:
  • engineering-craft skill: the rule set detected in STEP 1 (auto-loaded by triggers)
  • /dev-pipeline:* commands: full pipeline + utilities
  • SessionStart hook: keeps skill fresh, surfaces consolidation reminders
  • PostToolUse(Bash) hook: journals review-fix commits
  • launchd job: 2-day consolidation reminder

To start a new project:
  /dev-pipeline:init                 # detects stack, creates .claude/

To create a project CLAUDE.md from template:
  cp ~/.claude/skills/engineering-craft/bootstrap/templates/project-CLAUDE.md .claude/CLAUDE.md
  # then fill in the {{PLACEHOLDERS}}

To run consolidation manually:
  /dev-pipeline:consolidate-lessons

For full setup details:
  cat ~/.claude/skills/engineering-craft/bootstrap/HANDOFF.md
```

---

## Edge case: SSH not configured

If the bootstrap fails on `git clone git@github.com:orocsy/dev-pipeline.git` with "Permission denied (publickey)":

1. Surface the error to the user
2. Suggest running with HTTPS:
   ```bash
   DEV_PIPELINE_REPO=https://github.com/orocsy/dev-pipeline.git \
   SPEC_FORGE_REPO=https://github.com/orocsy/spec-forge.git \
   bash $HOME/.claude/skills/engineering-craft/bootstrap/install.sh
   ```
3. OR walk them through SSH key setup (`gh auth login` is the easiest path)

Don't auto-switch to HTTPS without asking — user may prefer SSH long-term.
