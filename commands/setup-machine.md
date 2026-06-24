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

---

## STEP 1: Detect what's missing

Check each layer and report:

```bash
echo "=== engineering-craft skill ==="
[ -d "$HOME/.claude/skills/engineering-craft/categories" ] \
  && echo "✓ present ($(find $HOME/.claude/skills/engineering-craft/categories -name '*.md' -path '*/rules/*' | wc -l | tr -d ' ') rules)" \
  || echo "✗ MISSING"

echo "=== engineering-craft mirror clone ==="
[ -d "$HOME/.claude/external-mirrors/engineering-craft/.git" ] \
  && echo "✓ present" || echo "✗ MISSING"

echo "=== dev-pipeline plugin ==="
[ -d "$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline/.git" ] \
  && echo "✓ present" || echo "✗ MISSING"

echo "=== spec-forge ==="
[ -d "$HOME/Desktop/projects/spec-forge/.git" ] \
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

## STEP 2: Run the bootstrap installer

```bash
bash "$HOME/.claude/skills/engineering-craft/bootstrap/install.sh"
```

The script handles:
- engineering-craft skill clone (if missing)
- dev-pipeline plugin clone (if missing)
- spec-forge clone (if missing)
- hooks copy + session-start fragment merge
- settings.json hook registration (jq-merged, doesn't clobber)
- launchd plist install + load

Allowed env overrides (pass to user if asked):
- `SKIP_DEV_PIPELINE=1` — skip dev-pipeline clone
- `SKIP_SPEC_FORGE=1` — skip spec-forge clone
- `SPEC_FORGE_DIR=<path>` — custom spec-forge location
- `DEV_PIPELINE_REPO=<url>` — fork or HTTPS URL
- `SPEC_FORGE_REPO=<url>` — fork or HTTPS URL

---

## STEP 3: Verify install end-to-end

```bash
# Run hooks
bash "$HOME/.claude/hooks/session-start.sh" 2>&1 | head -10

# Run lint
python3 "$HOME/.claude/skills/engineering-craft/scripts/lint.py" 2>&1 | tail -8

# Confirm launchd
launchctl list | grep engineering-craft
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
