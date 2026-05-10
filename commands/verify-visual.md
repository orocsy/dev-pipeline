---
description: Phase 8.2 visual verification — opens headed browser, captures screenshots of every UI surface touched in the diff, surfaces them for human inspection. Catches "tests pass but UI is broken" and "implementation diverges from design spec." Auto-invoked from /dev-pipeline:validate when UI files change.
---

# Development Pipeline: Visual Verification (Phase 8.2)

You are confirming that the UI a user sees matches the design intent. The failure this catches: E2E asserts `getByRole('combobox').click()`, the click works, the test passes — but the dropdown only has one option (so it's a fake-dropdown UX anti-pattern), or the spacing/layout is broken, or an icon is missing. Tests are green; the page is wrong.

This phase requires a headed browser and is mandatory for every UI-touching MIU.

All steps pre-approved.

---

## STEP 0: Detect UI Surfaces Touched

```bash
BASE="${1:-$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD~1)}"
UI_FILES=$(git diff --name-only "$BASE"..HEAD \
  | grep -E '\.(tsx|jsx|vue|svelte|css|scss|tailwind\.config\.)$' \
  | grep -vE '(\.test\.|\.spec\.|\.stories\.|/__tests__/)')

if [[ -z "$UI_FILES" ]]; then
  echo "ℹ️  No UI files in diff — visual verification skipped."
  exit 0
fi

echo "UI files changed:"
echo "$UI_FILES"
```

---

## STEP 1: Map UI Files to Routes

For Next.js App Router projects:
```bash
# Files under app/[…]/page.tsx → routes
echo "$UI_FILES" \
  | grep -E '/(page|layout)\.tsx$' \
  | sed -E 's|.*/app|app|; s|/page\.tsx$||; s|/layout\.tsx$||' \
  > .claude/.visual-routes.txt

# Component files → find which routes import them (best-effort)
echo "$UI_FILES" \
  | grep -E '/(components|ui)/.*\.tsx$' \
  | while read -r f; do
      base=$(basename "$f" .tsx)
      grep -rln "import.*${base}" apps/*/src/app 2>/dev/null \
        | grep -E '/(page|layout)\.tsx$' \
        | sed -E 's|.*/app|app|; s|/page\.tsx$||' \
        | head -5
    done >> .claude/.visual-routes.txt

sort -u -o .claude/.visual-routes.txt .claude/.visual-routes.txt
cat .claude/.visual-routes.txt
```

---

## STEP 2: Boot Dev Server (Headed-Browser-Friendly)

```bash
# Use the project's existing pipeline-e2e helper if present
if [[ -x scripts/pipeline-e2e.sh ]]; then
  # Spin up only the dev servers, not the full E2E run
  bash scripts/pipeline-e2e.sh --servers-only &
  SERVERS_PID=$!
else
  pnpm dev &> .claude/.visual-dev.log &
  SERVERS_PID=$!
fi

# Wait for readiness
TIMEOUT=120
while ! curl -sf http://localhost:3000 >/dev/null 2>&1 && [[ $TIMEOUT -gt 0 ]]; do
  sleep 1; ((TIMEOUT--))
done

[[ $TIMEOUT -eq 0 ]] && { echo "🛑 Dev server didn't come up in 120s"; kill $SERVERS_PID 2>/dev/null; exit 1; }
echo "✅ Dev server ready on :3000"
```

---

## STEP 3: Capture Screenshots via Headed Playwright

Write the runner inline so the project doesn't need a permanent script:
```bash
SHOTS_DIR=".claude/visual-verify/$(git rev-parse --short HEAD)"
mkdir -p "$SHOTS_DIR"

cat > /tmp/visual-shot.mjs <<'JS'
import { chromium } from 'playwright';
import { readFileSync } from 'fs';

const routes = readFileSync(process.argv[2], 'utf-8')
  .split('\n')
  .filter(Boolean)
  .map(r => r.startsWith('app') ? r.replace(/^app/, '') : r);

const baseUrl = process.argv[3] || 'http://localhost:3000';
const outDir = process.argv[4];

const browser = await chromium.launch({ headless: false, slowMo: 250 });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

for (const r of routes) {
  // Replace [param] with a placeholder; users will need to swap real values for parametric routes
  const url = baseUrl + (r === '' ? '/' : r).replace(/\[[^\]]+\]/g, 'preview');
  console.log('→', url);
  try {
    await page.goto(url, { waitUntil: 'networkidle', timeout: 15_000 });
    const safe = (r || 'root').replace(/[^\w]+/g, '_').slice(0, 60);
    await page.screenshot({ path: `${outDir}/${safe}.png`, fullPage: true });
    // Also capture mobile
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: `${outDir}/${safe}_mobile.png`, fullPage: true });
    await page.setViewportSize({ width: 1440, height: 900 });
  } catch (e) {
    console.log('   ⚠️ failed:', e.message);
  }
}
await browser.close();
JS

node /tmp/visual-shot.mjs .claude/.visual-routes.txt http://localhost:3000 "$SHOTS_DIR"
```

For routes with `[param]` placeholders, the runner uses `'preview'` — extend manually if those don't render. Don't silently skip them.

---

## STEP 4: Visual-Diff Against Baseline (if baseline exists)

```bash
BASELINE_DIR=".claude/visual-baseline"
if [[ -d "$BASELINE_DIR" ]]; then
  if command -v compare &>/dev/null; then
    # ImageMagick compare
    > "$SHOTS_DIR/.diffs.txt"
    for shot in "$SHOTS_DIR"/*.png; do
      name=$(basename "$shot")
      if [[ -f "$BASELINE_DIR/$name" ]]; then
        diff_score=$(compare -metric AE "$BASELINE_DIR/$name" "$shot" /tmp/diff.png 2>&1 | head -1)
        echo "$name: $diff_score" >> "$SHOTS_DIR/.diffs.txt"
      fi
    done
    cat "$SHOTS_DIR/.diffs.txt"
  else
    echo "ℹ️  ImageMagick not installed — skipping pixel-diff. Manual review required."
  fi
fi
```

---

## STEP 5: Surface Screenshots for Review (HARD STOP without baseline)

If no baseline exists OR pixel-diff isn't available, this phase REQUIRES human inspection:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖼  VISUAL VERIFICATION — manual review required
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Screenshots: $SHOTS_DIR/
Routes covered: $(wc -l < .claude/.visual-routes.txt | tr -d ' ')

Open the directory and confirm:
  [ ] Layout matches design intent (no overflow, no overlapping elements)
  [ ] Form controls render real options (no fake-dropdown with one option)
  [ ] Mobile layout (≤390px) is not broken
  [ ] Icons load (no broken-image squares)
  [ ] Typography matches design tokens
  [ ] Hover/focus states reachable

Reply with one of:
  ACK     → save as new baseline, continue
  REJECT  → list specific issues, halt for fixes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

The pipeline does NOT proceed until the user types ACK or REJECT in the chat.

On ACK:
```bash
mkdir -p .claude/visual-baseline
cp "$SHOTS_DIR"/*.png .claude/visual-baseline/
echo "✅ New visual baseline saved."
```

On REJECT:
```bash
echo "🛑 PHASE 8.2 BLOCKED — visual issues reported"
exit 1
```

---

## STEP 6: Teardown + Audit Trail

```bash
kill $SERVERS_PID 2>/dev/null

echo "{\"event\":\"verify-visual.complete\",\"shots\":$(ls "$SHOTS_DIR"/*.png 2>/dev/null | wc -l | tr -d ' '),\"sha\":\"$(git rev-parse HEAD)\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  >> .claude/agent-events.jsonl
```

---

## What this catches (real failure modes from prior sessions)

- **Phone country dropdown with one option** — E2E `.click()` works, page renders, design said "structured prefix selection" but implementation is theatre.
- **Mobile layout broken** below 390px width because nobody resized the browser during testing.
- **Icon imports missing** after a UI lib refactor — desktop test passed because no assertion on the icon, page looks empty for users.
- **Spacing/typography drift** from a Tailwind preset change — shipped a broken design.
- **Hover state never tested** — disabled-looking button on dashboard, users can't tell it's clickable.

This phase exists because LuxeBook's WS1 phone-component "passed E2E" while shipping a single-option fake dropdown.
