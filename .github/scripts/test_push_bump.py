#!/usr/bin/env python3
"""test_push_bump.py — offline tests for push_bump.sh (local git only, no network).

Why this exists: the bump workflow checks out with fetch-depth: 1 and its concurrency
group lets runs overlap, so origin/main can move between checkout and push. Actions run
44092258642 went red exactly there — a concurrent run had pushed the identical bump
(60c28eb) and the old step's bare `git push` was rejected with
"! [rejected] main -> main (fetch first)". These tests replay that race against local
bare repos: a bare push in that situation MUST be rejected (the planted negative — the
old workflow step), and push_bump.sh must rebase and land, or cleanly skip, exit 0.

Usage: python3 .github/scripts/test_push_bump.py [-v]   (--help prints this)
"""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

if any(a in ("-h", "--help") for a in sys.argv[1:]):
    print(__doc__.strip() if __doc__ else "")
    sys.exit(0)

SCRIPT = Path(__file__).resolve().parent / "push_bump.sh"


def git(cwd, *args, check=True, env=None):
    r = subprocess.run(["git", *args], cwd=str(cwd), capture_output=True, text=True, env=env)
    if check and r.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} in {cwd}: rc={r.returncode} {r.stderr}")
    return r


def commit(cwd, msg, when=None, paths=("-A",)):
    """`when` pins author+committer date (GIT_*_DATE) so two identical-content commits
    hash differently — same-second commits would be the SAME sha and a push would be
    trivially up-to-date instead of rejected."""
    env = None
    if when is not None:
        env = {**os.environ, "GIT_AUTHOR_DATE": when, "GIT_COMMITTER_DATE": when}
    git(cwd, "-c", "user.name=test", "-c", "user.email=test@example.com", "add", *paths, env=env)
    git(cwd, "-c", "user.name=test", "-c", "user.email=test@example.com", "commit", "-m", msg, env=env)


def formula(ver):
    return (f'class Demo < Formula\n'
            f'  desc "demo"\n'
            f'  url "https://github.com/acme/demo/releases/download/v{ver}/demo-{ver}.tar.gz"\n'
            f'  sha256 "{"0" * 64}"\n'
            f'  license "MIT"\n'
            f'end\n')


def run_script(cwd, *args):
    return subprocess.run(["bash", str(SCRIPT), *args], cwd=str(cwd),
                          capture_output=True, text=True)


class Sandbox:
    """A bare origin with one seed commit, plus `winner` (full clone) and `loser`
    (fetch-depth:1 clone, mirroring actions/checkout) — both able to push."""

    def __init__(self):
        self.d = Path(tempfile.mkdtemp(prefix="push-bump-test-"))
        self.origin = self.d / "origin.git"
        git(self.d, "init", "--bare", "-b", "main", str(self.origin))
        seed = self.d / "seed"
        git(self.d, "init", "-b", "main", str(seed))
        (seed / "Formula").mkdir()
        (seed / "Formula" / "demo.rb").write_text(formula("1.0.0"))
        commit(seed, "seed: demo 1.0.0")
        git(seed, "remote", "add", "origin", str(self.origin))
        git(seed, "push", "origin", "main")
        self.winner = self.d / "winner"
        git(self.d, "clone", f"file://{self.origin}", str(self.winner))
        self.loser = self.d / "loser"
        git(self.d, "clone", "--depth", "1", f"file://{self.origin}", str(self.loser))

    def loser_bump(self, ver, log_line=None):
        """The loser's bump step has rewritten the formula and written bump.log."""
        (self.loser / "Formula" / "demo.rb").write_text(formula(ver))
        line = log_line if log_line is not None else f"demo: 1.0.0 -> {ver} (sha256 {'a' * 12}…)"
        (self.loser / "bump.log").write_text(line + "\n")

    def origin_tip(self):
        return git(self.origin, "log", "-1", "--format=%H", "main").stdout.strip()

    def origin_subject(self):
        return git(self.origin, "log", "-1", "--format=%s", "main").stdout.strip()

    def origin_file(self, relpath):
        return git(self.origin, "show", f"main:{relpath}").stdout


