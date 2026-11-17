"""Redaction shared by the learning watcher.

Two tiers:

* ``redact(text)`` -- tier 1. Runs on every excerpt BEFORE it is written to the
  local journal under ``~/.claude/learning``. Removes secrets, credentials,
  emails, phone numbers, prices, IP addresses, payment-provider object IDs,
  home-directory user names and every term in the ``[always]`` section of
  ``private-terms.txt``. The journal never leaves this machine, but it is
  still written redacted so a copy-paste into a repo cannot leak a key.

* ``findings(text, public=...)`` -- tier 2, used by ``privacy_lint.py`` as a
  hard gate on anything bound for git. Reports (does not rewrite) every tier-1
  hit plus all private terms (both sections), unknown domains, absolute user
  paths, bundle identifiers and common given names; with ``public=True`` it
  also blocks CJK text (business conversations are mostly in Chinese and
  cannot be screened for names).

Standard library only, so it runs under launchd without a virtualenv.
"""

from __future__ import annotations

import os
import re
from typing import Iterable

HOME = os.path.expanduser("~")
LEARNING_HOME = os.environ.get("LW_HOME", os.path.join(HOME, ".claude", "learning"))
PRIVATE_TERMS_FILE = os.environ.get(
    "LW_PRIVATE_TERMS", os.path.join(LEARNING_HOME, "private-terms.txt")
)
HERE = os.path.dirname(os.path.abspath(__file__))

# --------------------------------------------------------------------------
# Tier-1 patterns: (name, compiled regex, replacement)
# Order matters: specific credential shapes before generic ones.
# --------------------------------------------------------------------------
_T1: list[tuple[str, re.Pattern, str]] = [
    ("private-key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)"), "<private-key>"),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{6,}"), "<jwt>"),
    ("anthropic-openai-key", re.compile(r"\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{16,}"), "<api-key>"),
    ("stripe-key", re.compile(r"\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{8,}"), "<api-key>"),
    ("stripe-webhook-secret", re.compile(r"\bwhsec_[A-Za-z0-9]{8,}"), "<api-key>"),
    ("stripe-object-id", re.compile(r"\b(?:acct|cus|pi|pm|price|prod|sub|in|ch|evt|seti|cs|tok|src|txn|po|tr|re|ii|il|si|card|ba)_[A-Za-z0-9]{10,}\b"), "<provider-id>"),
    ("resend-key", re.compile(r"\bre_[A-Za-z0-9]{8,}_[A-Za-z0-9]{8,}"), "<api-key>"),
    ("github-token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"), "<api-key>"),
    ("slack-token", re.compile(r"\bxox[abposr]-[A-Za-z0-9-]{10,}"), "<api-key>"),
    ("aws-access-key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"), "<api-key>"),
    ("google-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"), "<api-key>"),
    ("google-oauth", re.compile(r"\bya29\.[0-9A-Za-z_-]{20,}"), "<api-key>"),
    ("gitlab-token", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}"), "<api-key>"),
    ("npm-token", re.compile(r"\bnpm_[A-Za-z0-9]{30,}"), "<api-key>"),
    ("sendgrid-key", re.compile(r"\bSG\.[\w-]{16,}\.[\w-]{16,}"), "<api-key>"),
    ("cloudflare-tunnel-token", re.compile(r"\beyJh[A-Za-z0-9+/=]{40,}"), "<api-key>"),
    ("bearer", re.compile(r"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{12,}"), r"\1 <token>"),
    ("url-credentials", re.compile(r"(?i)\b([a-z][a-z0-9+.-]*://)(?!(?:user|username|USER):(?:pass|password|PASSWORD|secret)@)[^\s/@:<$]+:[^\s/@<$]+@"), r"\1<cred>@"),
    # KEY=value / "key": "value" / --body value, where the value looks like a
    # credential (8+ chars with a letter AND a digit). Prose such as
    # "password reset" and code such as `token: string` stay untouched.
    ("secret-assignment", re.compile(
        r"(?i)\b([A-Z0-9_.-]*(?:secret|token|passw(?:or)?d|pwd|api[_-]?key|private[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?key|signing[_-]?key|dsn)[A-Z0-9_.-]*)"
        r"(['\"]?\s*[=:]\s*|\s+--body\s+)(['\"]?)(?=[A-Za-z0-9_\-./+=]*\d)(?=[A-Za-z0-9_\-./+=]*[A-Za-z])([A-Za-z0-9_\-./+=]{8,})"), r"\1\2\3<redacted>"),
    ("secret-query", re.compile(r"(?i)([?&](?:token|key|secret|code|sig|signature|password|auth|access_token|api_key)=)(?=[^&\s\"'<>]*\d)[^&\s\"'<>]{6,}"), r"\1<redacted>"),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"), "<email>"),
    ("phone", re.compile(r"(?<![\w.])(?:\+\d{1,3}[\s-]?\(?\d{1,4}\)?[\s-]?\d{3,4}[\s-]?\d{3,4}|\b04\d{2}[\s-]?\d{3}[\s-]?\d{3})\b"), "<phone>"),
    ("price", re.compile(
        r"(?i)(?:\b(?:A|AU|US|NZ|C|HK|S)\$\s?\d[\d,]*(?:\.\d{1,2})?"
        r"|[€£¥￥]\s?\d[\d,]*(?:\.\d{1,2})?"
        r"|\$\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\$\d+\.\d{2}\b|\$\d{2,}\b"
        r"|\b\d[\d,]*(?:\.\d{1,2})?\s?(?:AUD|USD|EUR|GBP|CNY|RMB|NZD)\b"
        r"|\d[\d,]*(?:\.\d{1,2})?\s?(?:元|块钱|块))"), "<price>"),
    ("ipv4", re.compile(r"\b(?!127\.0\.0\.1\b)(?!0\.0\.0\.0\b)(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}\b"), "<ip>"),
    ("scratchpad", re.compile(r"/(?:private/)?tmp/claude-\d+/[^\s\"'`]*?/scratchpad"), "<scratchpad>"),
    ("session-dir", re.compile(r"/(?:private/)?tmp/claude-\d+/[^\s/\"'`]+(?:/[0-9a-f-]{36})?"), "<tmp-session>"),
    ("home-path", re.compile(r"/(?:Users|home)/[^/\s\"'`]+"), "~"),
    ("home-slug", re.compile(r"-(?:Users|home)-[A-Za-z0-9_]+-"), "-~-"),
    # Long mixed-case alphanumerics: unlabeled keys. Lowercase hex (git SHAs,
    # UUIDs) is deliberately left alone -- it is needed for citations.
    ("high-entropy", re.compile(r"\b(?=[A-Za-z0-9+_-]{32,}\b)(?=[A-Za-z0-9+_-]*[A-Z])(?=[A-Za-z0-9+_-]*[a-z])(?=[A-Za-z0-9+_-]*\d)[A-Za-z0-9+_-]{32,}\b"), "<token>"),
]

