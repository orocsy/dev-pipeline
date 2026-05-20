#!/usr/bin/env bash
# dev-pipeline — skill-doctor
#
# Diagnoses missing/drifted external skills and proposes fixes. Runs AFTER
# refresh-deps. Reads deps.json + .claude/dev-pipeline-deps-status.json, then
# resolves each missing name via:
#   1. Exact-name match in installed marketplaces.
#   2. Plugin-as-skill match (top-level SKILL.md).
#   3. Description fuzzy match (token overlap with usedBy context).
#   4. Marketplace catalog match (incl. URL-only entries not yet downloaded).
#   5. Falls through to "search-required" — emit web-search prompts.
#
# Modes:
#   --report   (default) emit .claude/dev-pipeline-skill-doctor-plan.md
#   --apply    same + apply non-destructive auto-resolves (deps.json + skill source edits)
#   --search   same + mark search-required items with explicit prompts the LLM can run
#
# Exit codes:
#   0  no issues OR all issues are search-required (LLM follow-up)
#   1  config error (deps.json missing, jq missing, etc.)
#   2  auto-resolvable items pending (action available — re-run with --apply)

set -e

MODE="report"
for arg in "$@"; do
  case "$arg" in
    --report)  MODE="report" ;;
    --apply)   MODE="apply" ;;
    --search)  MODE="search" ;;
    -h|--help) sed -n '1,/^set -e/p' "$0" | head -20; exit 0 ;;
  esac
done

PLUGIN_ROOT="${PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline}"
DEPS_JSON="$PLUGIN_ROOT/deps.json"
MARKETPLACES_DIR="$HOME/.claude/plugins/marketplaces"
STATUS_FILE=".claude/dev-pipeline-deps-status.json"
PLAN_OUT=".claude/dev-pipeline-skill-doctor-plan.md"

# ── Preflight ────────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required. Install: brew install jq"
  exit 1
fi
if [[ ! -f "$DEPS_JSON" ]]; then
  echo "❌ deps.json missing at $DEPS_JSON"
  exit 1
fi
if [[ ! -f "$STATUS_FILE" ]]; then
  echo "ℹ️  No refresh-deps status found at $STATUS_FILE — running refresh-deps first…"
  bash "$PLUGIN_ROOT/tools/refresh-deps.sh" --json-only || true
fi
mkdir -p .claude

# ── Build installed-name index ───────────────────────────────────────────────
# Two flat files: one for skill names + description, one for marketplace catalog.
SKILL_INDEX="$(mktemp)"
CATALOG_INDEX="$(mktemp)"
trap 'rm -f "$SKILL_INDEX" "$CATALOG_INDEX"' EXIT

# Skill index: lines of `<name>\t<plugin>\t<marketplace>\t<description-firstline>`
for mp_root in "$MARKETPLACES_DIR"/*/; do
  [[ -d "$mp_root" ]] || continue
  mp_name="$(basename "$mp_root")"
  for plugin_root in "$mp_root/plugins"/*/; do
    [[ -d "$plugin_root" ]] || continue
    plugin_name="$(basename "$plugin_root")"
    # Per-skill SKILL.md
    for skill_dir in "$plugin_root/skills"/*/; do
      [[ -d "$skill_dir" ]] || continue
      skill_name="$(basename "$skill_dir")"
      skill_md="$skill_dir/SKILL.md"
      desc=""
      if [[ -f "$skill_md" ]]; then
        desc="$(awk '/^description:/{$1=""; print; exit}' "$skill_md" | tr -d '\n' | sed 's/^ *//;s/ *$//' | cut -c1-180)"
      fi
      printf '%s\t%s\t%s\t%s\n' "$skill_name" "$plugin_name" "$mp_name" "$desc" >> "$SKILL_INDEX"
    done
    # Plugin-level SKILL.md (single-skill plugin)
    if [[ -f "$plugin_root/SKILL.md" ]]; then
      desc="$(awk '/^description:/{$1=""; print; exit}' "$plugin_root/SKILL.md" | tr -d '\n' | sed 's/^ *//;s/ *$//' | cut -c1-180)"
      printf '%s\t%s\t%s\t%s\n' "$plugin_name" "$plugin_name" "$mp_name" "$desc" >> "$SKILL_INDEX"
    fi
  done
