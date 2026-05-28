#!/usr/bin/env bash
# dev-pipeline — capture the URL topology of every deployable app in the repo.
#
# Reads each app's vercel.json + next.config.js (or framework equivalent) +
# any env-var references that hint at production hostnames, then optionally
# curls each candidate production URL to record the actual redirect chain.
# Writes .claude/docs/URL_TOPOLOGY.md.
#
# Why this exists: the previous /dev-pipeline:init only said "Production
# URLs: <one hostname from a commit message>". Multi-app projects (booking +
# admin + api on different hostnames) need the full mapping or every agent
# starts with wrong URL assumptions.
#
# Usage:
#   bash <plugin>/tools/url-topology.sh                # scan only, no network
#   bash <plugin>/tools/url-topology.sh --probe        # also curl each URL
#   bash <plugin>/tools/url-topology.sh --probe --out=docs/URL_TOPOLOGY.md
#
# Exit codes:
#   0  topology captured (with or without probe)
#   1  no deployable apps detected (run from project root?)
#   2  probe enabled but all URLs unreachable (often: VPN / DNS / no network)
#   3  config error

set -e

DO_PROBE=0
OUT=".claude/docs/URL_TOPOLOGY.md"
for arg in "$@"; do
  case "$arg" in
    --probe) DO_PROBE=1 ;;
    --out=*) OUT="${arg#--out=}" ;;
    -h|--help) sed -n '1,/^set -e/p' "$0" | head -25; exit 0 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq required. brew install jq"
  exit 3
fi

mkdir -p "$(dirname "$OUT")"

# ── Discover deployable apps ─────────────────────────────────────────────────
# Strategy: look for apps/*/vercel.json, apps/*/next.config.{js,mjs,ts},
# apps/*/Dockerfile. Each match = a candidate deployable app.
APPS=()
if [[ -d apps ]]; then
  for app in apps/*/; do
    [[ -d "$app" ]] || continue
    name="$(basename "$app")"
    if [[ -f "$app/vercel.json" ]] || [[ -f "$app/next.config.js" ]] || \
       [[ -f "$app/next.config.mjs" ]] || [[ -f "$app/Dockerfile" ]] || \
       [[ -f "$app/package.json" ]]; then
      APPS+=("$name")
    fi
  done
fi

if [[ "${#APPS[@]}" -eq 0 ]]; then
  echo "ℹ️  No apps detected under apps/ — single-app repo?"
  # Treat the repo root as the only app.
  APPS=(".")
fi

# ── Per-app extraction ──────────────────────────────────────────────────────
# Collects: name, basePath (Next.js), vercel-build-env hints,
# referenced env-var names (NEXT_PUBLIC_*_URL, *_APP_URL, etc.).
declare -a APP_RECORDS=()  # pipe-separated (NOT tab — bash `read -r` with
                            # IFS=$'\t' COLLAPSES consecutive tabs because tab
                            # is a whitespace char in IFS. With empty basepath
                            # and empty vercel_hints, that shifted columns
                            # over by one. `|` is non-whitespace → empty
                            # fields preserved correctly.

extract_basepath() {
  local config="$1"
  [[ -f "$config" ]] || { echo ""; return; }
  # Match: basePath: '/admin' or basePath: process.env.X || '/admin'
  grep -oE "basePath:[^,}]+" "$config" 2>/dev/null | head -1 | \
    sed -E "s/.*['\"](\/[^'\"]+)['\"].*/\1/" | head -1
}

extract_vercel_env_hints() {
  local vjson="$1"
  [[ -f "$vjson" ]] || { echo ""; return; }
  jq -r '.build.env // {} | to_entries[] | "\(.key)=\(.value)"' "$vjson" 2>/dev/null | \
    grep -iE "(URL|HOST|DOMAIN)" | tr '\n' ' '
}

extract_referenced_url_env() {
  local app_dir="$1"
  [[ -d "$app_dir" ]] || { echo ""; return; }
  # Find process.env.X references where X ends in _URL / _DOMAIN / _HOST.
  grep -rhoE "process\.env\.[A-Z_]+(_URL|_DOMAIN|_HOST|_BASE_PATH)" \
    "$app_dir/src" 2>/dev/null | \
    sed 's/process\.env\.//' | sort -u | tr '\n' ' '
}

for name in "${APPS[@]}"; do
  app_dir="apps/$name"
  [[ "$name" == "." ]] && app_dir="."

  basepath="$(extract_basepath "$app_dir/next.config.js")"
  [[ -z "$basepath" ]] && basepath="$(extract_basepath "$app_dir/next.config.mjs")"

  vercel_hints="$(extract_vercel_env_hints "$app_dir/vercel.json")"
  url_env_refs="$(extract_referenced_url_env "$app_dir")"

  APP_RECORDS+=("$name|$basepath|$vercel_hints|$url_env_refs")
done

# ── Derive candidate production URLs ─────────────────────────────────────────
# Heuristic: scan all *.json / *.md / *.env.example files in the repo for
# hostnames matching common patterns. Also pull from CORS allowlist env vars.
CANDIDATE_URLS=()
# Derive a base-hostname pattern from whatever shows up in vercel.json so the
# scan adapts to any project. Falls back to a permissive
# pattern if vercel.json doesn't reveal one.
HOST_HINT="$(grep -hoE "https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" \
  apps/*/vercel.json 2>/dev/null | sed -E 's|https?://([^/]+)|\1|' | \
  awk -F. '{ if (NF>=2) print $(NF-1)"."$NF }' | sort -u | head -1 || true)"
[[ -z "$HOST_HINT" ]] && HOST_HINT="(prod|staging|com|net|io|app)"

