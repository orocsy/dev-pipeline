---
description: Fetch, integrate, and respond to external reviews from multiple sources (PR bots, design docs) and manage Claude↔Codex turn-taking. Optional/opt-in — NOT part of the default pipeline; auto-invoked ONLY via deliver Phase 9.6 when the project's `.claude/co-review/enabled` flag grants standing consent.
argument-hint: "[channel] [--source=gh-pr-bot|doc] [--watch] [--once] [--respond] [--retrigger]"
---

# Development Pipeline: Co-Review (cross-agent review relay)

You are relaying code/design review between Claude and another agent (typically Codex) across one or more **sources** of different formats. You fetch only what is NEW since a cursor, verify + integrate it, respond back, and hand the turn off — without deadlocking, both-editing-at-once, or looping forever.

This command is **opt-in**. It is never triggered by Rule 1 / Rule 5. There are exactly THREE sanctioned entry paths: (1) the user runs it; (2) the session-start nudge suggests it (see "Opt-in auto-trigger" near the end of this file); (3) **deliver PHASE 9.6 invokes it automatically** when `.claude/co-review/enabled` exists — that flag is the project's standing consent, so the handoff is NOT a contract violation and must not be skipped as "prohibited". All steps below are pre-approved — run to completion, do not ask for permission.

Reuses (do NOT reinvent): `agents/co-review-adapter.md` (detect/parse), `agents/review-analyzer.md` (live-code verification + re-flag trap), `/dev-pipeline:fix` (Path A fixes), `/dev-pipeline:review` (Path A re-bless), `.claude/review-findings-<sha>.md` table, `hooks/pre-push` (blessing gate).

---

## PHASE 0: Resolve the channel + scaffold state

A **channel** = one review conversation (one PR, or one design-doc ping-pong). Parse the positional args: any token starting with `--` is a flag (per `argument-hint`: `--source=`, `--watch`, `--once`, `--respond`, `--retrigger`), the first non-flag token (if any) is the channel name. Flags are order-independent and can appear with or without an explicit channel (`co-review --watch` and `co-review media-upload --watch` must both work — taking `$1` unconditionally as the channel, with no flag-stripping, would set `CHANNEL="--watch"` for the first form):
```bash
FLAGS=()
CHAN_ARG=""
for a in "$@"; do
  case "$a" in
    --*) FLAGS+=("$a") ;;
    *) [ -z "$CHAN_ARG" ] && CHAN_ARG="$a" ;;
  esac
done
CHANNEL="${CHAN_ARG:-$(ls .claude/co-review/*.json 2>/dev/null | grep -v cursor | head -1 | xargs -n1 basename 2>/dev/null | sed 's/\.json$//')}"
# On the very first run (no channel arg, no existing channel configs) the substitution
# above resolves to an empty string, which would scaffold the undiscoverable dotfile
# ".claude/co-review/.json" — fall back to a real name instead.
CHANNEL="${CHANNEL:-default}"
CFG=".claude/co-review/${CHANNEL}.json"
CUR=".claude/co-review/${CHANNEL}.cursor.json"
mkdir -p ".claude/co-review/${CHANNEL}"
```

**First run in a project** (no `.claude/co-review/PROTOCOL.md`): scaffold the shared protocol so the OTHER agent (Codex) can follow the same conventions out-of-band. Write it verbatim:

```bash
if [ ! -f .claude/co-review/PROTOCOL.md ]; then
cat > .claude/co-review/PROTOCOL.md <<'PROTO'
# Co-Review Protocol (Claude ↔ other agent)

Both agents honor these conventions so a review relay never deadlocks or both-edits-at-once.

## Turn marker (cooperative lock)
- Doc channels carry `<!-- TURN: claude|codex -->` at the top of REVIEW-CYCLE.md.
- You WRITE (findings / acks / doc edits) only when `TURN == you`. When `TURN == other`, you are READ-ONLY (detect + report).
- After writing, flip the marker to the other agent and COMMIT. Git commit atomically transfers the turn.
- On `git pull` divergence: LAST-WRITER RECONCILES by merge. NEVER force-push a co-review doc.

## Round + finding format (in REVIEW-CYCLE.md)
- `## Round N — <agent> — <iso-ts>` opens a round authored by that agent.
- `### [P1|P2|P3] <code|design>: <title> — locator: <file:line | #anchor>` is one finding.
- `> <agent>-ack: <resolution + pointer>` acknowledges a finding as addressed.
- Untagged prose is tolerated but parsed as one coarse finding — prefer the tagged form.

