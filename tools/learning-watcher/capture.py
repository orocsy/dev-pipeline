#!/usr/bin/env python3
"""learning-watcher capture -- incremental transcript -> journal, zero LLM tokens.

Reads NEW lines of every Claude Code transcript (~/.claude/projects/*/*.jsonl)
since a stored byte cursor, extracts what happened, redacts it, and appends one
entry per session burst to a central journal under ~/.claude/learning/.

* Incremental: a per-file byte cursor (plus inode) in state/cursors.json.
* Idempotent: entry IDs are W-<session8>-<start offset>; IDs already present
  in events/*.jsonl are never written twice, so a crash between writing the
  journal and saving the cursor cannot duplicate entries.
* Bounded: at most --max-bytes of transcript are read per run; a file whose
  session is still active is left for a later run (--idle-minutes) unless it
  has piled up --flush-bytes, so entries land per work burst.
* Safe: every excerpt goes through redact.redact() before it is written.
  The journal lives outside every git repo and is never committed.

Run by launchd every 15 minutes (see README). Safe to run by hand.
"""
from __future__ import annotations

import argparse
import fcntl
import glob
import json
import os
import re
import sys
import time
from collections import Counter
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import redact  # noqa: E402

HOME = os.path.expanduser("~")
LW_HOME = os.environ.get("LW_HOME", os.path.join(HOME, ".claude", "learning"))
PROJECTS_DIR = os.environ.get("LW_PROJECTS_DIR", os.path.join(HOME, ".claude", "projects"))

KEEP_TYPES = {b"user", b"assistant", b"system", b"attachment"}

# --------------------------------------------------------------------------
# Signal patterns
# --------------------------------------------------------------------------
CORRECTION_START = re.compile(
    r"^\s*(?:no\b|nope\b|wrong\b|stop\b|wait\b|hold on\b|undo\b|revert\b|actually\b|instead\b|"
    r"don'?t\b|do not\b|why\b|not that\b|not like that\b)", re.IGNORECASE)
CORRECTION_ANY = re.compile(
    r"(?:that'?s not\b|not what i\b|you didn'?t\b|you forgot\b|you missed\b|you broke\b|"
    r"i (?:said|asked|told you|meant)\b|still (?:not|broken|wrong|failing|doesn'?t)\b|"
    r"(?:doesn'?t|does not|didn'?t|did not) work\b|not working\b|is broken\b|wrong again\b|"
    r"why (?:did|do|are|is|would|didn'?t) (?:you|i|we|it)\b|should(?:n'?t)? have\b|too (?:much|many|long)\b|"
    r"不对|不是这|错了|为什么|怎么还|不要|别再|还是不行|没用|理解错|两码事|不行|搞错|又错|重来|撤回|回滚|不用做)",
    re.IGNORECASE)
APPROVAL = re.compile(
    r"^\s*(?:yes|yep|yeah|ok(?:ay)?|sure|great|perfect|nice|good|thanks|thank you|lgtm|looks good|"
    r"ship it|merge it|go ahead|do it|continue|done|start|好|好的|可以|行|对|没问题|继续|不错|很好|完美)\b",
    re.IGNORECASE)
PRAISE = re.compile(
    r"\b(?:great|perfect|nice|love it|awesome|excellent|well done|amazing|brilliant)\b|很好|完美|不错|棒|厉害",
    re.IGNORECASE)
INTERRUPT = "[Request interrupted by user"
DENIAL = re.compile(r"doesn't want to proceed|user (?:rejected|denied|declined)|permission (?:to use .* )?(?:was )?denied", re.IGNORECASE)

TEST_LIKE = re.compile(
    r"\b(?:pnpm|npm|yarn|bun)\s+(?:-\S+\s+)*(?:run\s+)?(?:test|build|lint|typecheck|type-check|check|e2e)\b"
    r"|\b(?:pytest|vitest|jest|xcodebuild|tsc|eslint|biome|playwright|mypy|ruff|swiftlint)\b"
    r"|\b(?:cargo|go|swift)\s+(?:test|build|vet)\b|\bmake\s+(?:test|check|build)\b"
    r"|\btests?/\S*\.sh\b|\bbash\s+\S*test\S*\.sh\b")
HEREDOC_BODY = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?(?:\n\1\b|$)", re.S)
QUOTED = re.compile(r"\"(?:[^\"\\]|\\.)*\"|'[^']*'")


