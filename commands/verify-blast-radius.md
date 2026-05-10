---
description: Phase 8.1 blast radius analysis — finds dependents of changed shared modules and runs their tests, even if not directly modified. Catches "shared selector renamed, dependent E2E silently broken." Auto-invoked from /dev-pipeline:validate.
---

# Development Pipeline: Blast Radius Verification (Phase 8.1)

You are identifying the downstream impact of changes to shared code. The failure this catches: a refactor renames a component prop, the canonical test gets updated, but five OTHER specs that import the same component now have stale selectors and pass-by-not-running (no execution path) or fail silently (skipped tests).

This phase runs as part of Phase 8 validation. It does NOT replace running the unit tests of changed files — it adds the dependent files' tests on top.

All steps pre-approved.

---

## STEP 0: Identify Shared Modules in the Diff

```bash
BASE="${1:-$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD~1)}"
CHANGED=$(git diff --name-only "$BASE"..HEAD)

# A "shared module" is any file under packages/, libs/, src/components/, src/lib/,
# or anything imported from outside its own app directory.
SHARED_FILES=$(echo "$CHANGED" \
  | grep -E '^(packages/|libs/|apps/[^/]+/src/(components|lib|utils|hooks|types|ui)/|src/(components|lib|utils|hooks|types)/)' \
  | grep -vE '(\.test\.|\.spec\.|\.stories\.)')

if [[ -z "$SHARED_FILES" ]]; then
  echo "ℹ️  No shared module changes detected — blast radius skipped."
  exit 0
fi

echo "Shared files modified ($(echo "$SHARED_FILES" | wc -l | tr -d ' ')):"
echo "$SHARED_FILES"
```

---

## STEP 1: Find Direct Importers

```bash
> .claude/.blast-radius-importers.txt

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  base=$(basename "$f" | sed -E 's/\.(ts|tsx|js|jsx)$//')

  # 1. Find files that import this module by path
  modpath=$(echo "$f" | sed -E 's/\.(ts|tsx|js|jsx)$//')
  IMPORTERS=$(grep -rln "from ['\"].*${base}['\"]\|from ['\"].*${modpath}['\"]" \
    apps/ packages/ libs/ src/ tests/ 2>/dev/null \
    | grep -v "^${f}$" \
    | sort -u)

  if [[ -n "$IMPORTERS" ]]; then
    echo "── ${f} ──" >> .claude/.blast-radius-importers.txt
    echo "$IMPORTERS" >> .claude/.blast-radius-importers.txt
  fi
done <<< "$SHARED_FILES"

cat .claude/.blast-radius-importers.txt
```

Important: this is grep, not an AST. Capture more than you need; over-coverage is safer than under-coverage.

---

## STEP 2: Find E2E Specs That Reference Changed Identifiers

This is the high-value check. E2E specs use string selectors (testIds, role+name, text) that don't get updated by IDE rename. They're the most common silent-break source.

```bash
# Pull every renamed-or-deleted symbol from the diff
RENAMED=$(git diff "$BASE"..HEAD -- "*.ts" "*.tsx" \
  | grep -E '^-' | grep -vE '^---' \
  | grep -oE '(data-testid="[^"]+"|export (function|const|class) [A-Z][a-zA-Z0-9]+|name: ['"'"'"][^'"'"'"]+['"'"'"]|getByTestId\(['"'"'"][^'"'"'"]+['"'"'"]\))' \
  | sort -u)

if [[ -n "$RENAMED" ]]; then
  echo "Symbols / testIds removed in diff:"
  echo "$RENAMED"

  # Find E2E specs that still reference them
  echo "$RENAMED" | while read -r ref; do
    [[ -z "$ref" ]] && continue
    # Just the bare identifier
    needle=$(echo "$ref" | grep -oE '"[^"]+"|[A-Z][a-zA-Z0-9]+' | head -1 | tr -d '"')
    [[ -z "$needle" ]] && continue
    grep -rln --include="*.spec.ts" --include="*.test.ts" "$needle" tests/ apps/*/tests/ 2>/dev/null
  done | sort -u > .claude/.blast-radius-stale-e2e.txt

  if [[ -s .claude/.blast-radius-stale-e2e.txt ]]; then
    echo ""
    echo "⚠️  E2E specs that reference removed/renamed identifiers:"
    cat .claude/.blast-radius-stale-e2e.txt
    echo ""
    echo "These specs may now use stale selectors. Run them — do not assume green-from-not-running."
  fi
fi
```

