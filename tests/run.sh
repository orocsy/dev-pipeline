#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n \
  "$ROOT/hooks/session-start.sh" \
  "$ROOT/tools/pipeline-pointer-valid.sh" \
  "$ROOT/tools/resolve-feature-doc.sh" \
  "$ROOT/tools/resolve-traceability-specs.sh" \
  "$ROOT/tests/pipeline-pointer-valid.test.sh" \
  "$ROOT/tests/resolve-feature-doc.test.sh" \
  "$ROOT/tests/resolve-traceability-specs.test.sh" \
  "$ROOT/tests/session-start-tracked-handoff.test.sh"

"$ROOT/tests/resolve-feature-doc.test.sh"
"$ROOT/tests/session-start-tracked-handoff.test.sh"
"$ROOT/tests/pipeline-pointer-valid.test.sh"
"$ROOT/tests/resolve-traceability-specs.test.sh"

echo "PASS: all dev-pipeline shell tests"