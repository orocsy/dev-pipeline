"""End-to-end test of consolidate.sh with a stub `claude`: inbox worktrees,
privacy gate (clean change committed locally, dirty change rejected), entries
marked consolidated, nothing pushed. Spends no tokens."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LW = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(LW))

STUB = r'''#!/bin/bash
if [[ "$1" == "auth" ]]; then echo '{"loggedIn": true}'; exit 0; fi
dirs=(); prev=""
for a in "$@"; do [[ "$prev" == "--add-dir" ]] && dirs+=("$a"); prev="$a"; done
for d in "${dirs[@]}"; do
  case "$d" in
    */engineering-craft) mkdir -p "$d/categories/workflow/rules"
      printf '# Read a file before writing it\n\nAgents must read a file before overwriting it.\n' > "$d/categories/workflow/rules/read-before-write.md";;
    */dev-pipeline) echo "contact parent""@""family-mail.net for access" >> "$d/README.md";;
  esac
done
echo '{"type": "result", "subtype": "success", "is_error": false, "total_cost_usd": 0}'
'''


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True, text=True).stdout


def make_repo(path):
    os.makedirs(path)
    git(path, "init", "-q", "-b", "main")
    git(path, "config", "user.email", "test@example.com")
    git(path, "config", "user.name", "test")
    with open(os.path.join(path, "README.md"), "w") as fh:
        fh.write("# repo\n")
    git(path, "add", "-A")
    git(path, "commit", "-qm", "init")


class ConsolidateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="lw-cons-")
        self.home = os.path.join(self.tmp, "learning")
        os.makedirs(os.path.join(self.home, "bin"))
        for f in os.listdir(LW):
            if os.path.isfile(os.path.join(LW, f)):
                shutil.copy(os.path.join(LW, f), os.path.join(self.home, "bin", f))
        shutil.copy(os.path.join(REPO, "recipes", "recipes.json"), os.path.join(self.home, "bin", "recipes.json"))
        self.ec, self.dp = os.path.join(self.tmp, "ec"), os.path.join(self.tmp, "dp")
        make_repo(self.ec)
        make_repo(self.dp)
        stub = os.path.join(self.tmp, "claude")
        with open(stub, "w") as fh:
            fh.write(STUB)
        os.chmod(stub, 0o755)
        os.makedirs(os.path.join(self.home, "events"))
        with open(os.path.join(self.home, "events", "2099-01.jsonl"), "w") as fh:
            for i in range(6):
                fh.write(json.dumps({"id": f"W-test-{i}", "session": f"s{i}", "project": "p", "start": "2099-01-01T00:00:00Z",
                                     "end": "2099-01-01T01:00:00Z", "captured": "2099-01-01T01:00:00Z",
                                     "recipe_inferred": "bug-fix", "corrections": ["no, read it first"]}) + "\n")
        self.env = dict(os.environ, LW_HOME=self.home, CLAUDE_BIN=stub, LW_EC_REPO=self.ec, LW_DP_REPO=self.dp,
                        LW_PRIVATE_TERMS=os.path.join(self.tmp, "none.txt"), LW_NO_NOTIFY="1")
        self.env.pop("ANTHROPIC_API_KEY", None)
        self.env.pop("CLAUDE_CODE_OAUTH_TOKEN", None)

    def tearDown(self):
        for repo in (self.ec, self.dp):
            subprocess.run(["git", "-C", repo, "worktree", "prune"], capture_output=True)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_consolidate(self, *args):
        return subprocess.run(["bash", os.path.join(self.home, "bin", "consolidate.sh"), *args], env=self.env,
                              capture_output=True, text=True, timeout=120)

    def test_clean_change_committed_dirty_change_rejected(self):
        r = self.run_consolidate()
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        ec_log = git(self.ec, "log", "--oneline", "main..learning/inbox")
        self.assertIn("learn(auto)", ec_log)
        self.assertIn("read-before-write.md", git(self.ec, "show", "--stat", "learning/inbox"))
        self.assertEqual(git(self.dp, "log", "--oneline", "main..learning/inbox"), "")
        rejected = os.listdir(os.path.join(self.home, "rejected"))
        self.assertTrue(any(f.endswith("-dev-pipeline.patch") for f in rejected), rejected)
        self.assertEqual(git(os.path.join(self.home, "inbox", "dev-pipeline"), "status", "--porcelain"), "")
        with open(os.path.join(self.home, "state", "consolidated.json")) as fh:
            done = json.load(fh)["ids"]
        self.assertEqual(len(done), 6)
        self.assertEqual(git(self.ec, "remote"), "")  # nothing to push to, and nothing tried

    def test_too_few_entries_skips_model(self):
        with open(os.path.join(self.home, "events", "2099-01.jsonl"), "w") as fh:
            fh.write(json.dumps({"id": "W-x-0", "session": "s", "project": "p", "captured": "2099-01-01T00:00:00Z"}) + "\n")
        r = self.run_consolidate()
        self.assertEqual(r.returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(self.home, "inbox", "engineering-craft")))

    def test_signed_out_cli_leaves_entries_pending(self):
        with open(self.env["CLAUDE_BIN"], "w") as fh:
            fh.write('#!/bin/bash\n[[ "$1" == auth ]] && echo \'{"loggedIn": false}\'\nexit 0\n')
        r = self.run_consolidate()
        self.assertEqual(r.returncode, 0)
        self.assertIn("not signed in", r.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.home, "state", "consolidated.json")))


if __name__ == "__main__":
    unittest.main()
