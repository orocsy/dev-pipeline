#!/usr/bin/env bash
# validate-miu-breakdown.sh — mechanical validator for MIU breakdown markdown.
#
# The tech-lead checklist in skills/miu-methodology/SKILL.md is a schema in prose;
# this script makes it executable (assessment: docs/factory-redesign-assessment.md
# §5 MIU-D — the schema-validation idea applied to the tracked markdown the repo
# actually uses, not to new JSON). Zero node dependency, plain bash + awk.
#
# Usage:   tools/validate-miu-breakdown.sh docs/<feature>/<feature>-miu-breakdown.md
# Exit 0:  every MIU carries all 8 mandatory fields + structural rules hold.
# Exit 1:  one or more violations, each listed as "MIU <n>: <what is missing>".
#
# Checks (source of truth: skills/miu-methodology/SKILL.md "Technical MIU Output
# Format" + "Required fields checklist"):
#   1. The 8 mandatory fields per MIU:
#        Block / Files / Type / Depends on / What it does /
#        Build-Deploy-Runtime impact / Test plan / Done when
#   2. Files: 1–3 paths, never more. Bullets are split on commas when counting,
#      so "- a.ts, b.ts" is 2 paths — packing 4 paths into one bullet cannot
#      dodge the cap.
#   3. Block is EXACTLY one of BACKEND | FRONTEND | INFRASTRUCTURE | INTEGRATION
#      | TESTING (whole trimmed value — composites like "BACKEND + FRONTEND" and
#      annotated forms like "BACKEND (api)" are rejected; pick ONE block).
#   4. Type is one of new-file | modify-existing | new-test | refactor
#   5. "What it does" and "Test plan" are non-empty
#   6. "Build/Deploy/Runtime impact" is non-empty ("none" is valid but must be STATED)
#   7. "Done when" has >= 2 criteria
#   8. Depends form a DAG: referenced MIUs exist, no self-deps, no forward refs
#      (an MIU may only depend on a LOWER-numbered MIU). The "none" shortcut is
#      honored ONLY when the field is exactly none/None after trimming; mixed
#      values like "none, MIU 3" or "none (uses API contract from MIU 4)" still
#      have every "MIU N" reference validated.
#   9. Contract-source rule (MIU-A): an MIU that defines a first-party contract
#      (DTO / shared type / zod schema / API shape) must precede any MIU that
#      references one of its files — a consumer numbered before its contract fails.
#      Matching covers BOTH the contract file's basename AND the primary
#      exported-symbol guess derived from it (kebab/snake segments -> PascalCase,
#      extension stripped, suffix-preserving: create-referral.dto.ts ->
#      CreateReferralDto), so a consumer that names only the symbol is still
#      caught. The symbol heuristic is deliberately conservative: derived only
#      for contract-shaped basenames (.dto/.schema/.types/.contract/.interface
#      segment), only for symbols >= 6 chars, matched on exact word boundaries.
#      Exemption: an earlier MIU that itself lists the file in its own "Files:"
#      is a co-editor/definer of that file (two sequential MIUs legitimately
#      editing the same file in order), NOT a consumer-before-contract.
#
# Input tolerance: CRLF line endings are stripped at read time; bullets may
# start at column 0 (field-label detection runs first, so no collision).

set -u

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "usage: $(basename "$0") <miu-breakdown.md>" >&2
  echo "FAIL: file not found: '${FILE}'" >&2
  exit 1
fi

awk '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function fail(id, msg) { errors[++nerr] = "MIU " id ": " msg }

# symbol_from_base — primary exported-symbol guess for a contract file basename,
# so a consumer that names only the SYMBOL (not the file) is still ordered after
# its contract. kebab/snake/dot segments -> PascalCase, extension stripped,
# suffix-preserving: create-referral.dto.ts -> CreateReferralDto,
# booking.schema.ts -> BookingSchema. Conservative by design (avoids false
# positives on prose): returns "" unless the basename is contract-shaped
# (.dto/.schema/.types/.contract/.interface segment) and the derived symbol is
# >= 6 chars; callers match it on exact word boundaries only.
function symbol_from_base(base,   s, n, parts, i, out) {
  if (base !~ /\.(dto|schemas?|types?|contract|interface)\.[A-Za-z]+$/) return ""
  s = base
  sub(/\.[A-Za-z]+$/, "", s)          # strip extension
  n = split(s, parts, /[-_.]+/)
  out = ""
  for (i = 1; i <= n; i++) {
    if (parts[i] == "") continue
    out = out toupper(substr(parts[i], 1, 1)) substr(parts[i], 2)
  }
  if (length(out) < 6) return ""
  return out
}