## Cursors
- Each side tracks what it has already seen in its own `<channel>.cursor.json` (never shared/edited by the other).
- Newness is cursor-gated ONLY (timestamp for PR bots, doc commit SHA for docs). Re-anchored/re-flagged old items are NOT new.
PROTO
echo "[co-review] scaffolded .claude/co-review/PROTOCOL.md"
fi
```

**First run for this channel** (no `$CFG`): scaffold a config the user can edit, then STOP and ask them to fill in the source(s):

```bash
if [ ! -f "$CFG" ]; then
cat > "$CFG" <<JSON
{
  "channel": "${CHANNEL:-my-channel}",
  "kind": "code",
  "otherAgent": "codex",
  "sources": [
    { "id": "gh-pr-bot", "adapter": "gh-pr-bot", "pr": 0, "botLogin": "chatgpt-codex-connector[bot]", "retrigger": "@codex review" }
  ],
  "convergence": { "maxRounds": 5, "stallThreshold": 5 }
}
JSON
  echo "[co-review] scaffolded $CFG — set the PR number and/or add a doc source, then re-run."
  exit 0
fi
[ -f "$CUR" ] || echo '{"turn":"claude","round":0,"sources":{},"falsePositiveLedger":[],"roundHistory":[]}' > "$CUR"
```

**Cold-start a doc channel's REVIEW-CYCLE.md** — a `doc`-adapter source's `detect()` reads git history *of the doc file*; if the file never existed, there is no history to read, and the channel is permanently stuck reporting "nothing new" no matter what the cursor says. If `sources[]` includes a `doc` adapter and its `path` doesn't exist yet, scaffold it BEFORE detect runs. Default the initial turn to `otherAgent` (from `$CFG`) — Claude is running this because its own side of the work is presumably already done elsewhere (the normal implement/deliver flow); the doc's first move is inviting the other agent to review it, not writing a finding of our own:

```bash
DOCPATH="$(jq -r '.sources[] | select(.adapter=="doc") | .path // empty' "$CFG" 2>/dev/null | head -1)"
OTHER_AGENT="$(jq -r '.otherAgent // "codex"' "$CFG" 2>/dev/null)"
if [ -n "$DOCPATH" ] && [ ! -f "$DOCPATH" ]; then
  mkdir -p "$(dirname "$DOCPATH")"
  cat > "$DOCPATH" <<DOC
# Co-Review: ${CHANNEL}

<!-- TURN: ${OTHER_AGENT} -->

## Round 0 — claude — $(date -u +%Y-%m-%dT%H:%M:%SZ)
### context
Channel opened. See recent commits/PR for the change under review. Waiting on ${OTHER_AGENT} for the first round.
DOC
  git add "$DOCPATH" && git commit -q -m "docs(co-review): open ${CHANNEL} channel" -- "$DOCPATH"
  echo "[co-review] scaffolded $DOCPATH, turn -> ${OTHER_AGENT} — waiting, nothing to integrate yet."