def shell_skeleton(cmd: str) -> str:
    """The command with heredoc bodies and quoted strings removed (what actually runs)."""
    return QUOTED.sub("''", HEREDOC_BODY.sub("<<HEREDOC", cmd))
GIT_COMMIT = re.compile(r"\bgit\b(?:\s+-C\s+\S+)?(?:\s+-c\s+\S+)*\s+commit\b")
REVERT = re.compile(r"\bgit\b(?:\s+-C\s+\S+)?\s+(?:revert\b|reset\s+--hard\b|checkout\s+--\s|restore\s+--staged\s+--worktree\b|push\b[^;&|\n]*(?:--force(?:-with-lease)?\b|\s-f\b))")
PR_CREATE = re.compile(r"\bgh\s+pr\s+create\b")
PR_MERGE = re.compile(r"\bgh\s+pr\s+merge\b")
GIT_PUSH = re.compile(r"\bgit\b(?:\s+-C\s+\S+)?\s+push\b")
RECIPE_ANNOUNCE = re.compile(r"(?m)^[\W_]*Recipe:\s*`?([a-z][a-z0-9-]+)`?")
LEGACY_CLASS = re.compile(r"Classified as\s+\**([A-Z][A-Z_]+)")
SEVERITY = re.compile(r"(?m)^[\s>*#\-\d.|]*\**\s*(P[0-3]|CRITICAL|HIGH|MEDIUM)\b")
COMMAND_TAG = re.compile(r"<command-name>/?([\w:.-]+)</command-name>")
PASTE = re.compile(r"<pasted_content[^>]*>.*?(?:</pasted_content>|$)", re.S)
SYSREM = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)

EXT_STACK = {
    ".swift": "swift", ".m": "objc", ".kt": "kotlin", ".java": "java", ".ts": "typescript",
    ".tsx": "react", ".jsx": "react", ".js": "javascript", ".mjs": "javascript", ".py": "python",
    ".go": "go", ".rs": "rust", ".rb": "ruby", ".php": "php", ".sql": "sql", ".prisma": "prisma",
    ".css": "css", ".scss": "css", ".html": "html", ".md": "docs", ".yml": "yaml", ".yaml": "yaml",
    ".sh": "shell", ".plist": "ios", ".xcconfig": "ios", ".storyboard": "ios", ".xcstrings": "ios",
}
PATH_STACK = [
    (re.compile(r"/apps/ios/|\.xcodeproj|\.xcworkspace|Package\.swift|project\.yml$"), "ios"),
    (re.compile(r"(?:UI)?Tests?/[^/]*\.swift$|Tests\.swift$"), "ios-tests"),
    (re.compile(r"/(?:DesignSystem|Components|Theme|Tokens)/[^/]*\.swift$"), "swiftui-design-system"),
    (re.compile(r"\.(?:module|controller|service|guard|dto)\.ts$"), "nestjs"),
    (re.compile(r"next\.config|/app/.*(?:page|layout|route)\.tsx?$"), "nextjs"),
    (re.compile(r"\.github/workflows/"), "ci"),
    (re.compile(r"Dockerfile|docker-compose"), "docker"),
    (re.compile(r"/migrations?/"), "db-migration"),
    (re.compile(r"openapi|\.openapi\.|/contracts?/"), "api-contract"),
]
CMD_STACK = [
    (re.compile(r"\bxcodebuild\b|\bswift\s+(?:test|build|package)\b|\bxcrun\b"), "swift"),
    (re.compile(r"\bxcodebuild\b[^\n]*\btest\b|\bswift\s+test\b"), "ios-tests"),
    (re.compile(r"\bsimctl\b"), "ios-simulator"),
    (re.compile(r"\bxcodegen\b|\baltool\b|\bnotarytool\b|\bxcrun\s+(?:altool|devicectl)\b"), "ios"),
    (re.compile(r"@nestjs|\bnest\s+(?:build|start|g)\b"), "nestjs"),
    (re.compile(r"\bnext\s+(?:build|dev|start)\b"), "nextjs"),
    (re.compile(r"\bprisma\b"), "prisma"),
    (re.compile(r"\bplaywright\b"), "playwright"),
    (re.compile(r"\bvitest\b|\bjest\b"), "js-test"),
    (re.compile(r"\bdocker\b"), "docker"),
    (re.compile(r"\bterraform\b"), "terraform"),
    (re.compile(r"\baws\s+\w"), "aws"),
    (re.compile(r"\bvercel\b"), "vercel"),
    (re.compile(r"\bstripe\s+\w"), "stripe"),
    (re.compile(r"\bpsql\b|\bpg_dump\b"), "postgres"),
    (re.compile(r"\bredis-cli\b"), "redis"),
    (re.compile(r"\bpnpm\b|\bnpm\b|\byarn\b"), "node"),
    (re.compile(r"\bpytest\b|\bpip\b|\buv\s+(?:run|pip|sync)\b"), "python"),
    (re.compile(r"\bcargo\b"), "rust"),
    (re.compile(r"\bgo\s+(?:test|build|run|mod)\b"), "go"),
    (re.compile(r"\bgh\s+\w"), "github"),
]


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def project_of(slug: str) -> str:
    """'<home-slug>-projects-app--claude-worktrees-y' -> 'app'."""
    home_slug = re.sub(r"[/.]", "-", HOME)
    if "scratch-workspaces" in slug:
        return "misc"
    s = slug
    for prefix in (home_slug + "-projects-", home_slug + "-"):
        if s.startswith(prefix):
            s = s[len(prefix):]
            break
    s = s.split("--")[0].strip("-")
    return (s or "misc").lower()