class PushRace(unittest.TestCase):
    def test_bare_push_is_rejected_after_concurrent_push(self):
        """Planted negative: the OLD step (add, commit, bare `git push`) fails in
        exactly the scenario of run 44092258642. If this stops being rejected, the
        race no longer reproduces and the tests below prove nothing."""
        s = Sandbox()
        # a concurrent run lands the identical bump first. Distinct commit timestamps
        # (as in the real run 44092258642: 60c28eb vs 193eafe) — same-second commits with
        # identical content would hash identically and the push would be up-to-date.
        (s.winner / "Formula" / "demo.rb").write_text(formula("1.1.0"))
        commit(s.winner, "bump: demo: 1.0.0 -> 1.1.0", when="2026-11-17T13:23:49Z")
        git(s.winner, "push", "origin", "main")
        winner_tip = s.origin_tip()
        self.assertNotEqual(winner_tip, "", "winner push did not land")
        # our run: same checkout base, same bump, then the old bare push
        (s.loser / "Formula" / "demo.rb").write_text(formula("1.1.0"))
        commit(s.loser, "bump: demo: 1.0.0 -> 1.1.0", when="2026-11-17T13:23:50Z",
               paths=("Formula/",))
        r = git(s.loser, "push", "origin", "main", check=False)
        self.assertNotEqual(r.returncode, 0,
                            "bare push unexpectedly succeeded: " + r.stdout + r.stderr)
        self.assertIn("rejected", r.stderr)
        self.assertEqual(s.origin_tip(), winner_tip, "a rejected push must not move origin/main")

    def test_push_bump_lands_when_no_concurrent_push(self):
        s = Sandbox()
        s.loser_bump("1.1.0")
        r = run_script(s.loser, "--bump-log", "bump.log")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(s.origin_subject(), "bump: demo: 1.0.0 -> 1.1.0")
        self.assertEqual(s.origin_file("Formula/demo.rb"), formula("1.1.0"))
        self.assertEqual(git(s.loser, "status", "--porcelain", "-uno").stdout, "")

    def test_push_bump_rebases_over_concurrent_bump_of_another_formula(self):
        s = Sandbox()
        (s.winner / "Formula" / "other.rb").write_text(formula("1.1.0").replace("Demo", "Other").replace("demo", "other"))
        commit(s.winner, "bump: other: 1.0.0 -> 1.1.0")
        git(s.winner, "push", "origin", "main")
        winner_tip = s.origin_tip()
        s.loser_bump("1.1.0")
        r = run_script(s.loser, "--bump-log", "bump.log")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotEqual(s.origin_tip(), winner_tip, "our rebase must have landed on top")
        self.assertEqual(s.origin_subject(), "bump: demo: 1.0.0 -> 1.1.0")
        subjects = git(s.origin, "log", "--format=%s", "main").stdout.splitlines()
        self.assertIn("bump: other: 1.0.0 -> 1.1.0", subjects)
        self.assertEqual(git(s.origin, "show", "main:Formula/other.rb").stdout,
                         formula("1.1.0").replace("Demo", "Other").replace("demo", "other"))
        self.assertEqual(git(s.origin, "show", "main:Formula/demo.rb").stdout, formula("1.1.0"))

    def test_push_bump_drops_empty_commit_when_same_bump_already_landed(self):
        s = Sandbox()
        (s.winner / "Formula" / "demo.rb").write_text(formula("1.1.0"))
        commit(s.winner, "bump: demo: 1.0.0 -> 1.1.0")
        git(s.winner, "push", "origin", "main")
        winner_tip = s.origin_tip()
        s.loser_bump("1.1.0")
        r = run_script(s.loser, "--bump-log", "bump.log")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(s.origin_tip(), winner_tip,
                         "our now-empty commit must be dropped, not pushed on top")
        self.assertEqual(s.origin_file("Formula/demo.rb"), formula("1.1.0"))
        self.assertEqual(git(s.loser, "status", "--porcelain", "-uno").stdout, "")

    def test_push_bump_conflicting_concurrent_bump_skips_with_warning(self):
        s = Sandbox()
        # concurrent run changed the SAME url line to a different version -> conflict
        (s.winner / "Formula" / "demo.rb").write_text(formula("9.9.9"))
        commit(s.winner, "bump: demo: 1.0.0 -> 9.9.9")
        git(s.winner, "push", "origin", "main")
        winner_tip = s.origin_tip()
        s.loser_bump("1.1.0")
        r = run_script(s.loser, "--bump-log", "bump.log")
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        self.assertIn("::warning::", r.stdout)
        self.assertEqual(s.origin_tip(), winner_tip, "a conflicting push must NOT land")
        self.assertEqual(git(s.loser, "status", "--porcelain", "-uno").stdout,
                         "", "rebase --abort must leave a clean tree")


class Usage(unittest.TestCase):
    def test_help_exits_0_without_touching_git(self):
        d = Path(tempfile.mkdtemp(prefix="push-bump-help-"))
        r = subprocess.run(["bash", str(SCRIPT), "--help"], cwd=str(d),
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0)
        self.assertIn("Usage:", r.stdout)
        self.assertFalse((d / ".git").exists(), "--help must not create a repo")

    def test_unknown_flag_exits_2(self):
        d = Path(tempfile.mkdtemp(prefix="push-bump-bad-"))
        r = subprocess.run(["bash", str(SCRIPT), "--bogus"], cwd=str(d),
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("unknown argument", r.stderr)

    def test_missing_bump_log_exits_2(self):
        s = Sandbox()
        r = run_script(s.loser, "--bump-log", "nope.log")
        self.assertEqual(r.returncode, 2)
        self.assertIn("bump log not found", r.stderr)

    def test_bump_log_without_change_lines_exits_2_and_commits_nothing(self):
        s = Sandbox()
        s.loser_bump("1.0.0", log_line="demo: up to date (1.0.0)")
        r = run_script(s.loser, "--bump-log", "bump.log")
        self.assertEqual(r.returncode, 2)
        self.assertIn("nothing to commit", r.stderr)
        self.assertEqual(git(s.loser, "log", "-1", "--format=%s").stdout.strip(),
                         "seed: demo 1.0.0")


if __name__ == "__main__":
    unittest.main()