function flush_miu() {
  if (cur == "") return
  # 1. presence of the 8 mandatory fields
  split("Block Files Type Depends What Build Test Done", req, " ")
  label["Block"]   = "Block";
  label["Files"]   = "Files";
  label["Type"]    = "Type";
  label["Depends"] = "Depends on";
  label["What"]    = "What it does";
  label["Build"]   = "Build/Deploy/Runtime impact";
  label["Test"]    = "Test plan";
  label["Done"]    = "Done when";
  for (i = 1; i <= 8; i++) {
    f = req[i]
    if (!((cur, f) in seen)) fail(cur, "missing mandatory field \"" label[f] "\"")
  }
  # 2. Files: 1-3 paths (bullets split on commas — "- a.ts, b.ts" is 2 paths,
  #    so comma-packing a single bullet cannot bypass the cap)
  if ((cur SUBSEP "Files") in seen) {
    fv = trim(inline[cur, "Files"])
    nfiles = 0
    if (fv != "") { nfiles = split(fv, tmpf, ",") }
    nbul = bullets[cur, "Files"] + 0
    if (nbul > 0) {
      bc = content[cur, "Files"]
      nbul += gsub(/,/, ",", bc)   # each comma inside a bullet is one more path
    }
    nfiles += nbul
    if (nfiles < 1)      fail(cur, "Files is empty (need 1-3 explicit paths)")
    else if (nfiles > 3) fail(cur, "Files lists " nfiles " paths (max 3 — split the MIU)")
  }
  # 3. Block enum — EXACT match of the whole trimmed value; prefix forms like
  #    "BACKEND + FRONTEND" or "BACKEND (api)" are rejected (one block per MIU)
  if ((cur SUBSEP "Block") in seen) {
    bv = toupper(trim(inline[cur, "Block"]))
    if (bv !~ /^(BACKEND|FRONTEND|INFRASTRUCTURE|INTEGRATION|TESTING)$/)
      fail(cur, "Block \"" trim(inline[cur, "Block"]) "\" is not one of BACKEND|FRONTEND|INFRASTRUCTURE|INTEGRATION|TESTING")
  }
  # 4. Type enum
  if ((cur SUBSEP "Type") in seen) {
    tv = trim(inline[cur, "Type"])
    if (tv !~ /^(new-file|modify-existing|new-test|refactor)([ \t+].*)?$/)
      fail(cur, "Type \"" tv "\" is not one of new-file|modify-existing|new-test|refactor")
  }
  # 5-6. non-empty content fields
  split("What Test Build", ne, " ")
  for (i = 1; i <= 3; i++) {
    f = ne[i]
    if (((cur, f) in seen) && trim(inline[cur, f]) == "" && bullets[cur, f] + 0 == 0)
      fail(cur, "\"" label[f] "\" is empty — state it (for Build/Deploy/Runtime impact, \"none\" is valid but must be written)")
  }
  # 7. Done when >= 2 criteria
  if ((cur SUBSEP "Done") in seen) {
    ndone = bullets[cur, "Done"] + 0
    if (trim(inline[cur, "Done"]) != "") ndone++
    if (ndone < 2) fail(cur, "\"Done when\" has " ndone " criteria (need >= 2 exit criteria)")
  }
  cur = ""
}

BEGIN { nerr = 0; nmiu = 0; cur = ""; curfield = "" }

# CRLF tolerance: strip a trailing \r from every input line so Windows-edited
# breakdowns do not false-fail the Block/Type enum checks (trim() only strips
# space/tab).
{ sub(/\r$/, "") }

