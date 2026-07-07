---
description: Phase 8.6 requirements traceability — re-reads the original spec/MIU criteria and verifies each acceptance criterion AND each quality criterion (SPEC.md §6 measurable NFRs) has matching implementation + test. Catches "we shipped a feature that's missing the requirement we promised." Invoked as Phase 8.6 of /dev-pipeline:pipeline (the full feature flow).
---

# Development Pipeline: Requirements Traceability (Phase 8.6)

You are confirming that what you SAID you would build is what you ACTUALLY built. The failure this catches: the spec lists 6 acceptance criteria, the implementation covers 5, the tests assert on 4, and nothing in the pipeline noticed the silent drop. Reviewers approve internally-consistent code. The user sees the missing feature later.

This is the last gate before delivery. It runs after Phase 8 has already passed (so all unit/E2E tests are green) — it's checking the SPEC, not the IMPLEMENTATION QUALITY.

All steps pre-approved.

---

## STEP 0: Locate Specs

The pipeline writes specs to predictable locations. Read them in priority order:

```bash
# 1. Active MIU progress (canonical)
MIU_FILE=".claude/miu-progress.json"

# 2. Original spec (referenced in the MIU)
SPECS=()
if [[ -f "$MIU_FILE" ]]; then
  # Pull spec_path from in-progress / pending-validation MIUs
  while IFS= read -r p; do
    [[ -f "$p" ]] && SPECS+=("$p")
  done < <(jq -r '.tasks[] | select(.status == "pending-validation" or .status == "in-progress") | .spec_path // empty' "$MIU_FILE")
fi

# 3. Default doc locations
#    ISSUE.md is the minimal anchor written by the technical-fault skip branch
#    (dev-pipeline.md / plan.md Phase 1.0) — its "Done when" line IS the
#    acceptance criterion for no-SPEC bug runs.
for candidate in \
  docs/**/*-execution.md \
  docs/**/*-plan.md \
  docs/**/ISSUE.md \
  docs/PROJECT_STATUS.md \
  .claude/docs/PROJECT_STATUS.md; do
  for f in $candidate; do
    [[ -f "$f" ]] && SPECS+=("$f")
  done
done

if [[ ${#SPECS[@]} -eq 0 ]]; then
  echo "🛑 PHASE 8.6 BLOCKED — no spec found to trace against."
  echo "   Either:"
  echo "   1. The current MIU has no spec_path (fix .claude/miu-progress.json), or"
  echo "   2. The work is undocumented (run /dev-pipeline:plan to write a spec retroactively)"
  exit 1
fi

echo "Specs to trace:"
printf '  %s\n' "${SPECS[@]}"
```

---

## STEP 1: Extract Acceptance Criteria

Spawn a sub-agent to read each spec and produce a structured criteria list. Prompt:

> "Read the spec(s) at the paths I'm about to give you. Extract every acceptance criterion AND every quality criterion. Look for:
> - Lines under headings like 'Acceptance Criteria', 'Done When', 'Definition of Done'
> - Lines under headings like 'Quality Criteria' / '质量标准' (SPEC.md section 6 — measurable NFRs: rate limits, audit logging, perf budgets)
> - Bullet points starting with 'Must', 'Should', 'When … then …'
> - Numbered lists describing user-visible behavior
> - 'Test plan' / 'Verification' sections
>
> Output a JSON array: `[{ id: '1', criterion: '<short>', source: '<file:line>', category: 'feature|test|design|api|quality' }]`
>
> Be exhaustive. A criterion that's just a one-liner ('user sees error 410 for expired tokens') still counts.
> Quality criteria trace EXACTLY like acceptance criteria — 'p95 < 500ms' or 'send is audit-logged with tenantId' needs code + test evidence like any feature line. The one exception: an explicit simplicity trade-off entry ('polling not websockets this round') traces to the ABSENCE/choice being honored — cite the implementing file as code_evidence and mark test_evidence '—' if the choice is structural."

Save to `.claude/.traceability-criteria.json`.

```bash
# Confirm the JSON parses
jq length .claude/.traceability-criteria.json
```

---

## STEP 2: Map Each Criterion to Code + Tests

Spawn a second sub-agent. Give it `.claude/.traceability-criteria.json` and `git diff --name-only $BASE..HEAD`. Prompt:

> "For each criterion in the JSON, find evidence in the diff that it was implemented and tested. For each criterion, output:
> - `code_evidence`: list of file:line refs where the implementation lives (use grep)
> - `test_evidence`: list of file:line refs where a test asserts the behavior
> - `status`: one of:
>   - 'IMPLEMENTED_AND_TESTED' — both present
>   - 'IMPLEMENTED_NO_TEST' — code exists, no test asserts it
>   - 'TEST_ONLY' — test exists but no production code (likely the criterion was implemented earlier or in a dependency)
>   - 'MISSING' — no evidence in either
>
> Exception (`category == 'quality'` only — mirrors the STEP 1 extraction exception): a quality criterion that records an explicit simplicity trade-off ('polling not websockets this round') traces to the ABSENCE/choice being honored, not to new code. If the diff honors the recorded choice, cite the implementing file as `code_evidence`, set `test_evidence` to '—', and set `status` 'IMPLEMENTED_AND_TESTED' — do NOT mark it 'MISSING' merely because no test asserts an absence. If the diff violates the recorded choice, mark it 'MISSING' and say which file violates it.
>
> Output `.claude/.traceability-report.json` with the same structure plus the new fields."

