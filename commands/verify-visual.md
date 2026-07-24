---
description: Phase 8.2 visual verification — opens headed browser, captures screenshots of every UI surface touched in the diff, surfaces them for human inspection. Catches "tests pass but UI is broken" and "implementation diverges from design spec." Invoked as Phase 8.2 of /dev-pipeline:pipeline when UI files change.
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

## STEP 3.5: Load the Approved Design Spec

The screenshots are captured — now load what they are *supposed* to show. Phase 3 wrote the approved feature spec to `docs/<slug>/ui-design.md`, and the root `DESIGN.md` is the token authority (color/type/spacing/radii/shadows). Phase 3.5's gate promised this phase would compare the shipped pixels against that spec; **this step is where that promise is kept.**

`SLUG` is THIS pipeline run's feature slug — the `docs/<slug>/` folder Phase 3 created for this feature. You know it from the task/pipeline context; **set it before running this block.** The slug is derived from task context FIRST; the mtime "newest" heuristic is a last resort used ONLY when there is exactly one candidate. Never pick "newest" over a slug you know, and never guess "newest" when several specs exist and the slug is unknown — that silently verifies against the wrong feature's spec.

```bash
# --- Token authority: read the pinned design-system doc (default DESIGN.md when unset) ---
DESIGN_DOC=$(python3 -c "import json;print(json.load(open('.claude/project-context.json')).get('designSystemDoc','DESIGN.md'))" 2>/dev/null || echo DESIGN.md)
[[ -f "$DESIGN_DOC" ]] && DESIGN_TOKENS="$DESIGN_DOC" || DESIGN_TOKENS=""

# --- Approved feature spec: slug from task context FIRST, mtime only when exactly one candidate ---
CANDIDATES=$(ls -t docs/*/ui-design.md 2>/dev/null)
N=$(printf '%s' "$CANDIDATES" | grep -c .)
SPEC_FILE=""

if [[ -n "${SLUG:-}" && -f "docs/${SLUG}/ui-design.md" ]]; then
  SPEC_FILE="docs/${SLUG}/ui-design.md"            # task-context slug wins, unconditionally
elif [[ "$N" -eq 1 ]]; then
  SPEC_FILE="$CANDIDATES"                            # exactly one candidate — mtime is unambiguous
elif [[ "$N" -gt 1 ]]; then
  echo "🛑 PHASE 8.2 BLOCKED — $N ui-design specs exist and this run's slug is unknown."
  echo "   Refusing to guess which spec is this feature's by mtime. Candidates (newest first):"
  printf '%s\n' "$CANDIDATES" | sed 's/^/     /'
  echo "   → ASK THE USER which spec to verify against, set SLUG to that folder, and re-run STEP 3.5."
  exit 1
fi

if [[ -n "$SPEC_FILE" ]]; then
  echo "✅ Approved spec: $SPEC_FILE"
  [[ -n "$DESIGN_TOKENS" ]] && echo "✅ Token authority: $DESIGN_TOKENS" || echo "⚠️  No pinned design-system doc on disk — token conformance will be best-effort."
  echo "$SPEC_FILE" > .claude/.visual-spec.txt
else
  echo "ℹ️  No docs/*/ui-design.md found — this is a pre-Phase-3 feature with no approved spec."
  echo "    → STEP 4 and STEP 5 fall back to the generic checklist and label the output 'no approved spec found — generic review'."
  rm -f .claude/.visual-spec.txt
fi
```

**If a spec was found, read it now** — `Read $SPEC_FILE` and `Read $DESIGN_TOKENS` (the pinned design-system doc) — and for each UI surface the diff touches (the routes in `.claude/.visual-routes.txt`) extract the expectations the later steps will check the screenshots against:

- **Layout** — structure, hierarchy, and the key elements the spec says each surface must contain.
- **States** — enumerate EVERY state the spec lists for that surface (loading / error / empty / success / disabled / … — whatever the spec names). STEP 3 captured only whatever state rendered by default; each remaining state must be triggered and photographed, OR carried into STEP 5 as a BLOCKING finding. A spec-listed state that is neither captured nor explicitly waived (with a reason) blocks the phase — see STEP 5's state-coverage gate. "Note it for later" is not sufficient.
- **Responsive behavior** — the breakpoints and how the layout should reflow, mapped onto the two viewports STEP 3 captured (desktop 1440px, mobile 390px).
- **Named tokens** — the design-system-doc tokens ($DESIGN_TOKENS) the spec cites for that surface (color/type/spacing/radii/shadows), so STEP 5 can flag token drift instead of eyeballing "looks close."

Hold these per-surface expectations — STEP 4 folds them into its diff notes and STEP 5 presents them as the review table. If no spec was found, skip the extraction; the later steps run the generic checklist and say so.

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

When a spec was loaded in STEP 3.5, annotate each diff line with that surface's expected layout/tokens from the spec: a raised `diff_score` on a surface whose approved spec you hold is a *divergence-from-approved-design* signal, not merely "pixels changed" — carry that per-surface verdict into STEP 5's conformance table. With no spec, the diff score stands alone as a raw change indicator.

---

## STEP 5: Surface Screenshots for Review (HARD STOP without baseline)

If no baseline exists OR pixel-diff isn't available, this phase REQUIRES human inspection. **The presentation depends on whether STEP 3.5 loaded a spec** (`.claude/.visual-spec.txt` exists).

**A — Spec found: present the per-surface conformance table** built from the expectations extracted in STEP 3.5, so the human reviews *shipped against approved* rather than against taste. One row per UI surface the diff touched:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖼  VISUAL VERIFICATION — conformance review
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Screenshots: $SHOTS_DIR/   ·   Spec: <SPEC_FILE>   ·   Tokens: <DESIGN_TOKENS>

| Surface / route | Spec section (expected) | States: spec → captured? | Screenshot | Verdict |
|-----------------|-------------------------|--------------------------|------------|---------|
| /checkout | Layout 2-col; tokens color.brand-600, space-4, radius-lg | loading ✅ · error 🛑 not captured · empty ✅ · success ✅ | checkout.png · checkout_mobile.png | ⚠️ diverges: error state never photographed |
| …one row per surface, from .claude/.visual-routes.txt… |

Each row cites the concrete spec expectation (layout, responsive reflow at 1440/390px, named design-system-doc tokens) and gives a conforms/diverges verdict naming the specific divergence.

**State coverage is a hard gate.** The "States" cell must list EVERY state the spec defines for that surface (from STEP 3.5's per-surface extraction). Mark each state one of: **✅ captured** (a screenshot actually shows it), **⚁ waived: \<reason\>** (explicitly excused — e.g. "error state needs a backend 500 not reproducible locally"), or **🛑 not captured**. **Any 🛑 state is a BLOCKING finding** — that row's verdict is ⚠️ diverges, and the phase MUST NOT be ACK'd until the state is captured or waived with a written reason. A silent omission or "noted for later" does not clear the gate.

Reply with one of:
  ACK     → save as new baseline, continue
  REJECT  → list specific issues, halt for fixes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**B — No spec found (pre-Phase-3 feature): fall back to the generic checklist, and say so** in the header so the reviewer knows design conformance was NOT checked:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖼  VISUAL VERIFICATION — manual review required (no approved spec found — generic review)
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

This phase exists because, on a real project, a phone-component "passed E2E" while shipping a single-option fake dropdown.