# --------------------------------------------------------------------------
# Private terms (local file, never committed)
# --------------------------------------------------------------------------

def load_private_terms(path: str = PRIVATE_TERMS_FILE) -> dict[str, list[str]]:
    """Parse private-terms.txt: sections ``[always]`` and ``[git-only]``.

    Lines before any section header count as ``always``. Blank lines and
    ``#`` comments are ignored.
    """
    terms: dict[str, list[str]] = {"always": [], "git-only": []}
    try:
        with open(path, encoding="utf-8") as fh:
            section = "always"
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    section = line[1:-1].strip().lower()
                    terms.setdefault(section, [])
                    continue
                terms.setdefault(section, []).append(line)
    except FileNotFoundError:
        pass
    return terms


def _term_regex(term: str) -> re.Pattern:
    # Whole-word where the term starts/ends with a word char; CJK terms match anywhere.
    left = r"(?<![\w])" if re.match(r"\w", term[0]) and term[0].isascii() else ""
    right = r"(?![\w])" if re.match(r"\w", term[-1]) and term[-1].isascii() else ""
    return re.compile(left + re.escape(term) + right, re.IGNORECASE)


_TERM_CACHE: dict[str, list[tuple[str, re.Pattern]]] = {}


def _terms(section: str) -> list[tuple[str, re.Pattern]]:
    key = f"{PRIVATE_TERMS_FILE}:{section}"
    if key not in _TERM_CACHE:
        t = load_private_terms()
        # Longest first so "Jane Doe" wins over "Jane".
        items = sorted(t.get(section, []), key=len, reverse=True)
        _TERM_CACHE[key] = [(s, _term_regex(s)) for s in items]
    return _TERM_CACHE[key]


def redact(text: str, max_len: int | None = None) -> str:
    """Tier-1 redaction for local journal excerpts."""
    if not text:
        return ""
    out = text
    for _name, rx, repl in _T1:
        out = rx.sub(repl, out)
    for _term, rx in _terms("always"):
        out = rx.sub("<private>", out)
    if max_len is not None and len(out) > max_len:
        out = out[: max_len - 1].rstrip() + "…"
    return out


# --------------------------------------------------------------------------
# Tier 2: findings for the git-bound privacy gate
# --------------------------------------------------------------------------