# MIU header: "MIU 3: name", "### MIU 3 — name", "**MIU 3: name**", etc.
/^[#> \t*]*MIU[ \t]+[0-9]+/ {
  flush_miu()
  line = $0
  sub(/^[#> \t*]*MIU[ \t]+/, "", line)
  num = line; sub(/[^0-9].*$/, "", num)
  cur = num
  if (cur in header_seen) fail(cur, "duplicate MIU number")
  header_seen[cur] = 1
  order[++nmiu] = cur
  name[cur] = trim(substr(line, length(num) + 1)); sub(/^[:—-][ \t]*/, "", name[cur])
  curfield = ""
  next
}

cur != "" {
  line = $0
  stripped = line
  gsub(/\*\*/, "", stripped)                # tolerate **bold** labels
  # field label detection (case-sensitive on the leading capital, tolerant variants)
  f = ""
  if      (stripped ~ /^[ \t]*(- )?Block[ \t]*:/)                                    f = "Block"
  else if (stripped ~ /^[ \t]*(- )?Files[ \t]*:/)                                    f = "Files"
  else if (stripped ~ /^[ \t]*(- )?Type[ \t]*:/)                                     f = "Type"
  else if (stripped ~ /^[ \t]*(- )?Depends( on)?[ \t]*:/)                            f = "Depends"
  else if (stripped ~ /^[ \t]*(- )?What( it does)?[ \t]*:/)                          f = "What"
  else if (stripped ~ /^[ \t]*(- )?Build\/Deploy(\/Runtime)?( impact)?[ \t]*:/)      f = "Build"
  else if (stripped ~ /^[ \t]*(- )?Test( plan)?[ \t]*(\([^)]*\))?[ \t]*:/)           f = "Test"
  else if (stripped ~ /^[ \t]*(- )?Done( when)?[ \t]*:/)                             f = "Done"
  if (f != "") {
    seen[cur, f] = 1
    curfield = f
    val = stripped
    sub(/^[^:]*:[ \t]*/, "", val)
    inline[cur, f] = trim(val)
    if (f == "What") content[cur, f] = trim(val)   # Depends/Files content comes from bullets only (inline lives in inline[]; storing both double-counts)
    next
  }
  # bullet under the current field (leading indent optional — column-0 bullets
  # are valid; field-label detection above runs first, so no collision)
  if (curfield != "" && stripped ~ /^[ \t]*-[ \t]/) {
    bullets[cur, curfield]++
    b = stripped; sub(/^[ \t]*-[ \t]+/, "", b)
    content[cur, curfield] = content[cur, curfield] " " b
    next
  }
}

END {
  flush_miu()
  if (nmiu == 0) {
    print "FAIL: no MIU definitions found in file (expected lines like \"MIU 1: <technical name>\")"
    exit 1
  }
  # 8. Depends form a DAG (no self / forward / dangling refs)
  for (i = 1; i <= nmiu; i++) {
    m = order[i]
    dv = trim(inline[m, "Depends"] " " content[m, "Depends"])
    # "none" skips validation ONLY when the field is exactly none/None —
    # "none, MIU 3" or "none (uses API contract from MIU 4)" still carries
    # references that must be validated
    if (dv == "" || tolower(dv) == "none") continue
    # collect explicit "MIU N" refs first
    ndep = 0
    rest = dv
    while (match(rest, /MIU[ \t]*[0-9]+/)) {
      ref = substr(rest, RSTART, RLENGTH); sub(/^MIU[ \t]*/, "", ref)
      deplist[++ndep] = ref + 0
      rest = substr(rest, RSTART + RLENGTH)
    }
    # legacy bare-number form ("Depends on: 1, 2") — only when the field has no
    # explicit MIU refs AND no "none" (prose numbers next to "none" would be noise)
    if (ndep == 0 && dv !~ /[Nn]one/) {
      nd = split(dv, toks, /[^0-9]+/)
      for (j = 1; j <= nd; j++) {
        if (toks[j] == "") continue
        deplist[++ndep] = toks[j] + 0
      }
    }
    for (j = 1; j <= ndep; j++) {
      d = deplist[j]
      if (d == m + 0)            fail(m, "depends on itself")
      else if (!(d in header_seen)) fail(m, "depends on MIU " d " which does not exist")
      else if (d > m + 0)        fail(m, "depends on LATER MIU " d " (forward ref — dependencies must point to lower-numbered MIUs; renumber)")
    }
  }
  # 9. Contract-source rule: consumer numbered before its contract MIU
  contract_re = "([Dd][Tt][Oo]|[Ss]chema|zod|shared type|API (shape|contract)|contract)"
  for (i = 1; i <= nmiu; i++) {
    c = order[i]
    if ((name[c] " " content[c, "What"]) !~ contract_re) continue
    nf = split(inline[c, "Files"] " " content[c, "Files"], cf, /[, \t]+/)
    for (k = 1; k <= nf; k++) {
      p = cf[k]
      if (p !~ /\//) continue            # only real paths
      base = p; sub(/^.*\//, "", base)
      if (base == "" || length(base) < 6) continue
      sym = symbol_from_base(base)
      symre = (sym == "") ? "" : "(^|[^A-Za-z0-9_])" sym "($|[^A-Za-z0-9_])"
      for (j = 1; j <= nmiu; j++) {
        e = order[j]
        if (e + 0 >= c + 0) continue     # only EARLIER MIUs can violate
        # co-editor exemption: an earlier MIU that lists the file in its OWN
        # Files: is a co-editor/definer of it (two sequential MIUs editing the
        # same file in the correct order), not a consumer-before-contract
        if (index(inline[e, "Files"] " " content[e, "Files"], base) > 0) continue
        if (index(content[e, "What"], base) > 0)
          fail(e, "consumes contract file " base " defined by LATER MIU " c " (contract-source rule: contracts precede consumers — reorder)")
        # symbol fallback: consumer names only the exported symbol, not the file
        # (word-boundary match; at most ONE violation per earlier-MIU/file pair)
        else if (symre != "" && (content[e, "What"] ~ symre || (inline[e, "Files"] " " content[e, "Files"]) ~ symre))
          fail(e, "consumes contract symbol " sym " (from " base ") defined by LATER MIU " c " (contract-source rule: contracts precede consumers — reorder)")
      }
    }
  }
  if (nerr > 0) {
    print "FAIL: " nerr " violation(s) in " nmiu " MIU(s):"
    for (i = 1; i <= nerr; i++) print "  ✗ " errors[i]
    print ""
    print "Fix the breakdown (see skills/miu-methodology/SKILL.md — Technical MIU Output Format) and re-run."
    exit 1
  }
  print "OK: " nmiu " MIU(s) validated — 8 fields present, Files<=3, Build/Deploy stated, >=2 done-when, DAG clean, contracts precede consumers."
  exit 0
}
' "$FILE"
exit $?
