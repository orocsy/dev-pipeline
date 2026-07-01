---
description: Phase 7.6 SDK/API reality-check — verifies every third-party SDK method called (or type-stubbed) in the diff against the INSTALLED package's own .d.ts and latest docs (context7), and requires a recorded SDK-PROBE. Catches "typed a method that doesn't exist / invented the return shape → runtime 500". Auto-invoked from /dev-pipeline:validate and /dev-pipeline:review when the diff imports/uses a third-party package or edits a *.d.ts.
argument-hint: "[base-ref]"
---

# Development Pipeline: SDK/API Reality-Check (Phase 7.6)

You are proving that every third-party SDK/API surface the diff *calls* or *types* actually exists — with the exact signature and return shape — in the version installed here. Training knowledge is a guess; a hand-written stub is a guess; both compile, neither runs. This is the gate for CLAUDE.md **Rule 22**.

The failure mode it catches (real, production 500): a stub declared `getUploadMetadata` on `wx-server-sdk` (which ships no types and lacks the method) with an invented top-level shape; the real method lives on `@cloudbase/node-sdk` and returns `{ data: { url, authorization, token, fileId, cosFileId } }`. TS passed; the endpoint 500'd. The installed `.d.ts` had the truth the whole time.

Runs BEFORE Phase 8 validation. Non-optional when the diff touches a third-party surface. All steps pre-approved.

---

## STEP 0: Detect whether this phase applies

```bash
BASE="${1:-$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD~1)}"
DIFF="$(git diff "$BASE"..HEAD)"
FILES="$(git diff --name-only "$BASE"..HEAD)"

# Signal A — an added/edited hand-written type stub for a third-party module.
STUB_HITS="$(echo "$FILES" | grep -E '\.d\.ts$' | grep -vE '(^|/)node_modules/' || true)"

# Signal B — added lines importing a bare (non-relative) package specifier. This catches
# both `pkg` and `@scope/pkg`; it excludes relative (./ ../) and tsconfig aliases (@/…).
# Workspace/first-party packages that slip through are dropped in STEP 1 (they resolve to a
# symlink or a `workspace:` version), so no project-specific scope is hardcoded here.
PKG_IMPORTS="$(echo "$DIFF" | grep -E '^\+' | grep -oE "(import .* from |require\()['\"][^.@/][^'\"]*['\"]|from ['\"]@[^/]+/[^'\"]+['\"]" | grep -vE "workspace:|@/|\.\./|\./" || true)"

if [ -z "$STUB_HITS" ] && [ -z "$PKG_IMPORTS" ]; then
  echo "ℹ️  Diff touches no third-party SDK surface or type stub — SDK reality-check skipped."
  exit 0
fi
echo "🔬 SDK reality-check applies. Stubs: $(echo "$STUB_HITS" | grep -c . ). Pkg-import lines: $(echo "$PKG_IMPORTS" | grep -c . )."
```

---

## STEP 1: Enumerate the third-party surfaces the diff calls or types

Build the list of `(package, method)` pairs to verify:
- From **added call sites** — for each third-party import, grep the diff for `.<method>(` calls on that import's binding.
- From **added/edited `.d.ts` stubs** — every method the stub declares on a third-party module's type is a surface that MUST be proven to exist on THAT package.

For each candidate package, **skip first-party/workspace packages** — they are not third-party surfaces: drop `$PKG` if `node_modules/$PKG` is a symlink (pnpm/npm workspace link) or its `package.json` version is `workspace:*`. Then resolve the installed types root of the remainder:
```bash
[ -L "node_modules/$PKG" ] && { echo "skip $PKG (workspace symlink)"; continue; }
PKGROOT="node_modules/$PKG"                       # or the pnpm path: node_modules/.pnpm/$PKG@*/node_modules/$PKG
TYPES="$(node -e "try{const p=require('$PKG/package.json');process.stdout.write(p.types||p.typings||'index.d.ts')}catch(e){process.stdout.write('')}" 2>/dev/null)"
find node_modules -path "*$PKG*" -name '*.d.ts' 2>/dev/null | head -5   # locate the real declarations (incl. pnpm store)
```

