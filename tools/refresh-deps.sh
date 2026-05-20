#!/usr/bin/env bash
# dev-pipeline — verify presence + freshness of every external dependency.
#
# Reads deps.json (plugin root), surveys ~/.claude/plugins/marketplaces/*,
# pulls stale ones (ff-only), cross-checks hybrid skills, writes a status
# report to .claude/dev-pipeline-deps-status.json in the cwd.
#
# Usage:
#   bash <plugin>/tools/refresh-deps.sh                 # write status into ./.claude/
#   bash <plugin>/tools/refresh-deps.sh --pull          # also git pull stale marketplaces
#   bash <plugin>/tools/refresh-deps.sh --json-only     # suppress human output, only write JSON
#
# Exit codes:
#   0  everything current OR only optional/non-blocking gaps
#   1  REQUIRED external missing (e.g. code-review)
#   2  hybrid drift detected (warn-but-continue)
#   3  config error (deps.json missing, jq missing, etc.)

set -e

DO_PULL=0
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --pull) DO_PULL=1 ;;
    --json-only) QUIET=1 ;;
    -h|--help) sed -n '1,/^set -e/p' "$0" | head -20; exit 0 ;;
  esac
done

log() { [[ "$QUIET" -eq 1 ]] || echo "$@"; }

PLUGIN_ROOT="${PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/local/plugins/dev-pipeline}"
DEPS_JSON="$PLUGIN_ROOT/deps.json"
MARKETPLACES_DIR="$HOME/.claude/plugins/marketplaces"
STATUS_DIR=".claude"
STATUS_OUT="$STATUS_DIR/dev-pipeline-deps-status.json"

# ── Preflight ────────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  log "❌ jq is required. Install: brew install jq"
  exit 3
fi
if [[ ! -f "$DEPS_JSON" ]]; then
  log "❌ deps.json missing at $DEPS_JSON"
  log "   Is the dev-pipeline plugin installed?"
  exit 3
fi
mkdir -p "$STATUS_DIR"

