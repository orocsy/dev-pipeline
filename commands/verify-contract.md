---
description: Phase 7.5 API contract verification — diffs frontend payload shapes against backend DTO/schema definitions. Catches "frontend sends extra field, backend rejects with 400" before runtime. Auto-invoked from /dev-pipeline:validate when diff touches both client and server.
---

# Development Pipeline: API Contract Verification (Phase 7.5)

You are checking that the wire format between frontend and backend is consistent. The most common failure mode this catches: backend uses `forbidNonWhitelisted: true` (NestJS), `strict()` (zod), or schema-validators that reject unknown keys, while the frontend silently sends extra fields. Tests pass, runtime returns 400.

This phase runs BEFORE Phase 8 validation. It is non-optional when the diff includes both client and server code.

All steps pre-approved.

---

## STEP 0: Detect Whether This Phase Applies

```bash
BASE="${1:-$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD~1)}"
FILES_CHANGED=$(git diff --name-only "$BASE"..HEAD)

# Frontend signal: any web-app fetch/mutation site
FE_HITS=$(echo "$FILES_CHANGED" | grep -E '^(apps/(web|booking|admin|client|app|frontend)|packages/.*ui|src/components|src/pages|src/app)/' | wc -l | tr -d ' ')

# Backend signal: any controller/route/handler/DTO
BE_HITS=$(echo "$FILES_CHANGED" | grep -E '(controller\.ts|route\.ts|handler\.ts|dto\.ts|\.dto\.|schema\.ts|api/.*\.ts|server/)' | wc -l | tr -d ' ')

if [[ "$FE_HITS" == "0" || "$BE_HITS" == "0" ]]; then
  echo "ℹ️  Diff doesn't span both client and server — contract verification skipped."
  exit 0
fi

echo "⚠️  Diff touches frontend ($FE_HITS files) and backend ($BE_HITS files). Contract verification REQUIRED."
```

---

## STEP 1: Inventory Backend DTOs / Validators

For NestJS / class-validator projects:
```bash
git diff "$BASE"..HEAD --name-only \
  | grep -E '(\.dto\.ts|/dto/.*\.ts)$' \
  | xargs -I{} sh -c 'echo "── {} ──"; grep -nE "@IsString|@IsNumber|@IsBoolean|@IsOptional|@IsEnum|@IsObject|@IsDate|class .*Dto" "{}"' \
  > .claude/.contract-be-shapes.txt
```

For zod / yup / joi projects:
```bash
git diff "$BASE"..HEAD --name-only \
  | grep -E '\.(schema|validator)\.ts$' \
  | xargs -I{} sh -c 'echo "── {} ──"; grep -nE "z\.object|z\.string|z\.number|z\.array|\.optional\(|yup\.object|joi\.object|\.required\(\)" "{}"' \
  >> .claude/.contract-be-shapes.txt
```

Confirm `forbidNonWhitelisted` / `.strict()` / `.passthrough()` policy:
```bash
grep -rn "forbidNonWhitelisted\|whitelist:.*true\|\.strict()\|\.passthrough()\|\.strip()" \
  apps/ packages/ src/ 2>/dev/null \
  | head -20
```

If `forbidNonWhitelisted: true` or `.strict()` is in effect, **any extra field fails the request**. Note this in the report — it raises severity from "warning" to "error."

---

## STEP 2: Inventory Frontend Payloads

```bash
# Find every fetch/axios/mutation that hits a backend route, capture the body shape
git diff "$BASE"..HEAD --name-only \
  | grep -E '\.(ts|tsx)$' \
  | grep -vE '(\.test\.|\.spec\.|\.dto\.)' \
  | xargs grep -nE "fetch\(|axios\.|useMutation|mutate\(|JSON\.stringify\(" 2>/dev/null \
  | head -50 \
  > .claude/.contract-fe-calls.txt
```

For each fetch/mutation, walk back a few lines to capture the body object literal:
```bash
git diff "$BASE"..HEAD --name-only \
  | grep -E '\.(ts|tsx)$' \
  | grep -vE '(\.test\.|\.spec\.)' \
  | while read -r f; do
      grep -nB10 -E "body:.*JSON\.stringify|body:.*\{|data:.*\{" "$f" 2>/dev/null \
        | head -40 >> .claude/.contract-fe-shapes.txt
    done
```

---

## STEP 3: Diff and Report

Spawn a focused sub-agent with the two shape files. Prompt:

> "Compare the backend DTO/validator shapes in `.claude/.contract-be-shapes.txt` against the frontend payload shapes in `.claude/.contract-fe-shapes.txt`. For each backend endpoint touched in this diff, identify:
> 1. Frontend fields that don't exist in the DTO (will trigger 400 if forbidNonWhitelisted)
> 2. Backend required fields the frontend doesn't send
> 3. Type mismatches (string vs number, optional vs required, enum vs free-form)
> 4. Naming drift (camelCase vs snake_case)
>
> Output a markdown table: | Endpoint | Issue | FE field | BE field | Severity |
> Severity = ERROR if forbidNonWhitelisted is on; WARN otherwise."

Save the agent output to `.claude/contract-report-$(git rev-parse --short HEAD).md`.

---

## STEP 4: Gate Decision

```bash
REPORT=$(ls -1 .claude/contract-report-*.md | tail -1)
ERR_COUNT=$(grep -c '| ERROR |' "$REPORT" 2>/dev/null || echo 0)
WARN_COUNT=$(grep -c '| WARN |' "$REPORT" 2>/dev/null || echo 0)

if [[ "$ERR_COUNT" -gt 0 ]]; then
  echo "🛑 PHASE 7.5 BLOCKED — $ERR_COUNT contract mismatches will return HTTP 400 in production."
  echo "   See: $REPORT"
  echo "   Fix the frontend payloads or update the DTOs, then re-run /dev-pipeline:verify-contract"
  exit 1
fi

if [[ "$WARN_COUNT" -gt 3 ]]; then
  echo "⚠️  Phase 7.5 — $WARN_COUNT warnings. Review and acknowledge before proceeding."
  echo "   See: $REPORT"
fi

echo "✅ Phase 7.5 PASSED — frontend ↔ backend shapes consistent"
```

---

## STEP 5: Audit Trail

```bash
echo "{\"event\":\"verify-contract.complete\",\"errors\":$ERR_COUNT,\"warns\":$WARN_COUNT,\"sha\":\"$(git rev-parse HEAD)\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  >> .claude/agent-events.jsonl
```

---

## What this catches (real failure modes from prior sessions)

- **`@IsObject()` validator dropped from one DTO but two callers still send the field** — `forbidNonWhitelisted: true` returns 400, frontend form silently fails.
- **Frontend sends `phoneCountry: 'HK'` but DTO declares `country: string`** — naming drift, 400 in prod.
- **Backend renames `customerId` → `customerIdNew`, frontend not updated** — runtime failure on every booking.
- **Optional → required tightening on backend, frontend still omits the field** — every legacy form fails.

This phase exists because a real project hit each of the above in production at least once.
