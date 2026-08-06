#!/usr/bin/env bash
# run-craft-gates.sh
#
# Runs the engineering-craft executable gates over the CURRENT repo and reports one
# aggregated verdict. Called by /dev-pipeline:review STEP 1.7 and
# /dev-pipeline:validate STEP 2.7 — both of which previously inlined this as fenced
# bash in markdown.
#
# WHY THIS IS A SCRIPT AND NOT A CODE FENCE
# -----------------------------------------
# The first cut lived as a bash block inside review.md. It referenced $SRC_DIRS and
# $TEST_DIR, which nothing defined; validate.md's copy referenced a ${GATE_ARGS[...]}
# associative array that was never declared; and the baseline comparison the prose
# specified had no implementation at all. None of that was caught by running it,
# because a fenced block in a command file is READ, never EXECUTED — every human and
# agent who "verified" the step did so by running the gates by hand with explicit
# arguments, which is a different program. Making it a real file makes it runnable,
# and therefore falsifiable.
#
# EXIT CODES — three states, deliberately distinct
#   0  all gates clean, or not applicable to this repo
#   1  findings (at or above the blocking threshold after baseline subtraction)
#   2  gate execution error — a template is missing, crashed, or emitted an
#      unparseable result. Collapsing this onto 1 would report infrastructure
#      breakage as code findings; collapsing it onto 0 would silently skip the gate.
#
# USAGE
#   tools/run-craft-gates.sh [--baseline-write] [--changed-files <file>] [--json]
#
#   --baseline-write   record current findings as the accepted baseline and exit 0
#   --changed-files    newline-delimited paths; findings in these files ALWAYS block
#                      regardless of baseline
#   --json             emit machine-readable results (for the review findings table)
#
# CONFIG (optional) — .claude/gates/config.json in the consuming repo:
#   { "srcDirs": ["apps","packages"], "testDir": "tests",
#     "proofSteps": ["pnpm test"], "disabled": ["probe-sensitivity"] }
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || exit 2

GATES_DIR="${ENGINEERING_CRAFT_TEMPLATES:-$HOME/.claude/skills/engineering-craft/templates}"
GATE_STATE_DIR="$REPO_ROOT/.claude/gates"
BASELINE_FILE="$GATE_STATE_DIR/baseline.json"
CONFIG_FILE="$GATE_STATE_DIR/config.json"

MODE_BASELINE_WRITE=0
MODE_JSON=0
CHANGED_FILES_LIST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline-write) MODE_BASELINE_WRITE=1; shift ;;
    --json)           MODE_JSON=1; shift ;;
    --changed-files)
      CHANGED_FILES_LIST="${2:-}"
      if [[ -z "$CHANGED_FILES_LIST" || ! -f "$CHANGED_FILES_LIST" ]]; then
        echo "GATE ERROR — --changed-files needs a readable file (got: '${CHANGED_FILES_LIST:-<none>}')." >&2
        echo "  Without it, findings in files this diff touched would not block." >&2
        exit 2
      fi
      shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ── Gate availability ───────────────────────────────────────────────────────
# A missing templates directory is a SETUP problem, not a clean repo. Reporting
# it as 0 is the false-green this whole gate set exists to prevent.
if [[ ! -d "$GATES_DIR" ]]; then
  echo "GATE ERROR — engineering-craft templates not found at $GATES_DIR"
  echo "  The skill has not bootstrapped. Gates did NOT run; this is not a pass."
  echo "  Fix: git clone --depth 1 https://github.com/orocsy/engineering-craft.git \\"
  echo "         ~/.claude/skills/engineering-craft"
  exit 2
fi

jqr() { command -v jq >/dev/null 2>&1 && jq -r "$@" 2>/dev/null; }

