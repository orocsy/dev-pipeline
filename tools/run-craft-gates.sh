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
    --changed-files)  CHANGED_FILES_LIST="${2:-}"; shift 2 ;;
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
  for d in tests test e2e __tests__ spec; do [[ -d "$d" ]] && { echo "$d"; return; }; done
  echo ""   # empty → the skip-policy gate reports NOT APPLICABLE and exits 0
}

# The pipeline-causality gate's built-in default is the bare command `test`, which its
# (correctly) anchored matcher will never find inside `pnpm test` / `npm test`. Left to
# the default it reported two false positives on a correctly-chained pipeline — a gate
# that cries wolf gets switched off. Derive the real proof command from the repo's own
# package manager and synthesise the config when the repo has not pinned one.
detect_proof_steps() {
  local cfg
  cfg=$([[ -f "$CONFIG_FILE" ]] && jqr '.proofSteps // [] | join(" ")' <"$CONFIG_FILE")
  if [[ -n "${cfg:-}" ]]; then printf '%s' "$cfg"; return; fi
  local pm="npm"
  [[ -f pnpm-lock.yaml ]] && pm="pnpm"
  [[ -f yarn.lock ]] && pm="yarn"
  [[ -f bun.lockb ]] && pm="bun"
  printf '%s test' "$pm"
}

SRC_DIRS="$(detect_src_dirs)"
TEST_DIR="$(detect_test_dir)"

# Synthesise a pipeline config from the detected proof command when the repo has none,
# so the gate is exercised with a command that actually exists here.
PIPELINE_CFG="$GATE_STATE_DIR/pipeline.json"
if [[ ! -f "$PIPELINE_CFG" ]]; then
  PIPELINE_CFG="$(mktemp)"
  printf '{"proofSteps":["%s"]}\n' "$(detect_proof_steps)" > "$PIPELINE_CFG"
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
    async-child-busy-contract) echo "--dir ${SRC_DIRS%%,*}" ;;
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
      if printf '%s\n' "$out" | grep -q '^NOT APPLICABLE'; then
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
finding_keys() { cut -f1,2 -d$'\t' "$1" | sed 's/[[:space:]]*$//' | sort -u; }

if [[ "$MODE_BASELINE_WRITE" -eq 1 ]]; then
  {
    echo "{"
    echo "  \"recordedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"sha\": \"$(git rev-parse HEAD 2>/dev/null || echo unknown)\","
    echo "  \"accepted\": ["
    finding_keys "$CURRENT_FINDINGS_FILE" | sed 's/"/\\"/g' | awk '{printf "%s    \"%s\"", (NR>1?",\n":""), $0} END{if(NR)print ""}'
    echo "  ]"
    echo "}"
  } > "$BASELINE_FILE"
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
