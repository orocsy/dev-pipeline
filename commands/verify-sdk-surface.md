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
DIFF_ADDED="$(echo "$DIFF" | grep -E '^\+' || true)"

# Signal A — an added/edited hand-written type stub for a third-party module.
STUB_HITS="$(echo "$FILES" | grep -E '\.d\.ts$' | grep -vE '(^|/)node_modules/' || true)"

# Signal B — added lines that introduce a bare (non-relative) package specifier, in ANY
# of the four forms JS/TS code actually uses. A bare specifier's first char (right after
# the quote) is never '.' (that's relative) — that is the only exclusion needed at the
# regex level; tsconfig `@/` aliases and pnpm `workspace:` versions are dropped by the
# post-filter below (both contain the literal substrings excluded there). Erring toward
# over-matching here is fine — false positives just get filtered in STEP 1; a false
# NEGATIVE would silently skip the gate, which is the actual danger.
SIG_IMPORT="$(printf '%s\n' "$DIFF_ADDED" | grep -oE "import[^;()]* from ['\"][^.][^'\"]*['\"]" || true)"
SIG_REQUIRE="$(printf '%s\n' "$DIFF_ADDED" | grep -oE "require\(['\"][^.][^'\"]*['\"]\)" || true)"
SIG_DYNIMPORT="$(printf '%s\n' "$DIFF_ADDED" | grep -oE "import\(['\"][^.][^'\"]*['\"]\)" || true)"
SIG_SIDEEFFECT="$(printf '%s\n' "$DIFF_ADDED" | grep -oE "^\+[[:space:]]*import ['\"][^.][^'\"]*['\"]" || true)"
PKG_IMPORTS="$(printf '%s\n%s\n%s\n%s\n' "$SIG_IMPORT" "$SIG_REQUIRE" "$SIG_DYNIMPORT" "$SIG_SIDEEFFECT" \
  | grep -v '^$' | grep -vE '@/|workspace:' || true)"

# Signal C — a diff can add a NEW call on an ALREADY-imported third-party package with
# NO new import/require line and NO .d.ts edit; signals A/B (both diff-scoped) miss this
# entirely. For each touched, non-deleted file: scan the FULL FILE (not just the diff) for
# bare-specifier imports, and if the file's ADDED lines contain any call-like pattern
# (`.method(`), fold that file's full-file import hit into PKG_IMPORTS. Broad on purpose —
# STEP 1 narrows to the actual surfaces; a false negative here silently skips the gate.
while IFS= read -r F; do
  [ -z "$F" ] && continue
  [ -f "$F" ] || continue   # skip deleted files
  FULL_HIT="$(grep -oE "import[^;()]* from ['\"][^.][^'\"]*['\"]|require\(['\"][^.][^'\"]*['\"]\)" "$F" 2>/dev/null | grep -vE '@/|workspace:' || true)"
  [ -z "$FULL_HIT" ] && continue
  FILE_DIFF_ADDED="$(git diff "$BASE"..HEAD -- "$F" | grep -E '^\+' || true)"
  echo "$FILE_DIFF_ADDED" | grep -qE '\.[A-Za-z_][A-Za-z0-9_]*\(' && PKG_IMPORTS="$(printf '%s\n%s\n' "$PKG_IMPORTS" "$FULL_HIT")"
done <<< "$(echo "$FILES" | grep -vE '\.d\.ts$' || true)"
# NOTE: this loop uses `while read` rather than `for F in $(...)` — word-splitting a
# multi-line command substitution via `for` depends on the ambient $IFS, which is not
# guaranteed to include newline in every shell context. `while read` is IFS-independent.
PKG_IMPORTS="$(printf '%s\n' "$PKG_IMPORTS" | grep -v '^$' | sort -u)"

if [ -z "$STUB_HITS" ] && [ -z "$PKG_IMPORTS" ]; then
  echo "ℹ️  Diff touches no third-party SDK surface or type stub — SDK reality-check skipped."
  return 0 2>/dev/null || exit 0   # safe whether this block is sourced or run standalone
fi
echo "🔬 SDK reality-check applies. Stubs: $(echo "$STUB_HITS" | grep -c . ). Pkg-import lines: $(echo "$PKG_IMPORTS" | grep -c . )."
```

---

## STEP 1: Enumerate the third-party surfaces the diff calls or types

**1a. Reduce each matched import line to a bare package name** (strip to `@scope/name` for scoped packages, or the first path segment for unscoped ones — `lodash/fp` → `lodash`, `@scope/pkg/sub` → `@scope/pkg`):
```bash
PKG_LIST="$(printf '%s\n' "$PKG_IMPORTS" \
  | grep -oE "['\"][^'\"]+['\"]" | tr -d "'\"" \
  | sed -E 's#^(@[^/]+/[^/]+|[^/]+).*#\1#' \
  | sort -u)"
```

**1b. Drop first-party/workspace packages** — they are not third-party surfaces. Uses `while read` (not `for PKG in $PKG_LIST`, same IFS-portability reason as 1a's replacement above) and sends "skip" diagnostics to STDERR so they never pollute the accumulated package list on stdout (a prior draft mixed them into the same stream — a consumer of the tmp file would then see `skip <pkg> (workspace symlink)` as if it were a real package name):
```bash
while IFS= read -r PKG; do
  [ -z "$PKG" ] && continue
  if [ -L "node_modules/$PKG" ]; then echo "skip $PKG (workspace symlink)" >&2; continue; fi
  if node -e "process.exit(require('$PKG/package.json').version.startsWith('workspace:')?0:1)" 2>/dev/null; then echo "skip $PKG (workspace: version)" >&2; continue; fi
  echo "$PKG"   # a genuine third-party candidate — accumulate into the surface list below
done <<< "$PKG_LIST" > .claude/co-review-thirdparty-packages.tmp
```

**1c. For each remaining package, find every `.<method>(` call on its import binding** in `$DIFF_ADDED` (for call sites) and every method name declared in an added/edited `.d.ts` stub for that module (for type-only surfaces — these must ALSO be proven, per STEP 2, even if never called yet). **Also check bare-call and constructor-call forms** — a third-party API used as a direct function (`import { format } from 'date-fns'; format(...)`) or class (`import S3Client from '...'; new S3Client(...)`) never produces a `.<method>(` match, so it would ship unprobed. Extract the binding names from the package's import statement (named/default/namespace forms) and additionally grep `$DIFF_ADDED` for `\b<binding>\(` (this single pattern also matches `new <binding>\(`, since `new ` ends the word boundary right before the name):
```bash
# Named-import bindings (respecting `as` aliases), default-import binding, namespace binding.
BINDINGS=""
while IFS= read -r LINE; do
  [ -z "$LINE" ] && continue
  NAMED="$(printf '%s' "$LINE" | grep -oE '\{[^}]*\}' | tr -d '{}' | tr ',' '\n' | sed -E 's/.*as[[:space:]]+//' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  DEFAULT="$(printf '%s' "$LINE" | grep -oE '^\+?import[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*' | grep -oE '[A-Za-z_$][A-Za-z0-9_$]*$' | grep -v '^import$')"
  NS="$(printf '%s' "$LINE" | grep -oE '\*[[:space:]]+as[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*' | grep -oE '[A-Za-z_$][A-Za-z0-9_$]*$')"
  BINDINGS="${BINDINGS}
${NAMED}
${DEFAULT}
${NS}"
done <<< "$(printf '%s\n' "$DIFF_ADDED" | grep -E "^\+.*import.* from ")"
BINDINGS="$(printf '%s\n' "$BINDINGS" | grep -v '^$' | sort -u)"
while IFS= read -r B; do
  [ -z "$B" ] && continue
  echo "$DIFF_ADDED" | grep -qE "\b${B}\(" && echo "$B is called/constructed — add (package, \$B) to the surface list below"
done <<< "$BINDINGS"
```
A namespace member-call (`AWS.S3(...)` after `import * as AWS from 'aws-sdk'`) is already covered by the pre-existing `.<method>(`-on-binding check above — `S3` is the method to verify, `AWS` the binding it's scoped to.

**Persist the full `(package, method)` list as a checkable artifact** — STEP 4/5 diff against this file rather than trusting recollection:
```bash
SHA="$(git rev-parse --short HEAD)"
mkdir -p .claude
SURF_FILE=".claude/sdk-surfaces-${SHA}.txt"
: > "$SURF_FILE"
# for each (PKG, METHOD) found above:
printf '%s\t%s\n' "$PKG" "$METHOD" >> "$SURF_FILE"
sort -u -o "$SURF_FILE" "$SURF_FILE"
```

---

## STEP 2: Verify each surface against the INSTALLED package (ground truth)

For each `(package, method)` in `$SURF_FILE`:
```bash
# The installed pinned version — record it in the probe.
node -e "process.stdout.write(require('$PKG/package.json').version)" 2>/dev/null

# The real declaration + return shape. Read the actual .d.ts, do not guess.
DTS_FILES="$(find node_modules -path "*$PKG*" -name '*.d.ts' 2>/dev/null)"
grep -RnA6 "$METHOD" $DTS_FILES 2>/dev/null | head -30
```

**If `$DTS_FILES` is empty (untyped package) — do NOT default to "unproven, skip it."** Prove it mechanically both ways:
```bash
# (a) Does the method exist in the PACKAGE'S OWN runtime source?
grep -RIn "\b$METHOD\b" "node_modules/$PKG" --include='*.js' --include='*.cjs' --include='*.mjs' 2>/dev/null | grep -v '/test/' | head -10
# Nothing found → the method is UNPROVEN on this package → P1.

# (b) Does the method exist on a DIFFERENT installed package — i.e. is the stub
#     borrowing the wrong SDK's method? (This is the exact root cause of the reference
#     bug: getUploadMetadata lived on @cloudbase/node-sdk, not the wx-server-sdk stub.)
grep -RIln "\b$METHOD\b" node_modules --include='*.d.ts' 2>/dev/null | grep -v "node_modules/$PKG/"
# A hit here → the method belongs to a DIFFERENT package → P1: fix is to inject that
# package explicitly, never to fake the method onto $PKG's type.
```

- Method **absent** from the installed `.d.ts` (typed package) → **P1**: the code calls/declares a method that does not exist on this package.
- Method **unproven** in runtime source (untyped package, step (a) above empty) → **P1**.
- Method found via step (b) on a **different** package → **P1** (wrong-package borrowing).
- Method present (typed or runtime-proven) → read the EXACT return shape (including nesting), then compare it to how the diff actually CONSUMES it — extract the real consumption lines, don't compare from memory:
```bash
# The lines where the diff destructures or accesses fields off the call's return value.
printf '%s\n' "$DIFF_ADDED" | grep -A3 -E "\.$METHOD\("
printf '%s\n' "$DIFF_ADDED" | grep -oE "(const|let)[^=]*=[[:space:]]*(await )?[A-Za-z0-9_.]*\.$METHOD\([^)]*\)|\.$METHOD\([^)]*\)\.[A-Za-z0-9_.]+"
```
Reading top-level `x.url` in those lines when the declared/runtime-proven type is `x.data.url` → **P1** (the exact production-500 pattern).

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

---

## STEP 5: Gate — mechanically JOIN the surface list against the probe table

Do NOT take your own word for "every surface has a probe row" — diff `$SURF_FILE` (STEP 1c) against the actual probe table content. A surface is "probed" only if BOTH its package name and its method name appear on the SAME table row — two independent file-wide checks would let a package on one row and an unrelated method on a different row falsely count as probed (this is exactly the reference bug's shape: `wx-server-sdk` + `getUploadMetadata` would falsely "pass" if any OTHER row happened to mention `getUploadMetadata`):

```bash
PROBE_FILE="$(find docs -maxdepth 2 -name 'SDK-PROBE.md' 2>/dev/null | head -1)"
[ -z "$PROBE_FILE" ] && PROBE_FILE=".claude/sdk-probes/probe.md"

SURFACES=0
PROBED=0
UNPROBED_LIST=""
while IFS=$'\t' read -r PKG METHOD; do
  [ -z "$PKG" ] && continue
  SURFACES=$((SURFACES+1))
  ROW_MATCH=0
  if [ -f "$PROBE_FILE" ]; then
    while IFS= read -r ROW; do
      case "$ROW" in *"|"*) ;; *) continue ;; esac
      if printf '%s' "$ROW" | grep -qF "$PKG" && printf '%s' "$ROW" | grep -qF "$METHOD"; then
        ROW_MATCH=1
        break
      fi
    done < "$PROBE_FILE"
  fi
  if [ "$ROW_MATCH" -eq 1 ]; then
    PROBED=$((PROBED+1))
  else
    UNPROBED_LIST="${UNPROBED_LIST}${PKG}::${METHOD}, "
  fi
done < "$SURF_FILE"

[ "$PROBED" -lt "$SURFACES" ] && echo "🛑 $((SURFACES-PROBED)) surface(s) have NO probe row (P1): $UNPROBED_LIST"
```

This is the real enforcement of Rule 22's "a design that merely *claims* verified without this artifact does not count" — the join is computed from the persisted surface list, not recalled by the agent that wrote the probe (an agent that under-enumerates surfaces in STEP 1 does NOT get a free pass; `$SURF_FILE` was written before STEP 2's per-surface verification, so it can't retroactively shrink to match a thin probe).

Aggregate ALL P1s (from STEP 2's method-existence/wrong-package/shape checks, plus this join) into `.claude/sdk-surface-findings-$(git rev-parse --short HEAD).md` (same table columns as `review.md`). Rules:
- **ANY P1** (method absent from installed types / borrowed from wrong package / return-shape mismatch / missing probe row) → **BLOCK**. Print findings; the caller (`/dev-pipeline:review` or `/dev-pipeline:validate`) must route to `/dev-pipeline:fix` and re-run this check.
- Clean (`PROBED == SURFACES` and zero other P1s) → append the audit event and proceed:
```bash
P1="${P1:-0}"
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
- **Not** re-run wholesale at design time — the `technical-architect` agent (Phase 4 of `/dev-pipeline:plan` / `/dev-pipeline:dev-pipeline`) performs the same context7 + installed-types verification directly as part of designing, before code exists, and records it in the design's "Third-Party Surfaces Verified" table (which becomes the seed rows of `docs/<feature>/SDK-PROBE.md`). This command is the mechanical, implementation-time re-check that catches drift between the design and what actually got built — the two checkpoints share one standard (CLAUDE.md Rule 22) but run at different times for different reasons.