# A config that exists but cannot be parsed is a SETUP error, not "use defaults".
# Silently falling back discards the repo's deliberate settings and reports success.
if [[ -f "$CONFIG_FILE" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "GATE ERROR — $CONFIG_FILE exists but jq is not installed; its settings would be silently ignored." >&2
    exit 2
  fi
  if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "GATE ERROR — $CONFIG_FILE is not valid JSON; refusing to fall back to defaults." >&2
    exit 2
  fi
fi

# ── Repo shape detection ────────────────────────────────────────────────────
# Derived, never assumed. The previous inline version referenced $SRC_DIRS with
# nothing setting it, so every gate ran with `--dir ""`.
detect_src_dirs() {
  local cfg
  cfg=$([[ -f "$CONFIG_FILE" ]] && jqr '.srcDirs // [] | join(",")' <"$CONFIG_FILE")
  if [[ -n "${cfg:-}" ]]; then echo "$cfg"; return; fi
  local found=()
  for d in apps packages src lib app server client; do
    [[ -d "$d" ]] && found+=("$d")
  done
  # A repo with none of the conventional roots still has SOMETHING; fall back to
  # the tracked top-level dirs rather than emitting an empty --dir.
  if [[ ${#found[@]} -eq 0 ]]; then
    while IFS= read -r d; do [[ -d "$d" ]] && found+=("$d"); done < <(
      git ls-files | awk -F/ 'NF>1{print $1}' | sort -u | grep -vE '^\.' | head -5
    )
  fi
  (IFS=,; echo "${found[*]:-.}")
}

detect_test_dir() {
  local cfg
  cfg=$([[ -f "$CONFIG_FILE" ]] && jqr '.testDir // empty' <"$CONFIG_FILE")
  if [[ -n "${cfg:-}" ]]; then echo "$cfg"; return; fi
  # Every root, not the first. Returning early meant a repo with both tests/ and e2e/
  # never had its E2E skips inspected while the aggregate reported the gate passing.
  local roots=()
  for d in tests test e2e __tests__ spec; do [[ -d "$d" ]] && roots+=("$d"); done
  if [[ ${#roots[@]} -gt 0 ]]; then (IFS=,; echo "${roots[*]}"); return; fi
  # No dedicated test dir — but colocated specs are the common layout, and returning
  # "" made skip-policy report NOT APPLICABLE on every such repo. Point it at the
  # source roots instead; it filters to spec files itself.
  if git ls-files | grep -qE '\.(test|spec)\.[jt]sx?$'; then
    detect_src_dirs; return
  fi
  echo ""
}

# The pipeline-causality gate's built-in default is the bare command `test`, which its
# (correctly) anchored matcher will never find inside `pnpm test` / `npm test`. Left to
# the default it reported two false positives on a correctly-chained pipeline — a gate
# that cries wolf gets switched off. Derive the real proof command from the repo's own
# package manager and synthesise the config when the repo has not pinned one.
# Emits a JSON ARRAY, not a joined string. Joining with " " turned
# ["pnpm test","pnpm lint"] into the single command "pnpm test pnpm lint", which the
# gate's anchored matcher can never find — silently disabling a repo's own config.
detect_proof_steps_json() {
  if [[ -f "$CONFIG_FILE" ]]; then
    local arr
    arr=$(jqr -c '.proofSteps // empty' <"$CONFIG_FILE")
    if [[ -n "${arr:-}" && "$arr" != "null" && "$arr" != "[]" ]]; then printf '%s' "$arr"; return; fi
  fi
  # Node is not the only supported stack. Emitting `npm test` for a Python/Rust/Go
  # repo asks the anchored matcher to find a command that does not exist there, so a
  # correctly-causal pipeline is reported as a P1 — a gate that cries wolf on an
  # entire language gets switched off.
  if [[ -f package.json ]]; then
    local pm="npm"
    [[ -f pnpm-lock.yaml ]] && pm="pnpm"
    [[ -f yarn.lock ]] && pm="yarn"
    [[ -f bun.lockb ]] && pm="bun"
    printf '["%s test"]' "$pm"; return
  fi
  [[ -f Cargo.toml ]] && { printf '["cargo test"]'; return; }
  [[ -f go.mod ]] && { printf '["go test"]'; return; }
  if [[ -f pyproject.toml || -f requirements.txt || -f tox.ini ]]; then
    printf '["pytest","python -m pytest"]'; return
  fi
  [[ -f Gemfile ]] && { printf '["bundle exec rspec","rake test"]'; return; }
  [[ -f pom.xml ]] && { printf '["mvn test"]'; return; }
  [[ -f build.gradle || -f build.gradle.kts ]] && { printf '["gradle test"]'; return; }
  # Unknown stack: emit the common forms rather than one wrong guess.
  printf '["npm test","make test"]'
}

SRC_DIRS="$(detect_src_dirs)"
TEST_DIR="$(detect_test_dir)"

# Synthesise a pipeline config from the detected proof command when the repo has none,
# so the gate is exercised with a command that actually exists here.
PIPELINE_CFG="$GATE_STATE_DIR/pipeline.json"
if [[ ! -f "$PIPELINE_CFG" ]]; then
  PIPELINE_CFG="$(mktemp)"
  printf '{"proofSteps":%s}\n' "$(detect_proof_steps_json)" > "$PIPELINE_CFG"
  trap 'rm -f "$PIPELINE_CFG"' EXIT
fi
DISABLED=$([[ -f "$CONFIG_FILE" ]] && jqr '.disabled // [] | join(" ")' <"$CONFIG_FILE")
DISABLED="${DISABLED:-}"

# ── Per-gate argument table ─────────────────────────────────────────────────
gate_args() {
  case "$1" in
    pipeline-causality)        echo "--config $PIPELINE_CFG" ;;
    form-degradation)          echo "--dir $SRC_DIRS" ;;
    trust-boundary-decoding)   echo "--dir $SRC_DIRS" ;;
    async-child-busy-contract) echo "--dir $SRC_DIRS" ;;
    skip-policy)               [[ -n "$TEST_DIR" ]] && echo "--dir $TEST_DIR --config $GATE_STATE_DIR/skip.json" || echo "--dir __none__" ;;
    probe-sensitivity)         echo "--config $GATE_STATE_DIR/probe-sensitivity.json" ;;
    family-registry)           echo "--config $GATE_STATE_DIR/claim-registry.json" ;;
    catalog-integrity)         echo "--root $REPO_ROOT" ;;
    *)                         echo "" ;;
  esac
}

