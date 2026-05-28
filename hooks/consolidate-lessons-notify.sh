#!/usr/bin/env bash
# dev-pipeline — sweep journals and notify when entries pile up.
#
# Invoked by launchd plist com.engineering-craft.consolidation-reminder every 2 days.
# This script does NOT consolidate — it counts unconsolidated entries and
# posts a macOS notification telling the user to run the interactive
# consolidation command. Consolidation requires LLM judgment, so it stays
# manual on purpose.
#
# Safe to run standalone (e.g. for testing): bash <plugin>/hooks/consolidate-lessons-notify.sh

set +e

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"
TOTAL=0
REPO_COUNT=0

for journal in "$PROJECTS_DIR"/*/.learnings/JOURNAL.md; do
  [[ -f "$journal" ]] || continue

  # Count entries: lines starting with "## [JNL-" minus lines with a real
  # consolidated marker. The marker pattern requires a 4-digit year so the
  # header documentation line ("<!-- consolidated: ... -->") doesn't match.
  TOTAL_IN_FILE="$(grep -c '^## \[JNL-' "$journal" 2>/dev/null || echo 0)"
  CONSOLIDATED_IN_FILE="$(grep -cE '<!-- consolidated: [0-9]{4}' "$journal" 2>/dev/null || echo 0)"
  UNCONSOLIDATED=$((TOTAL_IN_FILE - CONSOLIDATED_IN_FILE))

  if [[ $UNCONSOLIDATED -gt 0 ]]; then
    TOTAL=$((TOTAL + UNCONSOLIDATED))
    REPO_COUNT=$((REPO_COUNT + 1))
  fi
done

if [[ $TOTAL -eq 0 ]]; then
  # Nothing pending — exit quietly. No notification noise.
  exit 0
fi

TITLE="Engineering Craft — consolidation pending"
MESSAGE="${TOTAL} new journal entries across ${REPO_COUNT} repos. Run /dev-pipeline:consolidate-lessons in Claude."

# macOS notification via osascript (works without extra deps).
osascript -e "display notification \"${MESSAGE}\" with title \"${TITLE}\"" 2>/dev/null || true

# Also log to stderr so launchd captures it in the system log if anyone looks.
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${TITLE}: ${MESSAGE}" >&2

exit 0
