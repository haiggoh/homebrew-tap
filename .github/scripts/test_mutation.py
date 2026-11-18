#!/usr/bin/env python3
"""test_mutation.py — meta-test: the push-race tests must KILL the pre-fix mutant of push_bump.sh.

Mutation testing, enshrined in CI: build the M1 mutant (the `git fetch` + rebase block deleted,
leaving a bare `git push` — exactly the pre-fix behavior that made actions run 44092258642 go
red with "! [rejected] main -> main (fetch first)"), run the race tests against the mutant in
a subprocess, and assert they FAIL. Then run the same tests against the real script and assert
they PASS — so a red mutant run is caused by the mutation, not by a broken test environment.
The mutant is also `bash -n`-checked, so red comes from behavior, not a syntax error.

Cost: two short subprocess runs of three race tests (~20-30s total), inside the existing
`unittest discover` offline-tests step.

Usage: python3 .github/scripts/test_mutation.py [-v]   (--help prints this)
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

SCRIPTS = Path(__file__).resolve().parent
# The three race tests that the M1 mutant (bare push, no rebase) must turn red.
RACE_TESTS = [
    "PushRace.test_push_bump_rebases_over_concurrent_bump_of_another_formula",
    "PushRace.test_push_bump_drops_empty_commit_when_same_bump_already_landed",
    "PushRace.test_push_bump_conflicting_concurrent_bump_skips_with_warning",
]
MUTANT_MARKER = "A concurrent run may have pushed"  # deleting this line's block makes M1


def build_variant(dst: Path, mutate: bool) -> str:
    """Copy test_push_bump.py + push_bump.sh into dst; return the (possibly mutated) script text."""
    (dst / "test_push_bump.py").write_bytes((SCRIPTS / "test_push_bump.py").read_bytes())
    script = (SCRIPTS / "push_bump.sh").read_text()
    if mutate:
        lines = script.splitlines(keepends=True)
        start = next(i for i, line in enumerate(lines) if MUTANT_MARKER in line)
        end = next(i for i in range(start, len(lines)) if lines[i].rstrip() == "fi")
        del lines[start:end + 1]  # comment + fetch + rebase-if-block, leaving the bare push
        script = "".join(lines)
    (dst / "push_bump.sh").write_text(script)
    return script


def run_race_tests(d: Path) -> subprocess.CompletedProcess:
    env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
    return subprocess.run([sys.executable, "test_push_bump.py", *RACE_TESTS],
                          cwd=str(d), capture_output=True, text=True, env=env)


class Mutation(unittest.TestCase):
    def test_prefix_mutant_is_killed_and_real_script_still_passes(self):
        with tempfile.TemporaryDirectory(prefix="push-bump-mut-") as td:
            root = Path(td)
            mut, real = root / "mutant", root / "real"
            mut.mkdir()
            real.mkdir()
            mutant_text = build_variant(mut, mutate=True)
            real_text = build_variant(real, mutate=False)
            self.assertNotEqual(mutant_text, real_text, "mutation did not change the script")
            self.assertNotIn("git rebase", mutant_text, "M1 mutant must not rebase at all")
            # red must come from behavior, not a syntax error
            syntax = subprocess.run(["bash", "-n", str(mut / "push_bump.sh")],
                                    capture_output=True, text=True)
            self.assertEqual(syntax.returncode, 0, "mutant is not valid bash: " + syntax.stderr)
            m = run_race_tests(mut)
            r = run_race_tests(real)
        # mutant: all three race tests red
        self.assertNotEqual(m.returncode, 0,
                            "M1 mutant SURVIVED — race tests passed on the pre-fix script:\n"
                            + m.stdout + m.stderr)
        m_out = m.stdout + m.stderr  # unittest writes its report to stderr
        self.assertIn("FAILED", m_out, m_out)
        for dotted in RACE_TESTS:
            short = dotted.split(".")[-1]
            self.assertIn(f"FAIL: {short}", m_out,
                          f"mutant did not kill {short}:\n{m_out}")
        # control: real script green on the same tests
        r_out = r.stdout + r.stderr
        self.assertEqual(r.returncode, 0,
                         "control failed — real script did not pass the race tests:\n" + r_out)
        self.assertIn("OK", r_out)


if __name__ == "__main__":
    unittest.main()