ALL_GATES="pipeline-causality form-degradation skip-policy trust-boundary-decoding async-child-busy-contract probe-sensitivity family-registry"

# ── Run ─────────────────────────────────────────────────────────────────────
mkdir -p "$GATE_STATE_DIR"
declare -a SUMMARY=()
CURRENT_FINDINGS_FILE="$(mktemp)"
: > "$CURRENT_FINDINGS_FILE"
EXEC_ERRORS=0
TOTAL_FINDINGS=0

for gate in $ALL_GATES; do
  if [[ " $DISABLED " == *" $gate "* ]]; then
    SUMMARY+=("  SKIP  $gate — disabled in .claude/gates/config.json")
    continue
  fi

  tpl="$GATES_DIR/$gate.template.mjs"
  # Per-template existence check. The inline version tested only the directory, so
  # a partially-synced skill silently ran fewer gates than it reported.
  if [[ ! -f "$tpl" ]]; then
    SUMMARY+=("  ERROR $gate — template missing at $tpl")
    EXEC_ERRORS=$((EXEC_ERRORS + 1))
    continue
  fi

  # shellcheck disable=SC2046
  out="$(node "$tpl" $(gate_args "$gate") 2>&1)"; rc=$?
  fails="$(printf '%s\n' "$out" | grep -c '^FAIL' || true)"

  case "$rc" in
    0)
      # A gate exiting 0 while PRINTING findings is the inverse contract violation
      # of "exit 1 with no FAIL lines", and strictly worse: labelling it PASS
      # discards every diagnostic it just produced. Both directions are execution
      # errors — the gate is not reporting what it found.
      if [[ "$fails" -gt 0 ]]; then
        SUMMARY+=("  ERROR $gate — exit 0 with $fails FAIL line(s) (contract violation; findings discarded)")
        printf '%s\n' "$out" | grep '^FAIL' | head -3 | sed 's/^/          /' >&2
        EXEC_ERRORS=$((EXEC_ERRORS + 1))
      elif printf '%s\n' "$out" | grep -q '^NOT APPLICABLE'; then
        SUMMARY+=("  N/A   $gate")
      else
        SUMMARY+=("  PASS  $gate")
      fi
      ;;
    1)
      # A gate that exits 1 with zero FAIL lines has broken its own contract:
      # exit 1 means findings, and findings are printed. Treat as an exec error
      # rather than inventing a count.
      if [[ "$fails" -eq 0 ]]; then
        SUMMARY+=("  ERROR $gate — exit 1 with no FAIL lines (contract violation)")
        EXEC_ERRORS=$((EXEC_ERRORS + 1))
      else
        SUMMARY+=("  FAIL  $gate — $fails finding(s)")
        TOTAL_FINDINGS=$((TOTAL_FINDINGS + fails))
        printf '%s\n' "$out" | grep '^FAIL' | sed "s|^FAIL |$gate\t|" >> "$CURRENT_FINDINGS_FILE"
      fi
      ;;
    *)
      SUMMARY+=("  ERROR $gate — exit $rc")
      printf '%s\n' "$out" | head -3 | sed 's/^/          /' >&2
      EXEC_ERRORS=$((EXEC_ERRORS + 1))
      ;;
  esac
done

# ── Baseline ────────────────────────────────────────────────────────────────
# Findings are keyed by "gate<TAB>file:line" so a whole-surface gate can adopt
# pre-existing debt without blocking the author who did not create it.
# Key = gate + the file:line token only. Including the human-readable message meant
# a reworded finding no longer matched its own baseline entry and re-blocked.
finding_keys() {
  awk -F'\t' '{ split($2, a, " "); print $1 "\t" a[1] }' "$1" | sed 's/[[:space:]]*$//' | sort -u
}