---

## STEP 2: Verify each surface against the INSTALLED package (ground truth)

For each `(package, method)`:
```bash
# The installed pinned version — record it in the probe.
node -e "process.stdout.write(require('$PKG/package.json').version)" 2>/dev/null

# The real declaration + return shape. Read the actual .d.ts, do not guess.
grep -RnA6 "$METHOD" $(find node_modules -path "*$PKG*" -name '*.d.ts' 2>/dev/null) 2>/dev/null | head -30
```
- If the method is **absent** from the installed `.d.ts` → **P1**: the code calls/declares a method that does not exist on this package. (If the package is untyped — ships no `.d.ts` — you MUST instead prove the method exists in its runtime `dist`/source, and confirm it is not a method that belongs to a *different* package. A method borrowed from another SDK onto a hand-written stub is a **P1**.)
- If present → read the EXACT return shape (including nesting). Compare it to how the diff consumes it. Reading top-level `x.url` when the type is `x.data.url` → **P1** (this is the exact production-500 pattern).

---

## STEP 3: Cross-check latest docs via context7 (deprecation / semantics)

```
mcp__context7__resolve-library-id  (libraryName: the package)  → pick the best id
mcp__context7__query-docs          (libraryId, query: "<method> signature and return shape; is it current/deprecated")
```
Installed `.d.ts` is authoritative for *what compiles/runs*; context7 catches *newer signatures, deprecations, and semantics* the pinned `.d.ts` doesn't convey. If context7 has no entry for a narrow server method, note "docs silent — installed .d.ts authoritative" in the probe (still a completed check, not a skip).

---

## STEP 4: Require + update the SDK-PROBE artifact

Every verified surface MUST be recorded (Rule 22 — a design that merely *claims* "verified" without this artifact does not count). Write/append `docs/<feature>/SDK-PROBE.md` (fallback `.claude/sdk-probes/<pkg>.md`):

```markdown
| package@version | method | signature | return shape (exact) | evidence |
|---|---|---|---|---|
| @cloudbase/node-sdk@2.10.0 | app.getUploadMetadata | ({cloudPath}) → Promise<IGetUploadMetadataRes> | { data: { url, token, authorization, fileId, cosFileId, download_url } } | node_modules/@cloudbase/node-sdk/types/index.d.ts:1009-1020 · context7:/websites/cloudbase_net |
```

If a called surface has **no probe row** after this step → **P1** (unverified surface shipped).

---

## STEP 5: Gate

Aggregate into `.claude/sdk-surface-findings-$(git rev-parse --short HEAD).md` (same table columns as `review.md`). Rules:
- **ANY P1** (method absent from installed types / borrowed from wrong package / return-shape mismatch / missing probe row) → **BLOCK**. Print findings; the caller (`/dev-pipeline:review` or `/dev-pipeline:validate`) must route to `/dev-pipeline:fix` and re-run this check.
- Clean → append the audit event and proceed:
```bash
printf '{"event":"verify-sdk-surface.complete","surfaces":%d,"p1":%d,"probed":%d,"sha":"%s","ts":"%s"}\n' \
  "$SURFACES" "$P1" "$PROBED" "$(git rev-parse HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .claude/agent-events.jsonl
```

---

## OUTPUT

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔬 SDK REALITY-CHECK  (base <base>..HEAD)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Surfaces:  <N> (<pkgs>)
Verified:  <M> against installed .d.ts + context7
Probe:     docs/<feature>/SDK-PROBE.md (<rows> rows)
Findings:  <P1> P1   →  [PASS | BLOCK]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## When this is auto-invoked
- `/dev-pipeline:validate` — Phase 7.6, right after `verify-contract` (7.5), before Phase 8.
- `/dev-pipeline:review` — before spawning reviewers, whenever the diff imports/uses a third-party package or edits a `*.d.ts`.
- Design/architecture phase (`/dev-pipeline:plan`, Phase 4) — run the probe FIRST for any feature that will call a third-party SDK, and commit `SDK-PROBE.md` as part of the design. Verifying at design time is cheaper than at the production-500.