---

## STEP 3: Render the Report

```bash
# Generate a human-readable markdown table
cat <<'TPL' > /tmp/render-traceability.mjs
import { readFileSync, writeFileSync } from 'fs';
const data = JSON.parse(readFileSync('.claude/.traceability-report.json', 'utf-8'));

const rows = data.map(c => {
  const icon =
    c.status === 'IMPLEMENTED_AND_TESTED' ? '✅' :
    c.status === 'IMPLEMENTED_NO_TEST'    ? '⚠️' :
    c.status === 'TEST_ONLY'              ? '🟡' :
                                            '❌';
  return `| ${icon} | ${c.id} | ${c.criterion} | ${c.code_evidence?.join(', ') || '—'} | ${c.test_evidence?.join(', ') || '—'} |`;
});

const md = [
  '# Requirements Traceability Report',
  '',
  `Generated: ${new Date().toISOString()}`,
  `SHA: ${process.env.HEAD_SHA || 'unknown'}`,
  '',
  '| Status | # | Criterion | Code | Tests |',
  '|---|---|---|---|---|',
  ...rows,
  '',
  `Total: ${data.length}`,
  `✅ Implemented + tested: ${data.filter(c => c.status === 'IMPLEMENTED_AND_TESTED').length}`,
  `⚠️  Implemented, no test: ${data.filter(c => c.status === 'IMPLEMENTED_NO_TEST').length}`,
  `🟡 Test only: ${data.filter(c => c.status === 'TEST_ONLY').length}`,
  `❌ Missing: ${data.filter(c => c.status === 'MISSING').length}`,
].join('\n');

writeFileSync(`.claude/traceability-report-${process.env.SHORT_SHA}.md`, md);
console.log(md);
TPL

HEAD_SHA=$(git rev-parse HEAD) SHORT_SHA=$(git rev-parse --short HEAD) node /tmp/render-traceability.mjs
```

---

## STEP 4: Gate Decision

```bash
REPORT=".claude/traceability-report-$(git rev-parse --short HEAD).md"
MISSING=$(grep -c '^| ❌ ' "$REPORT" 2>/dev/null || echo 0)
NO_TEST=$(grep -c '^| ⚠️ ' "$REPORT" 2>/dev/null || echo 0)

if [[ "$MISSING" -gt 0 ]]; then
  echo "🛑 PHASE 8.6 BLOCKED — $MISSING criteria from the spec are NOT implemented"
  echo "   See: $REPORT"
  echo ""
  echo "Either:"
  echo "  1. Implement them (return to Phase 7)"
  echo "  2. Update the spec to remove them, with a note explaining why (descope)"
  echo "  3. Confirm they're covered by a sibling MIU and update spec_path"
  echo ""
  echo "Do not proceed to delivery without resolving each missing criterion."
  exit 1
fi

if [[ "$NO_TEST" -gt 2 ]]; then
  echo "⚠️  Phase 8.6 — $NO_TEST criteria are implemented but have no test assertion."
  echo "   See: $REPORT"
  echo "   This is allowed but flagged. Consider adding tests before merging."
fi

echo "✅ Phase 8.6 PASSED — every spec criterion has implementation evidence"
```

---

## STEP 5: Audit Trail

```bash
TOTAL=$(jq length .claude/.traceability-report.json)
IMPLEMENTED=$(jq '[.[] | select(.status == "IMPLEMENTED_AND_TESTED")] | length' .claude/.traceability-report.json)

echo "{\"event\":\"verify-traceability.complete\",\"total\":$TOTAL,\"implemented_tested\":$IMPLEMENTED,\"missing\":$MISSING,\"no_test\":$NO_TEST,\"sha\":\"$(git rev-parse HEAD)\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  >> .claude/agent-events.jsonl
```

---

## What this catches (real failure modes from prior sessions)

- **Spec said "structured phone capture with country prefix selection"** — implementation has a SELECT with one option. Test asserts the field is present, doesn't assert that the country selection is functional. ⚠️ IMPLEMENTED_NO_TEST → user catches it later.
- **Spec said "QR token rotation produces 410 with refresh-on-phone copy"** — implementation overwrites the qrToken column on rotation, so the rotated-old token becomes 404 (token-not-found), never reaches the 410 branch. ❌ MISSING (the spec scenario isn't reachable in the implementation).
- **Spec listed 6 acceptance criteria, implementation covers 5** — reviewers approve, traceability catches the dropped one.
- **Edge case noted in spec but never covered** ("expired token shows refresh-code message") — test only covers happy path.

This phase exists because, on a real project, a spec said one thing, the implementation did another, and the gap was only caught by the user's eyes during a manual browser walkthrough.