# Collect into a temp file (safer than process-substitution + `set -e` +
# possibly-empty grep returns, which previously made the whole pipeline
# return non-zero and aborted via set -e).
URL_TMP="$(mktemp)"
trap 'rm -f "$URL_TMP"' EXIT

URL_RE='https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/[a-zA-Z0-9/_-]*)?'

# JSON / env configs — strongest signal.
grep -rhoE "$URL_RE" \
  apps/*/vercel.json apps/*/.env.example .env.example 2>/dev/null >> "$URL_TMP" || true
# Markdown docs.
grep -rhoE "$URL_RE" docs/*.md README.md 2>/dev/null >> "$URL_TMP" || true
# Source files — restricted to CORS allowlists, env schemas, and main
# bootstrap to avoid noise from arbitrary doc-comment URLs. Captures
# subdomain-form URLs (e.g. admin.foo.com) that aren't in vercel.json.
while IFS= read -r f; do
  grep -hoE "$URL_RE" "$f" 2>/dev/null >> "$URL_TMP" || true
done < <(find apps -type f \( \
    -name 'cors*.ts' -o -name 'cors*.spec.ts' \
    -o -name 'env*.ts' -o -name 'env*.spec.ts' \
    -o -name 'main.ts' -o -name 'main.spec.ts' \
  \) 2>/dev/null)

# Filter + dedupe.
while IFS= read -r url; do
  [[ -n "$url" ]] && CANDIDATE_URLS+=("$url")
done < <(
  grep -iE "${HOST_HINT}" "$URL_TMP" 2>/dev/null | \
    grep -vE "(localhost|example\.com|vercel\.app$|127\.0\.0\.1)" 2>/dev/null | \
    sort -u || true
)

# ── Optional probe (curl each URL, record redirect chain) ────────────────────
declare -a PROBE_RESULTS=()
if [[ "$DO_PROBE" -eq 1 ]]; then
  for url in "${CANDIDATE_URLS[@]}"; do
    # Single hop check (no -L) — record what THIS URL returns first.
    # Using ~ as the curl -w separator (not | because redirect URLs can
    # contain |) and as the array record separator.
    status="$(curl -sI -o /dev/null -w '%{http_code}~%{redirect_url}' "$url" 2>/dev/null || echo '000~')"
    code="${status%~*}"
    redir="${status#*~}"
    PROBE_RESULTS+=("$url~$code~$redir")
  done
fi

# ── Emit markdown ────────────────────────────────────────────────────────────
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "# URL Topology"
  echo ""
  echo "_Auto-generated by \`/dev-pipeline:url-topology\` at ${TS}_"
  echo "_Re-run whenever \`next.config.js\`, \`vercel.json\`, or CORS allow-lists change._"
  echo ""
  echo "## Apps detected"
  echo ""
  echo "| App | Next.js basePath | Vercel env hints | URL env vars referenced in src/ |"
  echo "|---|---|---|---|"
  for rec in "${APP_RECORDS[@]}"; do
    IFS='|' read -r name basepath hints url_refs <<< "$rec"
    [[ -z "$basepath" ]] && basepath="_(none)_"
    [[ -z "$hints" ]] && hints="_(no vercel.json build.env)_"
    [[ -z "$url_refs" ]] && url_refs="_(none)_"
    echo "| \`$name\` | $basepath | $hints | $url_refs |"
  done
  echo ""

  echo "## Candidate production URLs (scraped from configs + docs)"
  echo ""
  if [[ "${#CANDIDATE_URLS[@]}" -eq 0 ]]; then
    echo "_No production-looking URLs found in apps/*/vercel.json, .env.example, or docs/. Check the production deployment to fill this in manually._"
  else
    for url in "${CANDIDATE_URLS[@]}"; do
      echo "- \`$url\`"
    done
  fi
  echo ""

  if [[ "$DO_PROBE" -eq 1 ]]; then
    echo "## Probe results (\`curl -I\`)"
    echo ""
    echo "| URL | Status | Redirect target |"
    echo "|---|---|---|"
    for rec in "${PROBE_RESULTS[@]}"; do
      IFS='~' read -r url code redir <<< "$rec"
      [[ -z "$redir" ]] && redir="_(none)_"
      echo "| \`$url\` | \`$code\` | \`$redir\` |"
    done
    echo ""
  else
    echo "_Skip-probe mode: re-run with \`--probe\` to record actual redirect chains._"
    echo ""
  fi

  echo "## How to read this file"
  echo ""
  echo "- A **basePath** entry means requests to the bare hostname are server-redirected to that prefix before the app sees them. Bookmarks, OAuth redirect URIs, and external integrations should always include the basePath."
  echo "- A **Vercel env hint** like \`NEXT_PUBLIC_BOOKING_URL=https://app.example.com\` is set at build time and bakes the production hostname into the build. Don't override at runtime."
  echo "- A **URL env var referenced in src/** column lists every \`process.env.X_URL\` referenced by the app's source. If a value isn't set in vercel.json or .env.example, that's a missing-env risk."
  echo ""
  echo "## Maintenance"
  echo ""
  echo "Re-run \`/dev-pipeline:url-topology --probe\`:"
  echo "- After every domain cutover."
  echo "- After every \`next.config.js\` or \`vercel.json\` edit."
  echo "- Whenever an agent or new engineer needs to know where each app lives."
} > "$OUT"

# ── Summary line ─────────────────────────────────────────────────────────────
echo "✓ url-topology captured: $OUT"
echo "  apps detected:       ${#APPS[@]}"
echo "  candidate URLs:      ${#CANDIDATE_URLS[@]}"
if [[ "$DO_PROBE" -eq 1 ]]; then
  echo "  probes recorded:     ${#PROBE_RESULTS[@]}"
fi

exit 0