fi
```

Read `turn`, `round`, per-source `cursor`, `falsePositiveLedger`, and `roundHistory` from `$CUR`. Read `sources[]` + `convergence` from `$CFG`. `--source=<id>` narrows to one source.

---

## PHASE 1: Detect (per source, cursor-gated)

For each configured source, spawn the adapter to return only items newer than that source's cursor. Announce:

```
🤖 [dev-pipeline] spawning: co-review-adapter — <source.id> detect (cursor <cursor>)
```

Pass the adapter: the source config, its cursor, and the `falsePositiveLedger`. It returns canonical Findings (see `agents/co-review-adapter.md`) + a `cursorAfter`.

- **Turn guard (doc channels):** `$CUR`'s cached `turn` is only OUR local record of the last handoff — the OTHER agent flips `<!-- TURN -->` in the doc itself (per PROTOCOL.md), not in our cursor file. Re-sync from the live doc BEFORE gating, or a Codex round that already handed the turn back would still look like "not our turn" forever:
  ```bash
  DOCPATH="$(jq -r '.sources[] | select(.adapter=="doc") | .path // empty' "$CFG" 2>/dev/null | head -1)"
  if [ -n "$DOCPATH" ] && [ -f "$DOCPATH" ]; then
    git pull --ff-only 2>/dev/null || true
    LIVE_TURN="$(grep -oE '<!-- TURN: [a-z]+ -->' "$DOCPATH" | grep -oE '[a-z]+' | tail -1)"
    [ -n "$LIVE_TURN" ] && jq --arg t "$LIVE_TURN" '.turn = $t' "$CUR" > "${CUR}.tmp" && mv "${CUR}.tmp" "$CUR"
  fi
  ```
  THEN: if `turn != "claude"`, run detect **report-only** — do NOT write acks/edits/flip. You may report "waiting on <otherAgent>".
- If **nothing new** across all sources → append one `coreview.detect` event with `new:0`, print "Nothing to integrate; turn=<turn>", and exit (or, if `--watch`, go to PHASE 5).

For EACH source `$SID` in `$CFG`'s `sources[]` (looping): `$NEW` is the count of Findings that source's adapter just returned; `$ROUND` is `$CUR`'s current `round` value (unchanged until PHASE 4 advances it). Emit one event per source:

```bash
printf '{"event":"coreview.detect","channel":"%s","source":"%s","new":%d,"round":%d,"ts":"%s"}\n' \
  "$CHANNEL" "$SID" "$NEW" "$ROUND" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .claude/agent-events.jsonl
```

---

## PHASE 2: Parse & normalize

Collect Findings from every source. For `gh-pr-bot`, the adapter has already delegated verification to `review-analyzer` (live-code check + re-flag trap). Apply the false-positive ledger (drop suppressed ids). **Partition by `kind`**: `code` → Path A, `design` → Path B. Dedupe across sources by `locator` (mark `flaggedBy:[...]`).

---

## PHASE 3: Integrate (branch on `kind`)

### PATH A — `kind: code`  (the gh-pr-bot / code path)
1. Render code Findings into `.claude/review-findings-$(git rev-parse --short HEAD).md` using the EXISTING columns `| # | Severity | File:Line | Reviewer | Issue | Proposed Fix |`.
2. Invoke **`/dev-pipeline:fix`** with that findings file as context (one-at-a-time fix → validator agent → loop). Do not hand-roll fixing.
3. Re-bless: invoke **`/dev-pipeline:review`** on the new HEAD (writes `.claude/.last-reviewed-sha`).
4. `git push` (the pre-push hook enforces the blessing). On push failure (e.g. the SSH-over-443 quirk), retry ONCE, then surface to the user — never loop.

