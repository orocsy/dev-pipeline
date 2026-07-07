#!/usr/bin/env bash
# run-fixture-tests.sh — asserts tools/validate-miu-breakdown.sh behaviour
# against the committed fixtures in this directory (evals/BACKLOG.md → MIU-D).
#
# Covers:
#   compliant.md            → exit 0 (also as a CRLF variant and a
#                             column-0-bullet variant, both generated here)
#   missing-fields.md       → exit 1 with named field/enum/count messages
#   ordering-violations.md  → exit 1 for the TRUE violations only:
#                               - forward dependency (unit 3 → unit 4)
#                               - consumer-before-contract (unit 3 consumes
#                                 unit 4's DTO file without listing it)
#                             while the co-editor pattern (units 1 + 2 both
#                             listing schema.prisma in their own Files:) must
#                             NOT be flagged.
#
# Exit 0 = every assertion passed.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$HERE/../../validate-miu-breakdown.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0

# t <label> <expected_exit> <file> [assertion ...]
#   assertion 'substring'  → output MUST contain it (fixed-string match)
#   assertion '!substring' → output must NOT contain it
t() {
  local label="$1" want="$2" file="$3"; shift 3
  local out got ok=1 a
  out="$(bash "$VALIDATOR" "$file" 2>&1)"; got=$?
  [[ $got -eq $want ]] || { echo "    exit code: want $want, got $got"; ok=0; }
  for a in "$@"; do
    if [[ "$a" == '!'* ]]; then
      grep -qF -- "${a#!}" <<<"$out" && { echo "    must NOT contain: ${a#!}"; ok=0; }
    else
      grep -qF -- "$a" <<<"$out" || { echo "    missing expected: $a"; ok=0; }
    fi
  done
  if [[ $ok -eq 1 ]]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label"
    printf '%s\n' "$out" | sed 's/^/    | /'
    fails=$((fails + 1))
  fi
}

# 1. Compliant breakdown passes.
t "compliant.md passes" 0 "$HERE/compliant.md" \
  "OK: 3 MIU(s) validated"

# 2. CRLF variant of the compliant breakdown passes
#    (regression: \r broke the Block/Type enum checks).
sed 's/$/\r/' "$HERE/compliant.md" > "$WORK/compliant-crlf.md"
t "compliant.md with CRLF line endings passes" 0 "$WORK/compliant-crlf.md" \
  "OK: 3 MIU(s) validated"

# 3. Column-0-bullet variant passes
#    (regression: bullet regex required leading indentation).
sed -E 's/^[[:space:]]+//' "$HERE/compliant.md" > "$WORK/compliant-col0.md"
t "compliant.md with column-0 bullets passes" 0 "$WORK/compliant-col0.md" \
  "OK: 3 MIU(s) validated"

# 4. Missing/invalid fields fail with named messages.
t "missing-fields.md fails with named messages" 1 "$HERE/missing-fields.md" \
  'MIU 1: missing mandatory field "Test plan"' \
  'MIU 1: missing mandatory field "Done when"' \
  'MIU 2: Block "DATABASE" is not one of' \
  'MIU 2: Files lists 4 paths' \
  'MIU 2: "Done when" has 1 criteria'

# 5. Ordering violations: TRUE violations flagged; co-editor pattern exempt
#    (regression: an earlier unit listing the same file in its own Files: was
#    false-flagged as consumer-before-contract).
t "ordering-violations.md flags only the true violations" 1 "$HERE/ordering-violations.md" \
  'FAIL: 2 violation(s) in 4 MIU(s)' \
  'MIU 3: depends on LATER MIU 4' \
  'MIU 3: consumes contract file create-referral.dto.ts defined by LATER MIU 4' \
  '!MIU 1: consumes contract file' \
  '!MIU 2: consumes contract file'

echo ""
if [[ $fails -eq 0 ]]; then
  echo "ALL FIXTURE ASSERTIONS PASSED"
  exit 0
else
  echo "$fails fixture test(s) FAILED"
  exit 1
fi