def flatten(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for c in content:
            if isinstance(c, dict):
                if c.get("type") == "text":
                    parts.append(c.get("text", ""))
                elif c.get("type") == "tool_result":
                    parts.append(flatten(c.get("content")))
            elif isinstance(c, str):
                parts.append(c)
        return "\n".join(parts)
    return ""


def first_line(text: str, limit: int = 200) -> str:
    keys = re.compile(r"error|fail|fatal|exception|denied|not found|cannot|can't|refused|invalid|unable|timed? ?out|conflict", re.I)
    lines = [l.strip() for l in text.splitlines()
             if len(l.strip()) > 8 and not re.match(r"^(Exit code \d+|<[^>]+>|remote:\s*)$", l.strip())]
    pick = next((l for l in lines if keys.search(l)), lines[0] if lines else "")
    return pick[:limit]


LEADING_NOISE = re.compile(r"^\s*(?:(?:cd\s+\S+|[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|'[^']*'|\S*)|export\s+\S+|set\s+-\S+)\s*(?:&&|;|\n)\s*)+")


def cmd_summary(cmd: str, limit: int = 120) -> str:
    c = LEADING_NOISE.sub("", cmd.strip())
    c = c.splitlines()[0] if c else ""
    return c[:limit]


def cmd_signature(cmd: str) -> str:
    toks = [t for t in re.split(r"\s+", cmd_summary(cmd)) if t and not t.startswith(("-", "'", '"'))]
    return " ".join(toks[:3])


def commit_subject(cmd: str) -> str:
    g = GIT_COMMIT.search(cmd)
    cmd = cmd[g.start():] if g else cmd
    m = re.search(r"<<-?\s*['\"]?(\w+)['\"]?\s*\n(.*)", cmd, re.S)
    if m:
        for line in m.group(2).splitlines():
            if line.strip():
                return line.strip()
    m = re.search(r"-m\s+([\"'])(.*?)(?:\1|\n)", cmd, re.S)
    if m:
        return m.group(2).strip().splitlines()[0] if m.group(2).strip() else ""
    return "(message from editor or file)"


def stack_from_path(path: str, stack: Counter) -> None:
    _, ext = os.path.splitext(path)
    if ext in EXT_STACK:
        stack[EXT_STACK[ext]] += 1
    for rx, tag in PATH_STACK:
        if rx.search(path):
            stack[tag] += 1


# --------------------------------------------------------------------------
# Per-burst accumulator
# --------------------------------------------------------------------------
class Burst:
    def __init__(self, path: str, start_offset: int, cfg: dict, cutoff: str = ""):
        self.cfg = cfg
        self.cutoff = cutoff
        self.path = path
        self.session = os.path.splitext(os.path.basename(path))[0]
        self.project = project_of(os.path.basename(os.path.dirname(path)))
        self.start_offset = start_offset
        self.branch = ""
        self.first_ts = ""
        self.last_ts = ""
        self.human_turns = 0
        self.approvals = 0
        self.praise: list[str] = []
        self.corrections: list[str] = []
        self.interrupts = 0
        self.denials: list[str] = []
        self.tools: Counter = Counter()
        self.skills: Counter = Counter()
        self.agents: Counter = Counter()
        self.pending: dict[str, tuple] = {}
        self.errors_total = 0
        self.err_sigs: dict[str, list] = {}
        self.reverts: list[str] = []
        self.commits: list[str] = []
        self.prs = 0
        self.merges = 0
        self.pushes = 0
        self.test_fail: Counter = Counter()
        self.green_after_red: list[str] = []
        self.recaps: list[str] = []
        self.recipes: Counter = Counter()
        self.legacy_types: Counter = Counter()
        self.review: Counter = Counter()
        self.stack: Counter = Counter()
        self.compactions = 0

    # -- helpers -------------------------------------------------------------
    def _x(self, text: str, n: int | None = None) -> str:
        return redact.redact(re.sub(r"\s+", " ", text).strip(), n or self.cfg["excerpt_chars"])

    def _push(self, lst: list, item: str) -> None:
        if item and item not in lst and len(lst) < self.cfg["max_items"]:
            lst.append(item)

    # -- record handlers -----------------------------------------------------
    def human(self, text: str) -> None:
        for m in COMMAND_TAG.finditer(text):
            self.skills[m.group(1).lstrip("/")] += 1
        own = SYSREM.sub("", PASTE.sub(" [paste] ", text)).strip()
        if INTERRUPT in own:
            self.interrupts += 1
            return
        if not own or own.startswith("<"):
            return
        self.human_turns += 1
        # Corrections are short and say so up front. Long messages are briefs or
        # instructions; quoted lines (`> ...`) are the assistant's words echoed back.
        said = re.sub(r"<!--.*?-->|@\"[^\"]+\"", " ", own, flags=re.S)
        said = "\n".join(l for l in said.splitlines() if not l.lstrip().startswith(">")).strip()
        head = said[:300]
        if len(said) <= 800 and (CORRECTION_START.search(head) or CORRECTION_ANY.search(head)):
            self._push(self.corrections, self._x(said))
        elif APPROVAL.match(own) and len(own) <= 60:
            self.approvals += 1
            if PRAISE.search(own):
                self._push(self.praise, self._x(own, 80))
        elif PRAISE.search(own) and len(own) <= 120:
            self._push(self.praise, self._x(own, 80))

    def tool_use(self, item: dict) -> None:
        name = item.get("name") or "?"
        inp = item.get("input") or {}
        self.tools[name] += 1
        if name.startswith("mcp__Claude_Code_iOS_Simulator__"):
            self.stack["ios-simulator"] += 1
        kind, summary, extra = "tool", "", ""
        if name == "Skill":
            self.skills[str(inp.get("skill", "?"))] += 1
            summary = str(inp.get("skill", ""))
        elif name in ("Agent", "Task"):
            sub = str(inp.get("subagent_type") or "general-purpose")
            self.agents[sub] += 1
            kind = "agent"
            summary = f"{sub}: {inp.get('description', '')}"
        elif name == "Bash":
            cmd = str(inp.get("command", ""))
            summary = cmd_summary(cmd)
            skel = shell_skeleton(cmd)
            for rx, tag in CMD_STACK:
                if rx.search(skel):
                    self.stack[tag] += 1
            if GIT_COMMIT.search(skel):
                extra = "commit:" + commit_subject(cmd)
            elif PR_CREATE.search(skel):
                extra = "pr-create"
            elif PR_MERGE.search(skel):
                extra = "pr-merge"
            elif GIT_PUSH.search(skel):
                extra = "push"
            rv = REVERT.search(skel)
            if rv:
                self._push(self.reverts, self._x(skel[rv.start():].splitlines()[0], 140))
            if TEST_LIKE.search(skel):
                kind = "test"
        elif name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
            fp = str(inp.get("file_path") or inp.get("notebook_path") or "")
            stack_from_path(fp, self.stack)
            summary = os.path.basename(fp)
        elif name == "mcp__ccd_turn__wrap_up":
            recap = str(inp.get("recap", ""))
            if recap:
                self.recaps.append(self._x(recap, self.cfg["recap_chars"]))
                self.recaps = self.recaps[-3:]
        elif name == "ReportFindings":
            self.review["code-review"] += len(inp.get("findings") or [])
        if item.get("id"):
            self.pending[item["id"]] = (name, summary, kind, extra)

    def tool_result(self, item: dict) -> None:
        name, summary, kind, extra = self.pending.pop(item.get("tool_use_id", ""), ("?", "", "tool", ""))
        text = flatten(item.get("content"))[:6000]
        if item.get("is_error"):
            if DENIAL.search(text):
                self._push(self.denials, self._x(f"{name} {summary}", 140))
                return
            if INTERRUPT in text:
                self.interrupts += 1
                return
            self.errors_total += 1
            sig = redact.redact(f"{name} `{cmd_signature(summary) if name == 'Bash' else summary[:60]}`", 120)
            rec = self.err_sigs.setdefault(sig, [0, self._x(first_line(text), 180)])
            rec[0] += 1
            if kind == "test":
                self.test_fail[cmd_signature(summary)] += 1
            return
        if kind == "test":
            sig = cmd_signature(summary)
            if self.test_fail.get(sig):
                self._push(self.green_after_red, self._x(f"`{summary[:90]}` passed after {self.test_fail[sig]} failure(s)", 160))
                self.test_fail[sig] = 0
        if (extra.startswith("commit:") and not extra.endswith("(message from editor or file)")
                and not re.search(r"nothing to commit|no changes added", text)):
            self._push(self.commits, self._x(extra[7:], 120))
        elif extra == "pr-create":
            self.prs += 1
        elif extra == "pr-merge":
            self.merges += 1
        elif extra == "push":
            self.pushes += 1
        if kind == "agent" and re.search(r"review|audit|verify|check", summary, re.I):
            for m in SEVERITY.finditer(text):
                self.review[m.group(1)] += 1

    def record(self, r: dict) -> None:
        ts = r.get("timestamp") or ""
        if self.cutoff and ts and ts < self.cutoff:
            return
        if r.get("isCompactSummary") or r.get("isVisibleInTranscriptOnly"):
            return
        if ts:
            self.first_ts = self.first_ts or ts
            self.last_ts = ts
        if r.get("gitBranch"):
            self.branch = r["gitBranch"]
        t = r.get("type")
        msg = r.get("message") or {}
        if t == "user":
            content = msg.get("content")
            origin = (r.get("origin") or {}).get("kind")
            is_human = origin == "human" or (origin is None and not r.get("isMeta") and r.get("userType", "external") == "external")
            if isinstance(content, str):
                if is_human:
                    self.human(content)
                elif INTERRUPT in content:
                    self.interrupts += 1
            elif isinstance(content, list):
                texts = []
                for it in content:
                    if not isinstance(it, dict):
                        continue
                    if it.get("type") == "tool_result":
                        self.tool_result(it)
                    elif it.get("type") == "text":
                        texts.append(it.get("text", ""))
                if texts and is_human:
                    self.human("\n".join(texts))
                elif any(INTERRUPT in x for x in texts):
                    self.interrupts += 1
        elif t == "assistant":
            for it in msg.get("content") or []:
                if not isinstance(it, dict):
                    continue
                if it.get("type") == "tool_use":
                    self.tool_use(it)
                elif it.get("type") == "text":
                    txt = it.get("text", "")
                    for m in RECIPE_ANNOUNCE.finditer(txt):
                        self.recipes[m.group(1)] += 1
                    for m in LEGACY_CLASS.finditer(txt):
                        self.legacy_types[m.group(1)] += 1
        elif t == "system" and r.get("subtype") == "compact_boundary":
            self.compactions += 1

    # -- output --------------------------------------------------------------
    def significant(self) -> bool:
        signal = (self.errors_total or self.corrections or self.interrupts or self.denials or self.reverts
                  or self.commits or self.prs or self.recaps or self.green_after_red or sum(self.review.values())
                  or self.recipes or self.praise)
        busy = self.human_turns > 0 or sum(self.tools.values()) >= 3
        return bool(signal and busy)

    @property
    def entry_id(self) -> str:
        return f"W-{self.session[:8]}-{self.start_offset}"

    def to_event(self, recipes_lib) -> dict:
        sigs = sorted(self.err_sigs.items(), key=lambda kv: -kv[1][0])
        inferred = recipes_lib.infer(self.skills, self.agents) if recipes_lib else None
        return {
            "id": self.entry_id,
            "session": self.session,
            "project": self.project,
            "branch": redact.redact(self.branch, 80),
            "start": self.first_ts,
            "end": self.last_ts,
            "captured": now_iso(),
            "human_turns": self.human_turns,
            "tool_calls": sum(self.tools.values()),
            "tools": dict(self.tools.most_common(8)),
            "skills": dict(self.skills.most_common(15)),
            "agents": dict(self.agents.most_common(10)),
            "recipe_announced": dict(self.recipes),
            "legacy_types": dict(self.legacy_types),
            "recipe_inferred": inferred,
            "stack": dict(self.stack.most_common(8)),
            "errors_total": self.errors_total,
            "error_sigs": [[s, n, sample] for s, (n, sample) in sigs[: self.cfg["max_items"]]],
            "corrections": self.corrections,
            "interrupts": self.interrupts,
            "denials": self.denials,
            "reverts": self.reverts,
            "commits": self.commits,
            "prs": self.prs,
            "merges": self.merges,
            "pushes": self.pushes,
            "recaps": self.recaps,
            "green_after_red": self.green_after_red,
            "review_findings": dict(self.review),
            "approvals": self.approvals,
            "praise": self.praise,
            "compactions": self.compactions,
        }


def render_markdown(ev: dict) -> str:
    def fmt_counter(d: dict, sep=" · ") -> str:
        return sep.join(f"{k} ×{v}" if v > 1 else k for k, v in d.items())

    start = (ev["start"] or "")[:16].replace("T", " ")
    end = (ev["end"] or "")[:16].replace("T", " ")
    if end[:10] == start[:10]:
        end = end[11:]
    out = [f"## [{ev['id']}] {start}→{end} UTC · {ev['project']} · {ev['branch'] or '-'}"]
    out.append(f"- turns: {ev['human_turns']} human · {ev['tool_calls']} tool calls"
               + (f" · {ev['compactions']} compaction(s)" if ev["compactions"] else ""))
    rec = ", ".join(ev["recipe_announced"]) or "—"
    out.append(f"- recipe: announced {rec} · inferred {ev['recipe_inferred'] or 'ad-hoc'}")
    used = {**ev["skills"], **{f"agent:{k}": v for k, v in ev["agents"].items()}}
    if used:
        out.append(f"- skills/commands: {fmt_counter(used)}")
    if ev["tools"]:
        out.append(f"- tools: {' · '.join(f'{k} {v}' for k, v in ev['tools'].items())}")
    if ev["stack"]:
        out.append(f"- stack: {', '.join(ev['stack'])}")
    probs = []
    if ev["errors_total"]:
        probs.append(f"{ev['errors_total']} tool error(s)")
        for sig, n, sample in ev["error_sigs"][:5]:
            probs.append(f"  - {sig}{' ×' + str(n) if n > 1 else ''}: \"{sample}\"")
    for c in ev["corrections"]:
        probs.append(f"user correction: \"{c}\"")
    if ev["interrupts"]:
        probs.append(f"interrupted by user ×{ev['interrupts']}")
    for d in ev["denials"]:
        probs.append(f"tool call declined: {d}")
    for r in ev["reverts"]:
        probs.append(f"revert/reset: `{r}`")
    if ev["review_findings"]:
        probs.append(f"review findings: {fmt_counter(ev['review_findings'], ', ')}")
    if probs:
        out.append("- problems:")
        out += [("  " + p if p.startswith("  -") else f"  - {p}") for p in probs]
    wins = []
    for r in ev["recaps"]:
        wins.append(f"recap: \"{r}\"")
    if ev["commits"]:
        wins.append(f"commits ({len(ev['commits'])}): " + "; ".join(f"\"{c}\"" for c in ev["commits"][:5]))
    if ev["prs"] or ev["merges"]:
        wins.append(f"PRs opened {ev['prs']} · merged {ev['merges']}")
    for g in ev["green_after_red"]:
        wins.append(f"green after red: {g}")
    if ev["praise"]:
        wins.append("user praise: " + "; ".join(f"\"{p}\"" for p in ev["praise"]))
    if ev["approvals"]:
        wins.append(f"accepted proposals ×{ev['approvals']}")
    if wins:
        out.append("- wins:")
        out += [f"  - {w}" for w in wins]
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------
# Recipes (for inference only; the router owns selection)
# --------------------------------------------------------------------------
class RecipesLib:
    def __init__(self, path: str):
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        self.order = data.get("infer_order") or [r["id"] for r in data["recipes"]]
        self.match = {r["id"]: [m.lower() for m in r.get("infer_from", [])] for r in data["recipes"]}

    def infer(self, skills: Counter, agents: Counter) -> str | None:
        used = {k.lower() for k in skills} | {f"agent:{k}".lower() for k in agents}
        for rid in self.order:
            for m in self.match.get(rid, []):
                if any(u == m or u.endswith(":" + m) or u.startswith(m) for u in used):
                    return rid
        return None


def find_recipes_file() -> str | None:
    for p in (os.environ.get("LW_RECIPES"), os.path.join(LW_HOME, "bin", "recipes.json"),
              os.path.join(HERE, "..", "..", "recipes", "recipes.json")):
        if p and os.path.isfile(p):
            return p
    return None


# --------------------------------------------------------------------------
# File reading
# --------------------------------------------------------------------------
TS_RX = re.compile(rb'"timestamp":"([0-9T:.\-Z+]+)"')


def seek_to_time(path: str, size: int, cutoff_iso: str) -> int:
    """Binary-search a transcript for the first line at/after cutoff (timestamps ~monotonic)."""
    cutoff = cutoff_iso.encode()
    lo, hi = 0, size
    with open(path, "rb") as fh:
        while hi - lo > 256 * 1024:
            mid = (lo + hi) // 2
            fh.seek(mid)
            fh.readline()
            ts = None
            for _ in range(50):
                line = fh.readline()
                if not line:
                    break
                m = TS_RX.search(line[:4096]) or TS_RX.search(line[-4096:])
                if m:
                    ts = m.group(1)
                    break
            if ts is None or ts >= cutoff:
                hi = mid
            else:
                lo = mid
        if lo:
            fh.seek(lo)
            fh.readline()
            lo = fh.tell()
    return lo


def last_activity(path: str, size: int) -> float | None:
    """Epoch of the newest user/assistant record near the end of the file.

    File mtime is useless as an idle signal: the desktop app keeps appending
    metadata records (titles, latches, frame links) to sessions nobody is using.
    Conversation records are the ones that start with {"parentUuid".
    """
    with open(path, "rb") as fh:
        fh.seek(max(0, size - 512 * 1024))
        tail = fh.read()
    for raw in reversed(tail.split(b"\n")):
        if raw.startswith(b'{"parentUuid"'):
            m = TS_RX.search(raw[:4096]) or TS_RX.search(raw[-4096:])
            if m:
                try:
                    return datetime.fromisoformat(m.group(1).decode().replace("Z", "+00:00")).timestamp()
                except ValueError:
                    return None
    return None


def iter_records(chunk: bytes):
    for line in chunk.split(b"\n"):
        if not line:
            continue
        if line.startswith(b'{"type":"'):
            end = line.find(b'"', 9)
            if line[9:end] not in KEEP_TYPES:
                continue
        try:
            yield json.loads(line)
        except (ValueError, UnicodeDecodeError):
            continue


# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------
def load_json(path: str, default):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (FileNotFoundError, ValueError):
        return default


def save_json(path: str, data) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1, sort_keys=True)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def known_ids(events_dir: str) -> set[str]:
    ids = set()
    for p in sorted(glob.glob(os.path.join(events_dir, "*.jsonl")))[-3:]:
        with open(p, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r'\{"id": ?"([^"]+)"', line)
                if m:
                    ids.add(m.group(1))
    return ids


