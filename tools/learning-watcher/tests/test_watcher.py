"""Tests for the learning watcher: capture, redaction, idempotency, digest, lint.

Fake credentials are assembled at runtime so no secret-shaped literal is
committed (GitHub push protection scans for them).
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LW = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(LW))
HOME = os.path.expanduser("~")

FAKE_KEY = "sk_" + "live_" + "4eC39HqLyjWDarjtT1zdp7dc"
FAKE_EMAIL = "parent" + "@" + "family-mail.net"
SECRET_NAME = "Zephyrine"      # [always] private term
CLIENT = "acmekids"            # [git-only] private term


def _read(path, mode="r"):
    with open(path, mode) as fh:
        return fh.read()


def line(**kw):
    return json.dumps(kw)


def human(text, ts):
    return line(parentUuid="p", type="user", origin={"kind": "human"}, timestamp=ts, gitBranch="feat/x",
                message={"role": "user", "content": text})


def assistant(items, ts):
    return line(parentUuid="p", type="assistant", timestamp=ts, gitBranch="feat/x",
                message={"role": "assistant", "content": items})


def result(tid, text, ts, error=False):
    return line(parentUuid="p", type="user", timestamp=ts,
                message={"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": text, "is_error": error}]})


def bash(tid, cmd):
    return {"type": "tool_use", "id": tid, "name": "Bash", "input": {"command": cmd}}


def transcript_lines(day="2099-01-01"):
    t = lambda m: f"{day}T10:{m:02d}:00.000Z"
    return [
        line(type="api-request", timestamp=t(0), blob="x" * 2000),
        human(f"Please fix the waitlist hold for {SECRET_NAME}", t(1)),
        assistant([{"type": "text", "text": "Recipe: bug-fix — /dev-pipeline:fix → red test → validate"},
                   {"type": "tool_use", "id": "s1", "name": "Skill", "input": {"skill": "dev-pipeline:fix"}}], t(2)),
        result("s1", "loaded", t(2)),
        assistant([bash("b1", "cd apps/api && pnpm test booking")], t(3)),
        result("b1", f"Exit code 1\nFAIL booking.spec.ts\nError: expected 1 got 2 STRIPE_KEY={FAKE_KEY}", t(3), error=True),
        assistant([bash("b2", "cd apps/api && pnpm test booking")], t(4)),
        result("b2", "Exit code 1\nFAIL booking.spec.ts\nError: expected 1 got 2", t(4), error=True),
        assistant([{"type": "tool_use", "id": "e1", "name": "Edit", "input": {"file_path": "/x/apps/api/src/booking.service.ts"}}], t(5)),
        result("e1", "ok", t(5)),
        assistant([bash("b3", "cd apps/api && pnpm test booking")], t(6)),
        result("b3", "Tests: 12 passed", t(6)),
        assistant([bash("c1", "git add -A && git commit -m \"fix(booking): hold the seat for $28.00 classes\"")], t(7)),
        result("c1", "[feat/x abc1234] fix(booking)", t(7)),
        human(f"no, don't push yet — email {FAKE_EMAIL} first", t(8)),
        assistant([{"type": "tool_use", "id": "w1", "name": "mcp__ccd_turn__wrap_up",
                    "input": {"recap": f"Fixed the waitlist hold for {SECRET_NAME}; 12 tests green. Not pushed."}}], t(9)),
        result("w1", "ok", t(9)),
        human("great, thanks", t(10)),
    ]


class WatcherEnv(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="lw-test-")
        self.lw_home = os.path.join(self.tmp, "learning")
        self.projects = os.path.join(self.tmp, "projects")
        slug = re.sub(r"[/.]", "-", HOME) + "-projects-acmeapp"
        os.makedirs(os.path.join(self.projects, slug))
        self.transcript = os.path.join(self.projects, slug, "0123abcd-0000-0000-0000-000000000000.jsonl")
        self.terms = os.path.join(self.tmp, "private-terms.txt")
        with open(self.terms, "w") as fh:
            fh.write(f"[always]\n{SECRET_NAME}\n[git-only]\n{CLIENT}\n")
        self.env = dict(os.environ, LW_HOME=self.lw_home, LW_PROJECTS_DIR=self.projects,
                        LW_PRIVATE_TERMS=self.terms, LW_RECIPES=os.path.join(REPO, "recipes", "recipes.json"))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, lines, mode="w", trailing_newline=True):
        with open(self.transcript, mode) as fh:
            fh.write("\n".join(lines) + ("\n" if trailing_newline else ""))

    def capture(self, *args):
        return subprocess.run([sys.executable, os.path.join(LW, "capture.py"), "--idle-minutes", "0",
                               "--backfill-hours", "1000000", *args],
                              env=self.env, capture_output=True, text=True, check=True)

    def journal(self):
        path = os.path.join(self.lw_home, "journal", "acmeapp.md")
        return _read(path) if os.path.exists(path) else ""

    def events(self):
        out = []
        for name in sorted(os.listdir(os.path.join(self.lw_home, "events"))):
            with open(os.path.join(self.lw_home, "events", name)) as fh:
                out += [json.loads(l) for l in fh if l.strip()]
        return out


class CaptureTests(WatcherEnv):
    def test_entry_has_signals_and_is_redacted(self):
        self.write(transcript_lines())
        self.capture()
        j = self.journal()
        self.assertIn("announced bug-fix", j)
        self.assertIn("inferred bug-fix", j)
        self.assertIn("dev-pipeline:fix", j)
        self.assertIn("green after red", j)
        self.assertIn("passed after 2 failure(s)", j)
        self.assertIn("user correction", j)
        self.assertIn("recap:", j)
        self.assertIn("user praise", j)
        self.assertIn("fix(booking)", j)
        for leaked in (FAKE_KEY, FAKE_EMAIL, SECRET_NAME, "$28.00"):
            self.assertNotIn(leaked, j)
            self.assertNotIn(leaked, json.dumps(self.events()))
        self.assertIn("<email>", j)
        self.assertIn("<price>", j)
        self.assertIn("<private>", j)
        ev = self.events()[0]
        self.assertEqual(ev["errors_total"], 2)
        self.assertEqual(ev["error_sigs"][0][1], 2)  # same command failed twice: a retry loop
        self.assertIn("typescript", ev["stack"])

    def test_second_run_is_idempotent_and_new_lines_make_a_new_entry(self):
        self.write(transcript_lines())
        self.capture()
        self.capture()
        self.assertEqual(len(self.events()), 1)
        self.write(transcript_lines(day="2099-01-02"), mode="a")
        self.capture()
        evs = self.events()
        self.assertEqual(len(evs), 2)
        self.assertNotEqual(evs[0]["id"], evs[1]["id"])

    def test_partial_last_line_waits_for_its_newline(self):
        lines = transcript_lines()
        self.write(lines[:-1] + [lines[-1][:20]], trailing_newline=False)
        self.capture()
        cursors = json.loads(_read(os.path.join(self.lw_home, "state", "cursors.json")))
        offset = cursors[self.transcript]["offset"]
        self.assertEqual(_read(self.transcript, "rb")[offset:], lines[-1][:20].encode())
        with open(self.transcript, "a") as fh:
            fh.write(lines[-1][20:] + "\n")
        self.capture()
        cursors = json.loads(_read(os.path.join(self.lw_home, "state", "cursors.json")))
        self.assertEqual(cursors[self.transcript]["offset"], os.path.getsize(self.transcript))

    def test_paused_switch_stops_everything(self):
        os.makedirs(self.lw_home)
        open(os.path.join(self.lw_home, "PAUSED"), "w").close()
        self.write(transcript_lines())
        self.capture()
        self.assertEqual(self.journal(), "")
        self.assertFalse(os.path.exists(os.path.join(self.lw_home, "state", "cursors.json")))

    def test_digest_is_capped_and_marks_consolidated(self):
        for d in range(1, 8):
            self.write(transcript_lines(day=f"2099-01-0{d}"), mode="a")
            self.capture()
        out = os.path.join(self.lw_home, "digests", "t.md")
        ids = os.path.join(self.lw_home, "digests", "t.ids")
        run = lambda *a: subprocess.run([sys.executable, os.path.join(LW, "digest.py"), *a], env=self.env,
                                        capture_output=True, text=True, check=True)
        run("--out", out, "--ids-out", ids, "--max-chars", "3000")
        text = _read(out)
        self.assertLessEqual(len(text), 3000)
        self.assertIn("## Recipe outcomes", text)
        self.assertIn("| bug-fix |", text)
        self.assertEqual(len(_read(ids).split()), 7)
        run("--mark-consolidated", ids)
        self.assertIn("0 pending", run("--out", out).stdout)


class LintTests(WatcherEnv):
    def lint(self, text, *args):
        return subprocess.run([sys.executable, os.path.join(LW, "privacy_lint.py"), "--stdin", *args],
                              input=text, env=self.env, capture_output=True, text=True)

    def test_blocks_private_material(self):
        for bad in (f"key {FAKE_KEY}", f"mail {FAKE_EMAIL}", f"the {CLIENT} booking flow", f"{SECRET_NAME} booked",
                    "costs $28.00", "see https://client-shop.com.au/x", "/Users/someone/projects/x",
                    "com.acmeco.app", "Olivia booked a class"):
            self.assertEqual(self.lint(bad).returncode, 1, bad)
        self.assertEqual(self.lint("客户说", "--public").returncode, 1)

    def test_allows_generic_engineering_text(self):
        ok = ("A booking service must re-check slot availability inside the transaction.\n"
              "See https://docs.nestjs.com/techniques/validation and https://developer.apple.com/documentation/swiftui\n"
              "const token: string = req.headers.authorization\n"
              "password reset flow; git@github.com:org/repo.git\n")
        r = self.lint(ok, "--public")
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_allow_marker(self):
        self.assertEqual(self.lint("costs $28.00  privacy-lint: allow example price").returncode, 0)


class WrappedFeedbackTests(WatcherEnv):
    def test_feedback_inside_artifact_context_counts_as_human(self):
        t = lambda m: f"2099-02-01T10:{m:02d}:00.000Z"
        wrapped = ('<artifact-view-context artifact="x">\n{"context":{"mode":"edit"}}\n'
                   '<artifact-content-authored-by-others/>\n</artifact-view-context>\n\n'
                   '<!-- reply 2 -->\n> Settings → OAuth: allow OAuth and add the redirect address.\n\n'
                   'You mean onboarding options OAuth, enable and add this redirect url right?\n')
        self.write([
            line(type="custom-title", customTitle="Backend branch setup", sessionId="s"),
            assistant([bash("b1", "gh pr view 46")], t(1)),
            result("b1", "ok", t(1)),
            human(wrapped, t(2)),
            assistant([{"type": "tool_use", "id": "w1", "name": "mcp__ccd_turn__wrap_up", "input": {"recap": "Steps rewritten."}}], t(3)),
            result("w1", "ok", t(3)),
        ])
        self.capture()
        ev = self.events()[0]
        self.assertEqual(ev["title"], "Backend branch setup")
        self.assertEqual(ev["human_turns"], 1)
        self.assertEqual(len(ev["clarifications"]), 1)
        self.assertIn("redirect url right?", ev["clarifications"][0])
        self.assertIn("· Backend branch setup ·", self.journal())
        self.assertIn("user had to ask", self.journal())


class IOSStackTests(unittest.TestCase):
    def test_ios_signals_are_tagged(self):
        sys.path.insert(0, LW)
        import capture  # noqa: E402
        b = capture.Burst("/x/-Users-u-projects-app/s.jsonl", 0, {"excerpt_chars": 200, "recap_chars": 360, "max_items": 8})
        b.tool_use({"id": "1", "name": "Bash", "input": {"command": "xcodebuild -scheme App -destination 'platform=iOS Simulator' test"}})
        b.tool_use({"id": "2", "name": "Edit", "input": {"file_path": "/r/apps/ios/App/DesignSystem/PrimaryButton.swift"}})
        b.tool_use({"id": "3", "name": "Write", "input": {"file_path": "/r/apps/ios/AppUITests/BookingFlowUITests.swift"}})
        b.tool_use({"id": "4", "name": "mcp__Claude_Code_iOS_Simulator__control", "input": {"action": "screenshot"}})
        for tag in ("swift", "ios", "ios-tests", "ios-simulator", "swiftui-design-system"):
            self.assertIn(tag, b.stack, tag)


class RecipeInferenceTests(unittest.TestCase):
    def test_infer(self):
        sys.path.insert(0, LW)
        import capture  # noqa: E402
        from collections import Counter
        lib = capture.RecipesLib(os.path.join(REPO, "recipes", "recipes.json"))
        self.assertEqual(lib.infer(Counter({"dev-pipeline:fix": 1, "dev-pipeline:review": 1}), Counter()), "bug-fix")
        self.assertEqual(lib.infer(Counter({"dev-pipeline:review": 1}), Counter()), "review-only")
        self.assertEqual(lib.infer(Counter({"huashu-design": 1}), Counter()), "ui-design-round")
        self.assertEqual(lib.infer(Counter(), Counter({"dev-pipeline:test-planner": 1})), "test-only")
        self.assertIsNone(lib.infer(Counter({"stripe:test-cards": 1}), Counter()))
        self.assertEqual(lib.infer(Counter({"stack-setup": 1}), Counter()), "provider-setup")


if __name__ == "__main__":
    unittest.main()