# ── Build the installed-inventory across every marketplace ────────────────────
# Output: lines of `<plugin-name>\t<marketplace>\t<marketplace-path>`
inventory_plugins() {
  local mp_root mp_name mp_json
  for mp_root in "$MARKETPLACES_DIR"/*/; do
    [[ -d "$mp_root" ]] || continue
    mp_name="$(basename "$mp_root")"
    mp_json="$mp_root/.claude-plugin/marketplace.json"
    [[ -f "$mp_json" ]] || continue
    jq -r --arg mp "$mp_name" --arg path "$mp_root" \
      '.plugins[]? | "\(.name)\t\($mp)\t\($path)"' "$mp_json" 2>/dev/null || true
  done
}

# Output: lines of `<skill-name>\t<owning-plugin>\t<plugin-path>`
inventory_skills() {
  local plugin_root skill_dir skill_name
  # Use the marketplace plugin inventory to know which plugin dirs to scan.
  while IFS=$'\t' read -r plugin_name mp_name mp_path; do
    plugin_root="$mp_path/plugins/$plugin_name"
    # Plugin source may be a remote URL (not on disk) — skip silently.
    [[ -d "$plugin_root" ]] || continue
    if [[ -d "$plugin_root/skills" ]]; then
      for skill_dir in "$plugin_root"/skills/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_name="$(basename "$skill_dir")"
        printf '%s\t%s\t%s\n' "$skill_name" "$plugin_name" "$plugin_root"
      done
    fi
    # Top-level SKILL.md = the plugin itself ships as a single skill.
    if [[ -f "$plugin_root/SKILL.md" ]]; then
      printf '%s\t%s\t%s\n' "$plugin_name" "$plugin_name" "$plugin_root"
    fi
  done < <(inventory_plugins)
}

INSTALLED_PLUGINS="$(inventory_plugins)"
INSTALLED_SKILLS="$(inventory_skills)"

# ── Marketplace freshness ────────────────────────────────────────────────────
# For each marketplace that is a git checkout, fetch and report behind count.
declare -a PULLED=()
declare -a NEEDS_MANUAL=()
declare -a CURRENT_MPS=()

for mp_root in "$MARKETPLACES_DIR"/*/; do
  [[ -d "$mp_root/.git" ]] || continue
  mp_name="$(basename "$mp_root")"
  if ! git -C "$mp_root" fetch --quiet origin 2>/dev/null; then
    NEEDS_MANUAL+=("$mp_name (fetch failed — check connectivity / auth)")
    continue
  fi
  default_branch="$(git -C "$mp_root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  default_branch="${default_branch:-main}"
  behind="$(git -C "$mp_root" rev-list --count "HEAD..origin/$default_branch" 2>/dev/null || echo 0)"

  if [[ "$behind" -gt 0 ]]; then
    if [[ "$DO_PULL" -eq 1 ]]; then
      if git -C "$mp_root" merge --ff-only "origin/$default_branch" >/dev/null 2>&1; then
        PULLED+=("$mp_name (was $behind behind)")
      else
        NEEDS_MANUAL+=("$mp_name ($behind behind — ff-only failed; resolve manually)")
      fi
    else
      NEEDS_MANUAL+=("$mp_name ($behind behind — re-run with --pull)")
    fi
  else
    CURRENT_MPS+=("$mp_name")
  fi
done

# ── Cross-check deps.json against the inventory ──────────────────────────────
declare -a EXT_CURRENT=()
declare -a EXT_MISSING_REQUIRED=()
declare -a EXT_MISSING_OPTIONAL=()
declare -a HYBRID_DRIFT=()

# External plugins
while IFS=$'\t' read -r name required usedBy; do
  if echo "$INSTALLED_PLUGINS" | awk -F'\t' -v n="$name" '$1==n {found=1} END {exit !found}'; then
    EXT_CURRENT+=("plugin:$name")
  else
    if [[ "$required" == "true" ]]; then
      EXT_MISSING_REQUIRED+=("plugin:$name (used by: $usedBy)")
    else
      EXT_MISSING_OPTIONAL+=("plugin:$name (used by: $usedBy)")
    fi
  fi
done < <(jq -r '.external.plugins[]? | "\(.name)\t\(.required)\t\(.usedBy | join(","))"' "$DEPS_JSON")

# External skills
while IFS=$'\t' read -r name required usedBy; do
  if echo "$INSTALLED_SKILLS" | awk -F'\t' -v n="$name" '$1==n {found=1} END {exit !found}'; then
    EXT_CURRENT+=("skill:$name")
  else
    if [[ "$required" == "true" ]]; then
      EXT_MISSING_REQUIRED+=("skill:$name (used by: $usedBy)")
    else
      EXT_MISSING_OPTIONAL+=("skill:$name (used by: $usedBy)")
    fi
  fi
done < <(jq -r '.external.skills[]? | "\(.name)\t\(.required)\t\(.usedBy | join(","))"' "$DEPS_JSON")

# Hybrid-skill drift check: for each hybrid entry, confirm the composesWith
# externals are installed; if not, that's a drift signal because the owned
# skill assumes they exist.
while IFS=$'\t' read -r owned composesList note; do
  IFS=',' read -ra composes <<< "$composesList"
  for ext in "${composes[@]}"; do
    # Wildcard match (e.g. `nodejs-*`)
    if [[ "$ext" == *'*'* ]]; then
      prefix="${ext%\*}"
      if ! echo "$INSTALLED_SKILLS" | awk -F'\t' -v p="$prefix" '$1 ~ "^"p {found=1} END {exit !found}'; then
        HYBRID_DRIFT+=("$owned → no skill matches pattern '$ext' (note: $note)")
      fi
    else
      if ! echo "$INSTALLED_SKILLS" | awk -F'\t' -v n="$ext" '$1==n {found=1} END {exit !found}'; then
        HYBRID_DRIFT+=("$owned → composer expects '$ext' but it's missing (note: $note)")
      fi
    fi
  done
done < <(jq -r '.hybridSkills[]? | "\(.owned)\t\(.composesWith | join(","))\t\(.compatNote)"' "$DEPS_JSON")

# ── Emit JSON status ─────────────────────────────────────────────────────────
to_jsonarr() {
  if [[ "$#" -eq 0 ]]; then echo "[]"; return; fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg head "$(git -C "$PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
  --argjson current "$(to_jsonarr "${EXT_CURRENT[@]:-}")" \
  --argjson missingRequired "$(to_jsonarr "${EXT_MISSING_REQUIRED[@]:-}")" \
  --argjson missingOptional "$(to_jsonarr "${EXT_MISSING_OPTIONAL[@]:-}")" \
  --argjson hybridDrift "$(to_jsonarr "${HYBRID_DRIFT[@]:-}")" \
  --argjson pulled "$(to_jsonarr "${PULLED[@]:-}")" \
  --argjson currentMps "$(to_jsonarr "${CURRENT_MPS[@]:-}")" \
  --argjson needsManual "$(to_jsonarr "${NEEDS_MANUAL[@]:-}")" \
  '{
    checkedAt: $ts,
    devPipelineHead: $head,
    marketplaces: { current: $currentMps, pulled: $pulled, needsManual: $needsManual },
    external: { current: $current, missingRequired: $missingRequired, missingOptional: $missingOptional },
    hybridDrift: $hybridDrift
  }' > "$STATUS_OUT"

# ── Human summary ────────────────────────────────────────────────────────────
log ""
log "── dev-pipeline refresh-deps ──"
log "  Marketplaces current: ${#CURRENT_MPS[@]}"
log "  Marketplaces pulled:  ${#PULLED[@]}"
log "  Needs manual review:  ${#NEEDS_MANUAL[@]}"
[[ "${#NEEDS_MANUAL[@]}" -gt 0 ]] && for n in "${NEEDS_MANUAL[@]}"; do log "    • $n"; done
log "  Externals current:    ${#EXT_CURRENT[@]}"
log "  Required missing:     ${#EXT_MISSING_REQUIRED[@]}"
[[ "${#EXT_MISSING_REQUIRED[@]}" -gt 0 ]] && for n in "${EXT_MISSING_REQUIRED[@]}"; do log "    ❌ $n"; done
log "  Optional missing:     ${#EXT_MISSING_OPTIONAL[@]}"
[[ "${#EXT_MISSING_OPTIONAL[@]}" -gt 0 ]] && for n in "${EXT_MISSING_OPTIONAL[@]:0:5}"; do log "    ⚠️  $n"; done
[[ "${#EXT_MISSING_OPTIONAL[@]}" -gt 5 ]] && log "    … (+$((${#EXT_MISSING_OPTIONAL[@]} - 5)) more — see $STATUS_OUT)"
log "  Hybrid drift entries: ${#HYBRID_DRIFT[@]}"
[[ "${#HYBRID_DRIFT[@]}" -gt 0 ]] && for n in "${HYBRID_DRIFT[@]:0:5}"; do log "    ⚠️  $n"; done
log ""
log "  Report: $STATUS_OUT"

# ── Exit code ────────────────────────────────────────────────────────────────
if [[ "${#EXT_MISSING_REQUIRED[@]}" -gt 0 ]]; then
  exit 1
elif [[ "${#HYBRID_DRIFT[@]}" -gt 0 ]]; then
  exit 2
else
  exit 0
fi
