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
# `git diff "$BASE"` (no `..HEAD`) — NOT `"$BASE"..HEAD`. The latter excludes the working
# tree/index entirely, so a pre-commit invocation (this file is wired into validate.md's
# Phase 8, which runs BEFORE commit/deliver) would see a NEWLY ADDED third-party call as
# invisible — Rule 22 silently skipped at exactly the point it matters most. `git diff
# "$BASE"` is a strict superset: with nothing uncommitted it equals `"$BASE"..HEAD`
# (verified); with uncommitted work (staged or not) it also includes that.
DIFF="$(git diff "$BASE")"
FILES="$(git diff --name-only "$BASE")"
DIFF_ADDED="$(echo "$DIFF" | grep -E '^\+' || true)"

# Every SIG_*/FULL_HIT regex below is single-line: `import ... from '...'` must appear on
# ONE line to match. A multiline import (Prettier/multi-symbol imports wrap routinely):
#   import {
#     fooMethod,
#   } from 'some-pkg'
# matches NONE of them, silently skipping the whole gate. Collapse multiline import blocks
# onto one logical line first — buffer an unterminated `import` line until a line
# containing ` from '...'` closes it. (No `\b` word-boundary — this system's `awk` doesn't
# support it, unlike `grep -E`; anchor on `import` followed by space/`{`/`*` instead so
# `importantVariable = 1` is never mistaken for an import statement.)
DIFF_ADDED_JOINED="$(printf '%s\n' "$DIFF_ADDED" | awk '
  BEGIN { buf="" }
  /^\+[[:space:]]*import[[:space:]{*]/ && !/ from [\x27"]/ { buf=$0; next }
  buf != "" {
    buf = buf " " $0
    if ($0 ~ / from [\x27"]/) { print buf; buf=""; next }
    next
  }
  { print }
')"

# Signal A — an added/edited hand-written type stub for a third-party module.
STUB_HITS="$(echo "$FILES" | grep -E '\.d\.ts$' | grep -vE '(^|/)node_modules/' || true)"

# Signal B — added lines that introduce a bare (non-relative) package specifier, in ANY
# of the four forms JS/TS code actually uses. A bare specifier's first char (right after
# the quote) is never '.' (that's relative) — that is the only exclusion needed at the
# regex level; tsconfig `@/` aliases and pnpm `workspace:` versions are dropped by the
# post-filter below (both contain the literal substrings excluded there). Erring toward
# over-matching here is fine — false positives just get filtered in STEP 1; a false
# NEGATIVE would silently skip the gate, which is the actual danger.
SIG_IMPORT="$(printf '%s\n' "$DIFF_ADDED_JOINED" | grep -oE "import[^;()]* from ['\"][^.][^'\"]*['\"]" || true)"
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
# Same multiline-import collapse as above, applied to full-file content (no `+` prefix here).
while IFS= read -r F; do
  [ -z "$F" ] && continue
  [ -f "$F" ] || continue   # skip deleted files
  FILE_JOINED="$(awk '
    BEGIN { buf="" }
    /^[[:space:]]*import[[:space:]{*]/ && !/ from [\x27"]/ { buf=$0; next }
    buf != "" {
      buf = buf " " $0
      if ($0 ~ / from [\x27"]/) { print buf; buf=""; next }
      next
    }
    { print }
  ' "$F" 2>/dev/null)"
  FULL_HIT="$(printf '%s\n' "$FILE_JOINED" | grep -oE "import[^;()]* from ['\"][^.][^'\"]*['\"]|require\(['\"][^.][^'\"]*['\"]\)" | grep -vE '@/|workspace:' || true)"
  [ -z "$FULL_HIT" ] && continue
  FILE_DIFF_ADDED="$(git diff "$BASE" -- "$F" | grep -E '^\+' || true)"
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

**1c. For each remaining package, resolve its bindings and every method called on them, and persist `(package, method)` to `$SURF_FILE`.** This is fully mechanical — a concrete loop, not a "for each X, do Y" narrative the agent has to improvise. Three things this MUST get right, each independently verified by execution:
- **Both `import` and `require()` forms** — `import { x } from 'pkg'`, `const x = require('pkg')`, and `const { x } = require('pkg')` all bind `x` to something from `pkg`; missing the `require()` forms silently drops any CommonJS-style surface.
- **Both member-call and bare/constructor-call forms** — `binding.method(` (member call — the method is what's verified) and `binding(` / `new binding(` (the binding itself IS the callable export being verified, e.g. `import { format } from 'date-fns'; format(...)`).
- **Bindings resolved from the FULL FILE, not just `$DIFF_ADDED`** — a Signal-C case (new call on an ALREADY-imported package) has no import/require line in the diff at all; the binding only exists in the file's pre-existing content. Calls are still only checked against `$DIFF_ADDED`, since only NEW calls need verifying.

```bash
SHA="$(git rev-parse --short HEAD)"
mkdir -p .claude
SURF_FILE=".claude/sdk-surfaces-${SHA}.txt"
: > "$SURF_FILE"

while IFS= read -r PKG; do
  [ -z "$PKG" ] && continue
  # This package's import/require line(s), searched across every touched file's FULL
  # CURRENT content (covers both a brand-new import and a pre-existing one).
  PKG_LINES=""
  while IFS= read -r F; do
    [ -z "$F" ] && continue
    [ -f "$F" ] || continue
    HIT="$(grep -E "(import.* from |require\().*['\"]${PKG}(/|['\"])" "$F" 2>/dev/null || true)"
    [ -n "$HIT" ] && PKG_LINES="${PKG_LINES}
${HIT}"
  done <<< "$(echo "$FILES" | grep -vE '\.d\.ts$' || true)"
  PKG_LINES="$(printf '%s\n' "$PKG_LINES" | grep -v '^$' || true)"
  [ -z "$PKG_LINES" ] && continue

  # Bindings: named (incl. `as` aliases), default, namespace, plain require(), destructured require().
  BINDINGS=""
  while IFS= read -r LINE; do
    [ -z "$LINE" ] && continue
    NAMED="$(printf '%s' "$LINE" | grep -oE '\{[^}]*\}' | tr -d '{}' | tr ',' '\n' | sed -E 's/.*as[[:space:]]+//' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    DEFAULT="$(printf '%s' "$LINE" | grep -oE '^\+?import[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*' | grep -oE '[A-Za-z_$][A-Za-z0-9_$]*$' | grep -v '^import$')"
    NS="$(printf '%s' "$LINE" | grep -oE '\*[[:space:]]+as[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*' | grep -oE '[A-Za-z_$][A-Za-z0-9_$]*$')"
    REQ_PLAIN="$(printf '%s' "$LINE" | grep -oE '(const|let|var)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=[[:space:]]*require\(' | grep -oE '[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=[[:space:]]*require' | grep -oE '^[A-Za-z_$][A-Za-z0-9_$]*')"
    REQ_NAMED="$(printf '%s' "$LINE" | grep -oE '\{[^}]*\}[[:space:]]*=[[:space:]]*require\(' | grep -oE '\{[^}]*\}' | tr -d '{}' | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    BINDINGS="${BINDINGS}
${NAMED}
${DEFAULT}
${NS}
${REQ_PLAIN}
${REQ_NAMED}"
  done <<< "$PKG_LINES"
  BINDINGS="$(printf '%s\n' "$BINDINGS" | grep -v '^$' | sort -u)"

  while IFS= read -r B; do
    [ -z "$B" ] && continue
    # Member calls: binding.method( — method is the surface. (Also catches namespace
    # member-calls, e.g. AWS.S3( after `import * as AWS from 'aws-sdk'` — "S3" is the
    # method verified against the AWS package.)
    while IFS= read -r M; do
      [ -n "$M" ] && printf '%s\t%s\n' "$PKG" "$M" >> "$SURF_FILE"
    done < <(printf '%s\n' "$DIFF_ADDED" | grep -oE "\b${B}\.[A-Za-z_][A-Za-z0-9_]*\(" | sed -E "s/^${B}\.//; s/\($//")
    # Bare/constructor calls: binding( or new binding( — the binding itself is the surface.
    printf '%s\n' "$DIFF_ADDED" | grep -qE "\b${B}\(" && printf '%s\t%s\n' "$PKG" "$B" >> "$SURF_FILE"
  done <<< "$BINDINGS"
done <<< "$PKG_LIST"
sort -u -o "$SURF_FILE" "$SURF_FILE"
```

Also add every method name declared in an added/edited `.d.ts` stub for a third-party module — a type-only surface (never called yet) must ALSO be proven per STEP 2.

---

## STEP 2: Verify each surface against the INSTALLED package (ground truth)

A real `while read` loop over `$SURF_FILE`, with **`P1` explicitly initialized and accumulated** — the P1 conditions below are not narrative bullet points the agent has to remember to act on; each one is a concrete `P1=$((P1+1))` in the loop. (A prior draft of this file listed P1 conditions in prose only, with no code anywhere that ever incremented a `P1` variable — meaning the gate could report a clean pass with real P1s sitting undetected. This loop is the fix.)

```bash
P1=0
SURFACES=0
while IFS=$'\t' read -r PKG METHOD; do
  [ -z "$PKG" ] && continue
  SURFACES=$((SURFACES+1))

  # Resolve the package's REAL install directory via Node's own module resolution —
  # do NOT `find node_modules -path "*$PKG*"` (unanchored substring match): for a short
  # unscoped name like "is" or "ms" that matches unrelated packages too (e.g. "is-plain-
  # object", "mime-is-fake"), letting a method declared in the WRONG package's .d.ts
  # satisfy the existence check. require.resolve also transparently handles pnpm/hoisted
  # nesting, which a manual find would need to special-case.
  DTS_FILES=""
  if node -e "require.resolve('$PKG/package.json')" 2>/dev/null; then
    PKGDIR="$(node -e "console.log(require.resolve('$PKG/package.json').replace(/\/package\.json\$/,''))" 2>/dev/null)"
    DTS_FILES="$(find "$PKGDIR" -name '*.d.ts' 2>/dev/null)"
  fi
  # The installed pinned version — record it in the probe.
  VERSION="$(node -e "process.stdout.write(require('$PKG/package.json').version)" 2>/dev/null)"

  if [ -z "$DTS_FILES" ]; then
    # Untyped package — do NOT default to "unproven, skip it." Prove it mechanically both ways.
    # (a) Does the method exist in the PACKAGE'S OWN runtime source?
    RUNTIME_HIT="$(grep -RIn "\b$METHOD\b" "node_modules/$PKG" --include='*.js' --include='*.cjs' --include='*.mjs' 2>/dev/null | grep -v '/test/' | head -10)"
    if [ -z "$RUNTIME_HIT" ]; then
      P1=$((P1+1))
      echo "🛑 P1: $PKG::$METHOD — untyped package, method NOT found in its own runtime source"
      # (b) Does it exist on a DIFFERENT installed package — the stub borrowing the wrong
      #     SDK's method? (The exact root cause of the reference bug: getUploadMetadata
      #     lived on @cloudbase/node-sdk, not the wx-server-sdk stub.)
      WRONG_PKG_HIT="$(grep -RIln "\b$METHOD\b" node_modules --include='*.d.ts' 2>/dev/null | grep -v "node_modules/$PKG/")"
      [ -n "$WRONG_PKG_HIT" ] && echo "   -> method belongs to a DIFFERENT package: $WRONG_PKG_HIT (inject that SDK explicitly, never fake it onto $PKG's type)"
    fi
  else
    # Typed package — the real declaration + return shape. Read the actual .d.ts, do not guess.
    DECL="$(grep -RnA6 "$METHOD" $DTS_FILES 2>/dev/null | head -30)"
    if [ -z "$DECL" ]; then
      P1=$((P1+1))
      echo "🛑 P1: $PKG::$METHOD — absent from the installed .d.ts (method does not exist on this package)"
    else
      echo "$PKG::$METHOD ($VERSION) — declared shape:"
      printf '%s\n' "$DECL"
      # Read the EXACT return shape (incl. nesting) above, then compare to how the diff
      # actually CONSUMES it. Context covers BOTH member-call (.method() — round 1) and
      # bare/constructor-call (method()/new method() — round 2 fix, STEP 1c now enumerates
      # both forms as surfaces but this consumption check must recognize both too) forms.
      echo "  consumption context:"
      printf '%s\n' "$DIFF_ADDED" | grep -A3 -E "\.$METHOD\(|\b$METHOD\("
      printf '%s\n' "$DIFF_ADDED" | grep -oE "(const|let)[^=]*=[[:space:]]*(await )?(new )?[A-Za-z0-9_.]*\b$METHOD\([^)]*\)|\.$METHOD\([^)]*\)\.[A-Za-z0-9_.]+"
      # Reading top-level `x.url` in the consumption context when the declared shape is
      # `x.data.url` → P1 (the exact production-500 pattern). This comparison is a judgment
      # call against the printed DECL above, not a regex — shape structure isn't
      # mechanically diffable without a real type parser. If it's wrong: P1=$((P1+1)).
    fi
  fi
done < "$SURF_FILE"
```

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
# PLURAL — STEP 4's documented fallback is one file PER PACKAGE
# (.claude/sdk-probes/<pkg>.md), not a single hardcoded probe.md. A hardcoded singular
# filename meant a project following the documented fallback was silently never read
# here, so every surface reported unprobed regardless of real probe work done.
PROBE_FILES="$(find docs -maxdepth 2 -name 'SDK-PROBE.md' 2>/dev/null)"
[ -z "$PROBE_FILES" ] && PROBE_FILES="$(find .claude/sdk-probes -maxdepth 1 -name '*.md' 2>/dev/null)"

SURFACES=0
PROBED=0
UNPROBED_LIST=""
while IFS=$'\t' read -r PKG METHOD; do
  [ -z "$PKG" ] && continue
  SURFACES=$((SURFACES+1))
  ROW_MATCH=0
  while IFS= read -r PF; do
    [ -z "$PF" ] && continue
    [ -f "$PF" ] || continue
    while IFS= read -r ROW; do
      case "$ROW" in *"|"*) ;; *) continue ;; esac
      if printf '%s' "$ROW" | grep -qF "$PKG" && printf '%s' "$ROW" | grep -qF "$METHOD"; then
        ROW_MATCH=1
        break 2
      fi
    done < "$PF"
  done <<< "$PROBE_FILES"
  if [ "$ROW_MATCH" -eq 1 ]; then
    PROBED=$((PROBED+1))
  else
    UNPROBED_LIST="${UNPROBED_LIST}${PKG}::${METHOD}, "
  fi
done < "$SURF_FILE"

if [ "$PROBED" -lt "$SURFACES" ]; then
  MISSING=$((SURFACES-PROBED))
  P1=$((P1+MISSING))   # accumulate into the SAME $P1 STEP 2 built — a prior draft only
                        # echoed this diagnostic without ever incrementing P1, so a clean
                        # STEP 2 pass plus unprobed surfaces still reported PASS at STEP 5.
  echo "🛑 $MISSING surface(s) have NO probe row (P1): $UNPROBED_LIST"
fi
```

This is the real enforcement of Rule 22's "a design that merely *claims* verified without this artifact does not count" — the join is computed from the persisted surface list, not recalled by the agent that wrote the probe (an agent that under-enumerates surfaces in STEP 1 does NOT get a free pass; `$SURF_FILE` was written before STEP 2's per-surface verification, so it can't retroactively shrink to match a thin probe).

Aggregate ALL P1s (from STEP 2's method-existence/wrong-package/shape checks, plus this join) into `.claude/sdk-surface-findings-$(git rev-parse --short HEAD).md` (same table columns as `review.md`). Rules:
- **ANY P1** (method absent from installed types / borrowed from wrong package / return-shape mismatch / missing probe row) → **BLOCK**. Print findings; the caller (`/dev-pipeline:review` or `/dev-pipeline:validate`) must route to `/dev-pipeline:fix` and re-run this check.
- Clean (`PROBED == SURFACES` and `$P1 -eq 0`) → append the audit event and proceed. `$P1` here is the SAME variable STEP 2 accumulated into (plus this step's missing-probe additions) — never re-defaulted to 0, since that would silently discard whatever STEP 2 found:
```bash
printf '{"event":"verify-sdk-surface.complete","surfaces":%d,"p1":%d,"probed":%d,"sha":"%s","ts":"%s"}\n' \
  "$SURFACES" "${P1:-0}" "$PROBED" "$(git rev-parse HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .claude/agent-events.jsonl
```
(`${P1:-0}` only in the `printf` itself, as a defensive default for the rare case STEP 0 skipped before STEP 2 ever ran — it does not reset an already-accumulated `$P1`.)

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