### PATH B — `kind: design`  (the media-upload / doc path)
1. For each design Finding, edit the **design artifact** it references (the design doc / section), NOT source code.
2. **No tsc / test / bless / pre-push gate** — there is no code to type-check. (Guard: if a design round's edits touch real source files, kick those to Path A.)
3. Commit the design doc + REVIEW-CYCLE.md edits with a `docs(co-review):` message.

```bash
printf '{"event":"coreview.integrate","channel":"%s","findings":%d,"kind":"%s","resolved":%d,"round":%d,"ts":"%s"}\n' \
  "$CHANNEL" "$N" "$KIND" "$RESOLVED" "$ROUND" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .claude/agent-events.jsonl
```

---

## PHASE 4: Respond & hand off

1. **respond()** per resolved finding via its adapter: PR-thread ack (`gh pr review --comment`) for gh-pr-bot; `> claude-ack:` line for doc. List anything intentionally skipped (nits / wontfix) explicitly so the other agent sees it was seen.
2. **Flip the turn** to the other agent (doc channel: flip `<!-- TURN -->` and commit). Advance each source's cursor in `$CUR` to its `cursorAfter`. Add any confirmed false positives to `falsePositiveLedger`.
3. **Append this round to `roundHistory`** — `{round, findingsCount, resolvedIds}` — BEFORE incrementing `round`. This is the persisted record PHASE 5's convergence checks read; without it "trending up" and "a resolved finding reappearing" have no data to compare against:
   ```jsonc
   // .claude/co-review/<channel>.cursor.json — roundHistory grows by one entry per round:
   { "round": 4, "findingsCount": 6, "resolvedIds": ["gh-pr-bot:pr12:c889123", "..."] }
   ```
4. **retrigger()** if `--retrigger` (or config default): post `@codex review` (gh-pr-bot) / handoff signal (doc).

```bash
printf '{"event":"coreview.handoff","channel":"%s","from":"claude","to":"%s","round":%d,"ts":"%s"}\n' \
  "$CHANNEL" "$OTHER" "$ROUND" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .claude/agent-events.jsonl
```

If not `--watch`, print OUTPUT and stop (the turn is now the other agent's).

---

## PHASE 5: Watch (only with `--watch`) — with the convergence safeguard

`--watch` loops PHASE 1→4 on an interval until the turn returns to the other agent OR convergence. **Before every loop continuation**, evaluate stop conditions against `$CUR`'s `roundHistory` array (PHASE 4 appends one entry per round — the check below is a mechanical read of that array, not a narrated impression):

```bash
# roundHistory: [{round, findingsCount, resolvedIds}, ...] — one entry per completed round.
HIST_LEN="$(jq '.roundHistory | length' "$CUR" 2>/dev/null)"
TRENDING_UP=0
if [ "${HIST_LEN:-0}" -ge 2 ]; then
  # Guard: with <2 rounds of history there's nothing to trend against — without this,
  # round 1 compares against a PREV_N default of 0 and always looks "trending up".
  LAST_N="$(jq -r '.roundHistory[-1].findingsCount // 0' "$CUR")"
  PREV_N="$(jq -r '.roundHistory[-2].findingsCount // 0' "$CUR")"
  [ "$LAST_N" -gt "$PREV_N" ] 2>/dev/null && TRENDING_UP=1
fi

# THIS_ROUND_NEW_IDS = the finding ids this round's PHASE 2 just parsed (a JSON array).
# REAPPEARED>0 means one of them was already in some PRIOR round's resolvedIds — the bot
# re-flagging something we already fixed, the exact pattern that ran 7 rounds without
# converging. `roundHistory[0:-1]` (all entries EXCEPT the last) — PHASE 4 step 3 already
# appended THIS round's own resolvedIds before PHASE 5 runs, so scanning the full array
# would count a finding resolved in THIS SAME round as "reappeared," stalling after round 1.
REAPPEARED="$(jq --argjson new "$THIS_ROUND_NEW_IDS" '
  ([.roundHistory[0:-1][].resolvedIds[]] | unique) as $everResolved
  | [$new[] | select(. as $id | $everResolved | index($id) != null)] | length
' "$CUR" 2>/dev/null)"
```

- **Converged** — a round produced **0 open findings** → emit `coreview.converged` (`reason:"zero-open"`), stop, report success.
- **Round cap** — `round >= convergence.maxRounds` (default 5) → stop, "did not converge in N rounds."
- **Stall / non-convergence** — a round still yields `>= stallThreshold` findings, OR `REAPPEARED > 0` (a finding id from THIS round appears in some prior round's `resolvedIds`/false-positive ledger), OR `TRENDING_UP` (this round's `findingsCount` exceeds the previous round's) → emit `coreview.stalled`, **STOP**, and surface a diagnostic + hand back to the user (the `Findings/round: 6 → 5 → 5 → 6 → 7` trail below is read directly off `roundHistory[].findingsCount`):
  ```
  🛑 CO-REVIEW STALLED — channel <channel>, round <n>
     Findings/round: 6 → 5 → 5 → 6 → 7  (not converging)
     Repeated false positives: <n>  (e.g. "os.getenv already covered")
     Auto-loop stopped to avoid a runaway relay. Handing back to you.
  ```
- **False-positive ledger** — anything the user / `review-analyzer` marks `false-positive` is remembered in `$CUR` and suppressed on re-detect, so re-flags don't restart the cycle.

Default `--watch` = an in-session bounded poller (`until`-loop + sleep, max `maxRounds` ticks), surfacing every round. `--watch=cron` (opt-in) instead creates a `mcp__scheduled-tasks__create_scheduled_task` with a self-contained prompt that re-invokes `/dev-pipeline:co-review <channel> --once` on a cron (prefers `gh-pr-bot`/`git-doc` sources — Notion auth is absent in cron).

```bash
printf '{"event":"coreview.converged","channel":"%s","rounds":%d,"reason":"zero-open","ts":"%s"}\n' \
  "$CHANNEL" "$ROUND" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .claude/agent-events.jsonl
# or, on stall:
printf '{"event":"coreview.stalled","channel":"%s","round":%d,"reason":"%s","ts":"%s"}\n' \
  "$CHANNEL" "$ROUND" "$STALL_REASON" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .claude/agent-events.jsonl
```

---

## OUTPUT

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🤝 CO-REVIEW: <channel>  (round <R>)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Detected:  <N> new  (sources: <ids>)
Resolved:  <M> code / <K> design   Skipped: <S> (nits/wontfix)
Acked:     <sources acked>
Turn →     <agent>          Cursor advanced.
State:     [waiting | converged | stalled | integrated]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Opt-in auto-trigger (session-start nudge)

Enable per-project with `touch .claude/co-review/enabled`. When present, the plugin SessionStart hook (`hooks/session-start.sh`, registered via `hooks/hooks.json`) runs a lightweight cursor-compare per channel (one `gh api` or one `git log` call) and, on new input, prints a **CO-REVIEW PENDING** directive (mirroring the AUTO-REVIEW DIRECTIVE pattern). It only *surfaces a suggestion* — you still run this command. It is NOT wired into Rule 1/Rule 5 auto-invoke.

**Why this command carries no `disable-model-invocation`, unlike other side-effect commands (`deploy`, `setup-machine`)**: `--watch=cron` (below) self-schedules a re-invocation of this very command via `mcp__scheduled-tasks__create_scheduled_task`. Claude Code's scheduled-task execution treats a scheduled prompt's slash-command text as subject to the SAME model-invocation gating as an in-session call — so `disable-model-invocation: true` would silently turn the cron job's prompt into inert plain text, breaking the feature outright (this was tried and reverted — see CHANGELOG). Rule 21's "never auto-invoke" is already satisfied structurally without the flag: this command is absent from Rule 1's routing table and Rule 5's auto-resume, so nothing routes here without the user explicitly running it, explicitly opting into `--watch=cron`, or having granted the standing `.claude/co-review/enabled` consent that deliver Phase 9.6 honors. The flag would add no real safety here, only break a legitimate opt-in automation.

## State & config files (per project, git-tracked)
- `.claude/co-review/PROTOCOL.md` — the cross-agent convention (scaffolded above; read by both agents).
- `.claude/co-review/<channel>.json` — sources + convergence config.
- `.claude/co-review/<channel>.cursor.json` — `{turn, round, sources:{<id>:{cursor}}, falsePositiveLedger:[], roundHistory:[{round,findingsCount,resolvedIds}]}`. `roundHistory` is what PHASE 5's convergence checks (trending-up, reappeared-after-resolved) actually read — it is not optional bookkeeping.
- `.claude/co-review/<channel>/REVIEW-CYCLE.md` — the git-doc transport artifact (doc channels); auto-scaffolded by PHASE 0 on first run if a `doc` source is configured and the file doesn't exist yet.
- Events appended to `.claude/agent-events.jsonl`: `coreview.detect|integrate|handoff|converged|stalled`.