done

# Catalog index: every plugin listed in any marketplace.json, downloaded or not.
# Lines of `<plugin>\t<marketplace>\t<source-url-or-./path>\t<description-firstline>`
for mp_root in "$MARKETPLACES_DIR"/*/; do
  mp_json="$mp_root/.claude-plugin/marketplace.json"
  [[ -f "$mp_json" ]] || continue
  mp_name="$(basename "$mp_root")"
  jq -r --arg mp "$mp_name" '
    .plugins[]? |
    [
      .name,
      $mp,
      (if .source then (if (.source | type) == "string" then .source else (.source.url // .source.path // "") end) else "" end),
      (.description // "" | .[0:180])
    ] | @tsv
  ' "$mp_json" >> "$CATALOG_INDEX"
done

# ── Resolution helpers ───────────────────────────────────────────────────────
exact_match() {
  local name="$1"
  awk -F'\t' -v n="$name" '$1==n {print $0; exit}' "$SKILL_INDEX"
}

catalog_match() {
  local name="$1"
  awk -F'\t' -v n="$name" '$1==n {print $0; exit}' "$CATALOG_INDEX"
}

# Description fuzzy match: token overlap with the target name's stem.
# Returns the best matching installed skill if score >= threshold, else empty.
fuzzy_match() {
  local target="$1"
  local trigger="$2"   # extra context (e.g. usedBy)
  # Build tokens from the target name (split on `-`) + trigger.
  local tokens
  tokens="$(echo "$target $trigger" | tr -cs 'A-Za-z0-9' ' ' | tr 'A-Z' 'a-z')"
  # For each indexed skill, count how many of those tokens appear in its description.
  awk -F'\t' -v toks="$tokens" -v THRESHOLD=2 '
    BEGIN {
      n = split(toks, T, /[ \t]+/)
      for (i = 1; i <= n; i++) if (length(T[i]) >= 3) want[T[i]] = 1
    }
    {
      desc = tolower($4)
      hits = 0
      for (t in want) if (index(desc, t)) hits++
      if (hits >= THRESHOLD && hits > best_hits) { best_hits = hits; best = $0 }
    }
    END { if (best_hits >= THRESHOLD) print best }
  ' "$SKILL_INDEX"
}

# Look up an entry by name in deps.json → external.skills[]
deps_lookup_skill() {
  local name="$1"
  jq --arg n "$name" '.external.skills[]? | select(.name == $n)' "$DEPS_JSON"
}

# Check if any deps.json skill entry lists `name` under supersedes[].
superseded_by() {
  local name="$1"
  jq -r --arg n "$name" '.external.skills[]? | select(.supersedes // [] | index($n)) | .name' "$DEPS_JSON" | head -1
}

# ── Gather missing/drift names ───────────────────────────────────────────────
MISSING_NAMES=()
if [[ -f "$STATUS_FILE" ]]; then
  while IFS= read -r line; do
    # status file emits "skill:<name> (used by: …)" — strip prefix + suffix.
    n="$(echo "$line" | sed -E 's/^skill://; s/ \(used by:.*$//')"
    [[ -n "$n" ]] && MISSING_NAMES+=("$n")
  done < <(jq -r '.external.missingOptional[]? | select(startswith("skill:"))' "$STATUS_FILE")
fi

# Build a fresh set of names declared in deps.json so we also catch
# `status: search-required` entries even if refresh-deps already classified them.
while IFS= read -r n; do
  [[ -n "$n" ]] && MISSING_NAMES+=("$n")
done < <(jq -r '.external.skills[]? | select(.status == "search-required") | .name' "$DEPS_JSON")
# Dedup (bash 3.2 compatible — no mapfile).
_DEDUPED=()
while IFS= read -r n; do
  [[ -n "$n" ]] && _DEDUPED+=("$n")
done < <(printf '%s\n' "${MISSING_NAMES[@]}" | awk '!seen[$0]++')
MISSING_NAMES=("${_DEDUPED[@]}")
unset _DEDUPED

# ── Classify each name ───────────────────────────────────────────────────────
declare -a AUTO_RESOLVABLE=()    # already-renamed (supersedes), or exact-match-but-not-in-deps
declare -a MARKETPLACE_RESOLVE=() # in a marketplace catalog (downloaded or URL-only)
declare -a SEARCH_REQUIRED=()    # no local trace

for name in "${MISSING_NAMES[@]}"; do
  [[ -z "$name" ]] && continue

  # 1. Has deps.json already declared this name as superseded by something?
  superseder="$(superseded_by "$name")"
  if [[ -n "$superseder" ]]; then
    AUTO_RESOLVABLE+=("$name|SUPERSEDED_BY|$superseder|deps.json already lists $superseder as the replacement; drop the old name")
    continue
  fi

  # 2. Exact-name match in installed skills?
  hit="$(exact_match "$name")"
  if [[ -n "$hit" ]]; then
    IFS=$'\t' read -r sk pl mp desc <<< "$hit"
    AUTO_RESOLVABLE+=("$name|INSTALLED|$pl/$mp|skill is on disk; refresh-deps misclassified — file a bug")
    continue
  fi

  # 3. In a catalog (downloaded or URL-only)?
  hit="$(catalog_match "$name")"
  if [[ -n "$hit" ]]; then
    IFS=$'\t' read -r pl mp source desc <<< "$hit"
    MARKETPLACE_RESOLVE+=("$name|CATALOG|$mp|/plugin install $mp/$pl|$source")
    continue
  fi

  # 4. Fuzzy match against installed skill descriptions?
  trigger="$(jq -r --arg n "$name" '.external.skills[]? | select(.name == $n) | .trigger // ""' "$DEPS_JSON")"
  hit="$(fuzzy_match "$name" "$trigger")"
  if [[ -n "$hit" ]]; then
    IFS=$'\t' read -r sk pl mp desc <<< "$hit"
    AUTO_RESOLVABLE+=("$name|FUZZY|$sk|matched against $pl/$mp via description overlap — propose rename")
    continue
  fi

  # 5. Search-required.
  family="$(jq -r --arg n "$name" '.external.skills[]? | select(.name == $n) | .family // ""' "$DEPS_JSON")"
  usedBy="$(jq -r --arg n "$name" '.external.skills[]? | select(.name == $n) | (.usedBy // []) | join(", ")' "$DEPS_JSON")"
  SEARCH_REQUIRED+=("$name|family=$family|used-by=$usedBy")
done

# ── Emit the plan ────────────────────────────────────────────────────────────
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "# Skill Doctor — Action Plan"
  echo ""
  echo "_checkedAt: ${TS}_"
  echo "_mode: ${MODE}_"
  echo ""
  echo "## Auto-resolvable"
  echo ""
  if [[ "${#AUTO_RESOLVABLE[@]}" -eq 0 ]]; then
    echo "_None._"
  else
    for entry in "${AUTO_RESOLVABLE[@]}"; do
      IFS='|' read -r name kind target rest <<< "$entry"
      echo "- **\`$name\`** → $kind"
      echo "  - target: \`$target\`"
      echo "  - reason: $rest"
    done
  fi
  echo ""
  echo "## Marketplace-resolvable"
  echo ""
  if [[ "${#MARKETPLACE_RESOLVE[@]}" -eq 0 ]]; then
    echo "_None._"
  else
    for entry in "${MARKETPLACE_RESOLVE[@]}"; do
      IFS='|' read -r name kind mp install source <<< "$entry"
      echo "- **\`$name\`** → present in marketplace \`$mp\`"
      echo "  - install: \`$install\`"
      echo "  - source:  $source"
    done
  fi
  echo ""
  echo "## Search-required (LLM web search needed)"
  echo ""
  if [[ "${#SEARCH_REQUIRED[@]}" -eq 0 ]]; then
    echo "_None._"
  else
    for entry in "${SEARCH_REQUIRED[@]}"; do
      IFS='|' read -r name fam usedBy <<< "$entry"
      stem="$(echo "$name" | sed -E 's/-(best-practices|patterns|engineer|architecture|production|testing|orm|redis|security|error-handling|docker)$//')"
      echo "- **\`$name\`** ($fam, $usedBy)"
      echo "  - search prompt: \`Claude Code skill $name\` OR \`Claude plugin marketplace $stem\`"
      echo "  - action: if found upstream, add the marketplace to \`deps.json → marketplaces[]\`,"
      echo "    set \`marketplaceHint\` on the skill entry, drop \`status: search-required\`."
      echo "  - if upstream is gone: either author an owned skill that covers the gap,"
      echo "    or remove the reference from \`skill-router\` / \`project-detector\`."
    done
  fi
  echo ""
  echo "## How to apply"
  echo ""
  echo "\`bash $PLUGIN_ROOT/tools/skill-doctor.sh --apply\` — applies non-destructive auto-resolves."
  echo "\`bash $PLUGIN_ROOT/tools/skill-doctor.sh --search\` — same report + explicit LLM search prompts."
  echo ""
  echo "Marketplace-resolvable entries require interactive Claude Code commands; this script does not run them."
} > "$PLAN_OUT"

# ── Apply auto-resolvable changes if --apply ─────────────────────────────────
APPLIED=0
if [[ "$MODE" == "apply" && "${#AUTO_RESOLVABLE[@]}" -gt 0 ]]; then
  for entry in "${AUTO_RESOLVABLE[@]}"; do
    IFS='|' read -r name kind target rest <<< "$entry"
    case "$kind" in
      SUPERSEDED_BY)
        # Remove the old name from deps.json → external.skills[] (it's now
        # implicit under the superseding entry's supersedes[]). Also remove
        # from any hybridSkills.composesWith[] arrays so refresh-deps stops
        # flagging it as drift.
        tmp="$(mktemp)"
        jq --arg old "$name" '
          .external.skills = (.external.skills | map(select(.name != $old))) |
          .hybridSkills = (.hybridSkills | map(.composesWith = (.composesWith | map(select(. != $old)))))
        ' "$DEPS_JSON" > "$tmp" && mv "$tmp" "$DEPS_JSON"
        APPLIED=$((APPLIED + 1))
        ;;
      INSTALLED|FUZZY)
        # Leave a manual-edit suggestion; the rename of a string across
        # skill-router / project-detector SKILL.md needs human verification
        # (the surrounding sentences may need rewording).
        echo "ℹ️  $name → propose rename to '$target' — review skills/skill-router/SKILL.md and skills/project-detector/SKILL.md manually."
        ;;
    esac
  done
  echo "✓ Applied $APPLIED auto-resolvable patches to deps.json"
fi

# ── Human summary ────────────────────────────────────────────────────────────
echo ""
echo "── dev-pipeline skill-doctor ──"
echo "  Mode:                  $MODE"
echo "  Auto-resolvable:       ${#AUTO_RESOLVABLE[@]}"
echo "  Marketplace-resolvable:${#MARKETPLACE_RESOLVE[@]}"
echo "  Search-required:       ${#SEARCH_REQUIRED[@]}"
echo "  Plan written:          $PLAN_OUT"

# ── Exit code ────────────────────────────────────────────────────────────────
if [[ "${#AUTO_RESOLVABLE[@]}" -gt 0 && "$MODE" != "apply" ]]; then
  exit 2
fi
exit 0