---

## STEP 3: Run Affected Tests

Compose the test set: importers' tests + stale-e2e specs.

```bash
# Find test files corresponding to importers
> .claude/.blast-radius-test-targets.txt
grep -v '^── ' .claude/.blast-radius-importers.txt 2>/dev/null | while read -r src; do
  [[ -z "$src" ]] && continue
  base=$(basename "$src" | sed -E 's/\.(ts|tsx|js|jsx)$//')
  dir=$(dirname "$src")
  # Same-dir __tests__ pattern + sibling .test.ts pattern
  for candidate in \
    "${dir}/__tests__/${base}.test.ts" \
    "${dir}/__tests__/${base}.test.tsx" \
    "${dir}/${base}.test.ts" \
    "${dir}/${base}.test.tsx" \
    "${dir}/${base}.spec.ts" \
    "${dir}/${base}.spec.tsx"; do
    [[ -f "$candidate" ]] && echo "$candidate"
  done
done | sort -u >> .claude/.blast-radius-test-targets.txt

cat .claude/.blast-radius-stale-e2e.txt 2>/dev/null >> .claude/.blast-radius-test-targets.txt

if [[ -s .claude/.blast-radius-test-targets.txt ]]; then
  echo "Running blast-radius tests:"
  cat .claude/.blast-radius-test-targets.txt
  pnpm jest $(cat .claude/.blast-radius-test-targets.txt | grep -E '\.(test|spec)\.tsx?$' | grep -v '\.e2e\.' | tr '\n' ' ') 2>&1 \
    | tee .claude/.blast-radius-results.txt
fi
```

For E2E specs:
```bash
E2E_TARGETS=$(cat .claude/.blast-radius-test-targets.txt | grep -E 'tests/.*\.spec\.ts$')
if [[ -n "$E2E_TARGETS" ]]; then
  echo "Running blast-radius E2E specs (headed):"
  npx playwright test $E2E_TARGETS --headed --workers=1 \
    2>&1 | tee -a .claude/.blast-radius-results.txt
fi
```

---

## STEP 4: Gate Decision

```bash
TARGET_COUNT=$(wc -l < .claude/.blast-radius-test-targets.txt 2>/dev/null | tr -d ' ' || echo 0)
FAILED=$(grep -cE 'FAIL|✗|×' .claude/.blast-radius-results.txt 2>/dev/null || echo 0)

if [[ "$FAILED" -gt 0 ]]; then
  echo "🛑 PHASE 8.1 BLOCKED — $FAILED dependent tests failed (blast radius from $TARGET_COUNT targets)"
  echo "   See: .claude/.blast-radius-results.txt"
  echo "   These tests use code you changed — fix them before proceeding."
  exit 1
fi

echo "✅ Phase 8.1 PASSED — $TARGET_COUNT dependent tests still green"
```

---

## STEP 5: Audit Trail

```bash
echo "{\"event\":\"verify-blast-radius.complete\",\"targets\":$TARGET_COUNT,\"failed\":$FAILED,\"sha\":\"$(git rev-parse HEAD)\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  >> .claude/agent-events.jsonl
```

---

## What this catches (real failure modes from prior sessions)

- **Phone field split into `phoneCountry` + `phoneNationalNumber`**, ten pre-existing E2E specs still use `name: /^phone/i` and silently break (10 broken tests undiscovered until full E2E sweep).
- **Component renamed** in the canonical file, dependent stories/tests still reference the old name, type-check passes, runtime fails.
- **Shared utility's signature changes** (added required argument), dependent files type-check because of inference but throw at runtime.
- **A `data-testid` value changes**, dependent E2E specs match the old testId, fail with "element not found" but only when actually run.

This phase exists because LuxeBook's WS1 phone-component refactor silently broke 10 pre-existing E2E specs that no test filter would have caught.
