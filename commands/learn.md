---
description: Capture learnings and knowledge from a development session for future reference
---

# Development Pipeline: Learn Phase

You are capturing knowledge from a completed development session for continuous improvement.

---

## Knowledge Capture

Invoke `@self-improvement` to activate the learning capture system.

### Step 1: Review the Session

Analyze the current session for:
- **Corrections** — mistakes made and how they were fixed
- **Knowledge gaps** — things that required research or multiple attempts
- **Best practices discovered** — patterns that worked well
- **Command failures** — tools or commands that failed and root causes
- **Debugging insights** — non-obvious root causes that were hard to find

### Step 2: Log Learnings

For each finding, log to `.learnings/` directory:
- `LEARNINGS.md` — corrections, knowledge gaps, best practices
- `ERRORS.md` — command failures and exceptions
- `FEATURE_REQUESTS.md` — user-requested capabilities or improvements

Each entry uses structured format:
- Unique ID (LRN/ERR/FEAT + date)
- Priority level (critical → low)
- Pattern-Key for recurrence tracking
- Status tracking (new → acknowledged → resolved)

### Step 3: Check for Promotions

Review existing learnings for patterns that recur (≥3 occurrences in 30 days):
- Promote to CLAUDE.md as a permanent rule
- Promote to a skill rule file if domain-specific
- Promote to AGENTS.md if it affects agent behavior

---

## OUTPUT

Present learning summary:
- New learnings captured (count + highlights)
- Errors logged (count)
- Promotions triggered (if any)
- Patterns approaching promotion threshold

Tell the user: "Learnings captured. These will inform future sessions."