_DOMAIN_RX = re.compile(
    r"(?<![@\w.-])((?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
    r"(?:com|net|org|io|dev|app|ai|co|au|cn|xyz|me|tech|cloud|site|online|store|shop|uk|nz|us|ca|de|fr|jp|hk|sg|info|biz))(?![\w-])",
    re.IGNORECASE,
)
_BUNDLE_RX = re.compile(r"\b(?:com|au|io|net|org)\.[a-z0-9-]+\.[a-z0-9.-]+\b")
_ABS_USER_PATH_RX = re.compile(r"/(?:Users|home)/(?!<|\$|USER\b|you\b|me\b|\{)[A-Za-z0-9._-]+")
_CODE_RECEIVERS = {
    "this", "self", "req", "res", "ctx", "window", "document", "module", "process", "props",
    "state", "config", "options", "opts", "event", "e", "err", "error", "result", "response",
    "request", "router", "server", "client", "app", "db", "prisma", "os", "sys", "path", "url",
}
_CJK_RX = re.compile(r"[㐀-䶿一-鿿豈-﫿぀-ヿ가-힯]")


def _load_lines(path: str) -> list[str]:
    try:
        with open(path, encoding="utf-8") as fh:
            return [l.strip() for l in fh if l.strip() and not l.lstrip().startswith("#")]
    except FileNotFoundError:
        return []


def _domain_allowlist() -> set[str]:
    base = set(_load_lines(os.path.join(HERE, "domain-allowlist.txt")))
    base |= set(_load_lines(os.path.join(LEARNING_HOME, "domain-allowlist.txt")))
    return {d.lower() for d in base}


def _domain_allowed(domain: str, allow: set[str]) -> bool:
    d = domain.lower().rstrip(".")
    parts = d.split(".")
    # allow exact or any parent suffix listed (docs.github.com <- github.com)
    return any(".".join(parts[i:]) in allow for i in range(len(parts) - 1))


# Placeholder domains used in docs and tests; never a real party.
_PLACEHOLDER_DOMAINS = {
    "test.com", "a.com", "b.com", "domain.com", "your-domain.com", "their-domain.com",
    "my-domain.com", "attacker.com", "evil.com", "email.com", "acme.com", "foo.com", "bar.com",
}
# Reverse-DNS labels (launchd, bundle IDs) that are tooling, not a client.
_REVERSE_DNS_OK = {"example", "apple", "anthropic", "engineering-craft", "dev-pipeline", "yourcompany", "google", "microsoft"}


def _public_email(addr: str, allow: set[str]) -> bool:
    """git@ and noreply@ addresses at allowlisted vendors, and placeholders, are not personal."""
    local, _, domain = addr.lower().partition("@")
    if domain.split(".")[0] == "example" or domain in _PLACEHOLDER_DOMAINS:
        return True
    return local in {"git", "noreply", "no-reply"} and _domain_allowed(domain, allow)


def _names() -> list[re.Pattern]:
    names = _load_lines(os.path.join(HERE, "given-names.txt"))
    # Capitalised whole words only: "<Name> booked" yes, a lowercase slug no.
    return [re.compile(r"(?<![\w-])" + re.escape(n) + r"(?![\w-])") for n in names]


def findings(text: str, public: bool = False) -> list[tuple[str, str]]:
    """Return [(rule, matched_text)] for anything that must not reach git."""
    hits: list[tuple[str, str]] = []
    allow = _domain_allowlist()
    for name, rx, _repl in _T1:
        for m in rx.finditer(text):
            if name == "email" and _public_email(m.group(0), allow):
                continue
            hits.append((name, m.group(0)))
    for section in ("always", "git-only"):
        for term, rx in _terms(section):
            for m in rx.finditer(text):
                hits.append((f"private-term:{section}", m.group(0)))
    for m in _DOMAIN_RX.finditer(text):
        dom = m.group(1)
        # `this.app.get(...)`, `req.app` are code, not domains.
        if dom.split(".")[0].lower() in _CODE_RECEIVERS or re.match(r"\.[A-Za-z_]", text[m.end():m.end() + 2]):
            continue
        low = dom.lower()
        if any(low == d or low.endswith("." + d) for d in _PLACEHOLDER_DOMAINS) or low.split(".")[0] in {"example", "localhost"}:
            continue
        if _BUNDLE_RX.fullmatch(dom.lower()):
            continue  # reported (or cleared) by the bundle-id rule below
        if not _domain_allowed(dom, allow):
            hits.append(("unknown-domain", dom))
    for m in _BUNDLE_RX.finditer(text):
        if m.group(0).split(".")[1] not in _REVERSE_DNS_OK:
            hits.append(("bundle-id", m.group(0)))
    for m in _ABS_USER_PATH_RX.finditer(text):
        hits.append(("user-path", m.group(0)))
    for rx in _names():
        for m in rx.finditer(text):
            hits.append(("given-name", m.group(0)))
    if public:
        m = _CJK_RX.search(text)
        if m:
            hits.append(("cjk-text", text[max(0, m.start() - 10): m.start() + 10]))
    return hits


def iter_hits(lines: Iterable[tuple[str, int, str]], public: bool = False):
    """lines: (file, lineno, text). Yields (file, lineno, rule, match)."""
    for f, n, t in lines:
        for rule, match in findings(t, public=public):
            yield f, n, rule, match
