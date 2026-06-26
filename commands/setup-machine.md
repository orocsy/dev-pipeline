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

**Platform**: macOS-first. The consolidation reminder uses **launchd** (`launchctl`, `~/Library/LaunchAgents`), which is macOS-only — on Linux those steps no-op/fail and the equivalent (a systemd timer or cron job) is not yet wired. Everything else (skill, plugin, hooks, settings) is cross-platform.

---

## STEP 1: Detect what's missing

Check each layer and report:

```bash
echo "=== engineering-craft skill ==="
[ -d "$HOME/.claude/skills/engineering-craft/categories" ] \
  && echo "✓ present ($(find "$HOME/.claude/skills/engineering-craft/categories" -name '*.md' -path '*/rules/*' | wc -l | tr -d ' ') rules)" \
  || echo "✗ MISSING"

echo "=== engineering-craft mirror clone (provisioned lazily, not by setup) ==="
[ -d "$HOME/.claude/external-mirrors/engineering-craft/.git" ] \
  && echo "✓ present" || echo "✗ MISSING (OK on a fresh machine — created on first /dev-pipeline:consolidate-lessons)"

echo "=== dev-pipeline plugin ==="
[ -d "$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline/.git" ] \
  && echo "✓ present" || echo "✗ MISSING"

echo "=== spec-forge ==="
[ -d "${SPEC_FORGE_DIR:-$HOME/Desktop/projects/spec-forge}/.git" ] \
  && echo "✓ present" || echo "✗ MISSING (skip if not using scaffold-from-prd)"

echo "=== Hooks ==="
[ -x "$HOME/.claude/hooks/post-codex-fix-extract-lesson.sh" ] \
  && echo "✓ post-codex-fix-extract-lesson.sh installed" || echo "✗ MISSING"
[ -f "$HOME/.claude/hooks/session-start.sh" ] && grep -q "engineering-craft skill bootstrap" "$HOME/.claude/hooks/session-start.sh" \
  && echo "✓ session-start.sh has engineering-craft fragment" || echo "✗ session-start.sh missing fragment"

echo "=== launchd consolidation reminder ==="
launchctl list 2>/dev/null | grep -q engineering-craft \
  && echo "✓ loaded" || echo "✗ NOT loaded"
```

If everything is `✓` and the user didn't ask to force-reinstall, exit "Already set up." If anything is `✗`, continue.

---

## STEP 2: Bootstrap the skill, then run the installer

`install.sh` lives *inside* the engineering-craft skill dir, so it can't clone the skill it
runs from — on a truly fresh machine STEP 1 reports the skill MISSING and a bare
`bash …/install.sh` dies with "No such file or directory" before anything installs.
Clone-or-refresh the skill FIRST, then hand off to the installer for everything else:

```bash
SKILL_DIR="$HOME/.claude/skills/engineering-craft"
REPO="${ENGINEERING_CRAFT_REPO:-https://github.com/orocsy/engineering-craft}"

if [ -d "$SKILL_DIR/categories" ]; then
  # Already present — fast-forward refresh, tolerate failure (offline is fine here).
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