if [[ "$MODE_BASELINE_WRITE" -eq 1 ]]; then
  # Refuse a partial baseline. If a gate errored, its findings are absent from this
  # run, so recording now would permanently accept debt that was never measured.
  if [[ "$EXEC_ERRORS" -gt 0 ]]; then
    echo "Refusing to write a baseline: $EXEC_ERRORS gate(s) failed to execute, so this run did not measure the full surface." >&2
    rm -f "$CURRENT_FINDINGS_FILE"
    exit 2
  fi
  # Serialised by jq, not string-concatenation: keys contain tabs, quotes and
  # backslashes, and hand-built JSON produced a file the next run could not parse —
  # which read as "no baseline", making every finding look new forever.
  if command -v jq >/dev/null 2>&1; then
    finding_keys "$CURRENT_FINDINGS_FILE" \
      | jq -R -s --arg sha "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
             --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          '{recordedAt:$ts, sha:$sha, accepted: (split("\n") | map(select(length>0)))}' \
      > "$BASELINE_FILE"
  else
    echo "GATE ERROR — jq is required to write a baseline safely." >&2
    rm -f "$CURRENT_FINDINGS_FILE"
    exit 2
  fi
  echo "Baseline written: $BASELINE_FILE ($(finding_keys "$CURRENT_FINDINGS_FILE" | wc -l | tr -d ' ') accepted finding(s))"
  rm -f "$CURRENT_FINDINGS_FILE"
  exit 0
fi

NEW_FINDINGS=0
if [[ -s "$CURRENT_FINDINGS_FILE" ]]; then
  BASELINE_KEYS="$(mktemp)"
  if [[ -f "$BASELINE_FILE" ]]; then
    jqr '.accepted[]?' <"$BASELINE_FILE" | sort -u > "$BASELINE_KEYS" || : > "$BASELINE_KEYS"
  else
    : > "$BASELINE_KEYS"
  fi
  NEW_KEYS="$(mktemp)"
  comm -23 <(finding_keys "$CURRENT_FINDINGS_FILE") "$BASELINE_KEYS" > "$NEW_KEYS"
  NEW_FINDINGS=$(wc -l < "$NEW_KEYS" | tr -d ' ')

  # Findings inside files this change touched always block, baseline or not —
  # otherwise a baseline entry grants permanent amnesty to a file being edited now.
  if [[ -n "$CHANGED_FILES_LIST" && -f "$CHANGED_FILES_LIST" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if grep -qF -- "$f" "$CURRENT_FINDINGS_FILE"; then
        grep -F -- "$f" "$CURRENT_FINDINGS_FILE" | cut -f1,2 >> "$NEW_KEYS"
      fi
    done < "$CHANGED_FILES_LIST"
    NEW_FINDINGS=$(sort -u "$NEW_KEYS" | wc -l | tr -d ' ')
  fi
  rm -f "$BASELINE_KEYS"
  [[ "$MODE_JSON" -eq 0 ]] && [[ "$NEW_FINDINGS" -gt 0 ]] && {
    echo; echo "New since baseline:"; sort -u "$NEW_KEYS" | sed 's/^/  /'
  }
  rm -f "$NEW_KEYS"
fi

# ── Report ──────────────────────────────────────────────────────────────────
if [[ "$MODE_JSON" -eq 1 ]]; then
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "${SUMMARY[@]}" \
      | jq -R -s --argjson t "$TOTAL_FINDINGS" --argjson n "$NEW_FINDINGS" --argjson e "$EXEC_ERRORS" \
          '{totalFindings:$t, newSinceBaseline:$n, execErrors:$e,
            gates: (split("\n") | map(select(length>0) | ltrimstr("  ")))}'
  else
    echo "GATE ERROR — --json requires jq." >&2; exit 2
  fi
  [[ "$EXEC_ERRORS" -gt 0 ]] && exit 2
  [[ "$NEW_FINDINGS" -gt 0 ]] && exit 1
  exit 0
fi

echo "── craft gates ──────────────────────────────────────────"
printf '%s\n' "${SUMMARY[@]}"
echo "─────────────────────────────────────────────────────────"
echo "  total findings: $TOTAL_FINDINGS   new since baseline: $NEW_FINDINGS   exec errors: $EXEC_ERRORS"
[[ -f "$BASELINE_FILE" ]] || echo "  (no baseline recorded — run with --baseline-write to accept current debt)"

rm -f "$CURRENT_FINDINGS_FILE"

# Execution errors outrank findings: an unrun gate is a bigger problem than a
# known one, and must not be reported as "clean".
[[ "$EXEC_ERRORS" -gt 0 ]] && exit 2
[[ "$NEW_FINDINGS" -gt 0 ]] && exit 1
exit 0