def journal_header(project: str) -> str:
    return (f"# Learning journal — {project}\n\n"
            "Written by the dev-pipeline learning watcher (`tools/learning-watcher/capture.py`).\n"
            "Local only: never copy into a repo. Excerpts are redacted; consolidation state lives in\n"
            "`state/`, not here. Turn off: see the watcher README.\n\n")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Capture new transcript lines into the learning journal.")
    ap.add_argument("--max-bytes", type=int, default=int(os.environ.get("LW_MAX_BYTES", 160 * 1024 * 1024)))
    ap.add_argument("--backfill-hours", type=float, default=float(os.environ.get("LW_BACKFILL_HOURS", 48)))
    ap.add_argument("--idle-minutes", type=float, default=float(os.environ.get("LW_IDLE_MINUTES", 20)))
    ap.add_argument("--flush-bytes", type=int, default=48 * 1024 * 1024)
    ap.add_argument("--max-defer-hours", type=float, default=float(os.environ.get("LW_MAX_DEFER_HOURS", 2)),
                    help="capture a never-idle session at least this often")
    ap.add_argument("--include-subagents", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="print entries, write nothing")
    a = ap.parse_args(argv)

    if os.path.exists(os.path.join(LW_HOME, "PAUSED")):
        return 0
    cfg = {"excerpt_chars": 200, "recap_chars": 360, "max_items": 8}
    for d in ("state", "journal", "events", "logs"):
        os.makedirs(os.path.join(LW_HOME, d), exist_ok=True)
    lock = open(os.path.join(LW_HOME, "state", "capture.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return 0

    started = time.time()
    cursors_path = os.path.join(LW_HOME, "state", "cursors.json")
    cursors = load_json(cursors_path, {})
    rpath = find_recipes_file()
    recipes_lib = RecipesLib(rpath) if rpath else None
    pattern = os.path.join(PROJECTS_DIR, "*", "*.jsonl")
    files = glob.glob(pattern)
    if a.include_subagents:
        files += glob.glob(os.path.join(PROJECTS_DIR, "*", "*", "subagents", "*.jsonl"))
    files.sort(key=lambda p: os.path.getmtime(p))
    now = time.time()
    cutoff_iso = datetime.fromtimestamp(now - a.backfill_hours * 3600, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    budget = a.max_bytes
    bursts: list[Burst] = []
    new_cursors = dict(cursors)
    read_total = 0
    deferred = 0

    for path in files:
        if budget <= 0:
            break
        try:
            st = os.stat(path)
        except FileNotFoundError:
            continue
        cur = cursors.get(path)
        if cur is None:
            if st.st_mtime < now - a.backfill_hours * 3600:
                new_cursors[path] = {"ino": st.st_ino, "offset": st.st_size}
                continue
            offset = seek_to_time(path, st.st_size, cutoff_iso)
        elif cur.get("ino") != st.st_ino or st.st_size < cur.get("offset", 0):
            offset = 0
        else:
            offset = cur["offset"]
        pending = st.st_size - offset
        if pending <= 0:
            continue
        active_at = last_activity(path, st.st_size) if now - st.st_mtime < a.idle_minutes * 60 else None
        idle = active_at is None or now - active_at >= a.idle_minutes * 60
        since = (cur or {}).get("deferred_since", now)
        if not idle and pending < a.flush_bytes and now - since < a.max_defer_hours * 3600:
            deferred += 1
            new_cursors[path] = {"ino": st.st_ino, "offset": offset, "deferred_since": since}
            continue
        with open(path, "rb") as fh:
            fh.seek(offset)
            data = fh.read(min(pending, budget))
            end = data.rfind(b"\n")
            if end < 0:
                if len(data) < pending:  # one line bigger than the budget: finish it
                    data += fh.readline()
                    end = data.rfind(b"\n")
                if end < 0:
                    continue  # partial line still being written
        chunk = data[: end + 1]
        budget -= len(chunk)
        read_total += len(chunk)
        b = Burst(path, offset, cfg, cutoff=cutoff_iso if cur is None else "")
        for rec in iter_records(chunk):
            if rec.get("isSidechain") and not a.include_subagents:
                continue
            b.record(rec)
        if b.significant():
            bursts.append(b)
        new_cursors[path] = {"ino": st.st_ino, "offset": offset + len(chunk)}

    # prune cursors of deleted files
    new_cursors = {p: c for p, c in new_cursors.items() if os.path.exists(p)}

    events_dir = os.path.join(LW_HOME, "events")
    seen = known_ids(events_dir)
    written = 0
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    for b in bursts:
        if b.entry_id in seen:
            continue
        ev = b.to_event(recipes_lib)
        md = render_markdown(ev)
        if a.dry_run:
            print(md)
            continue
        jpath = os.path.join(LW_HOME, "journal", f"{ev['project']}.md")
        new_file = not os.path.exists(jpath)
        with open(jpath, "a", encoding="utf-8") as fh:
            if new_file:
                fh.write(journal_header(ev["project"]))
            fh.write(md + "\n")
        with open(os.path.join(events_dir, f"{month}.jsonl"), "a", encoding="utf-8") as fh:
            fh.write(json.dumps(ev, ensure_ascii=False) + "\n")
            fh.flush()
            os.fsync(fh.fileno())
        seen.add(b.entry_id)
        written += 1

    if not a.dry_run:
        save_json(cursors_path, new_cursors)
        with open(os.path.join(LW_HOME, "logs", "capture.log"), "a", encoding="utf-8") as fh:
            fh.write(f"{now_iso()} read={read_total // 1024}KiB files={len(files)} bursts={len(bursts)} "
                     f"written={written} deferred_active={deferred} secs={time.time() - started:.1f}\n")
    else:
        print(f"[dry-run] read={read_total // 1024}KiB bursts={len(bursts)} deferred_active={deferred}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
