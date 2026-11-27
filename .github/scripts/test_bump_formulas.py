#!/usr/bin/env python3
"""test_bump_formulas.py — offline tests for bump_formulas.py (no network; API and download faked).

Usage: python3 .github/scripts/test_bump_formulas.py [-v]   (--help prints this)
"""
import contextlib
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

if any(a in ("-h", "--help") for a in sys.argv[1:]):
    print(__doc__.strip() if __doc__ else "")
    sys.exit(0)

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bump_formulas as bf  # noqa: E402

FORMULA = '''class Demo < Formula
  desc "demo"
  url "https://github.com/acme/demo/releases/download/v1.2.0/demo-1.2.0.tar.gz"
  sha256 "{sha}"
  license "MIT"
end
'''.format(sha="0" * 64)
ASSET = b"new tarball bytes"


def fake_latest(tag, asset_name="demo-1.3.0.tar.gz"):
    return lambda owner, repo: {"tag_name": tag, "assets": [
        {"name": asset_name, "browser_download_url": f"https://dl/{asset_name}"}]}


class Bump(unittest.TestCase):
    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        self.f = self.d / "demo.rb"
        self.f.write_text(FORMULA)

    def test_bumps_url_and_sha_from_downloaded_bytes(self):
        line, changed = bf.bump(self.f, False, get=lambda u, a=None: ASSET, latest=fake_latest("v1.3.0"))
        self.assertTrue(changed, line)
        out = self.f.read_text()
        self.assertIn("/download/v1.3.0/demo-1.3.0.tar.gz", out)
        self.assertIn(hashlib.sha256(ASSET).hexdigest(), out)
        self.assertNotIn("0" * 64, out)
        self.assertIn('license "MIT"', out, "the rest of the formula is untouched")

    def test_up_to_date_writes_nothing(self):
        line, changed = bf.bump(self.f, False, get=lambda *a: self.fail("downloaded"),
                                latest=fake_latest("v1.2.0", "demo-1.2.0.tar.gz"))
        self.assertFalse(changed)
        self.assertEqual(self.f.read_text(), FORMULA)

    def test_missing_asset_is_an_error_and_writes_nothing(self):
        line, changed = bf.bump(self.f, False, get=lambda *a: ASSET,
                                latest=fake_latest("v1.3.0", "something-else.zip"))
        self.assertFalse(changed)
        self.assertIn("ERROR", line)
        self.assertEqual(self.f.read_text(), FORMULA)

    def test_dry_run_writes_nothing(self):
        line, changed = bf.bump(self.f, True, get=lambda *a: ASSET, latest=fake_latest("v1.3.0"))
        self.assertTrue(changed)
        self.assertIn("dry-run", line)
        self.assertEqual(self.f.read_text(), FORMULA)

    def test_non_release_url_is_skipped(self):
        self.f.write_text(FORMULA.replace("releases/download/v1.2.0/demo-1.2.0.tar.gz",
                                          "archive/refs/heads/main.tar.gz"))
        line, changed = bf.bump(self.f, False, get=lambda *a: ASSET, latest=fake_latest("v1.3.0"))
        self.assertFalse(changed)
        self.assertIn("skipped", line)

    def test_non_version_tag_is_refused(self):
        line, changed = bf.bump(self.f, False, get=lambda *a: ASSET, latest=fake_latest("nightly"))
        self.assertFalse(changed)
        self.assertIn("ERROR", line)


ARCHIVE_FORMULA = '''class Demo < Formula
  desc "demo"
  url "https://github.com/acme/demo/archive/refs/tags/v1.2.0.tar.gz"
  sha256 "{sha}"
  license "MIT"
end
'''.format(sha="0" * 64)
ARCHIVE = b"source archive bytes"


class ArchiveBump(unittest.TestCase):
    """Formulas that build from the git tag's SOURCE archive (archive/refs/tags/vX.tar.gz)
    bump to the latest release's tag archive; the sha256 comes from the downloaded archive
    itself, never from the API. refs/heads/... must stay skipped."""

    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        self.f = self.d / "demo.rb"
        self.f.write_text(ARCHIVE_FORMULA)

    def test_archive_url_bumps_to_latest_tag_archive(self):
        line, changed = bf.bump(self.f, False, get=lambda u, a=None: ARCHIVE,
                                latest=lambda o, r: {"tag_name": "v1.3.0", "assets": []})
        self.assertTrue(changed, line)
        out = self.f.read_text()
        self.assertIn("/archive/refs/tags/v1.3.0.tar.gz", out)
        self.assertIn(hashlib.sha256(ARCHIVE).hexdigest(), out)
        self.assertNotIn("0" * 64, out)
        self.assertIn('license "MIT"', out, "the rest of the formula is untouched")
        # exact line, closing quote included — a substring check alone let the
        # group(4)/group("quote") mix-up ship a mangled url line (2026-11-08)
        self.assertIn('  url "https://github.com/acme/demo/archive/refs/tags/v1.3.0.tar.gz"', out)

    def test_archive_up_to_date_writes_nothing(self):
        line, changed = bf.bump(self.f, False, get=lambda *a: self.fail("downloaded"),
                                latest=lambda o, r: {"tag_name": "v1.2.0", "assets": []})
        self.assertFalse(changed)
        self.assertEqual(self.f.read_text(), ARCHIVE_FORMULA)

    def test_archive_dry_run_writes_nothing(self):
        line, changed = bf.bump(self.f, True, get=lambda *a: ARCHIVE,
                                latest=lambda o, r: {"tag_name": "v1.3.0", "assets": []})
        self.assertTrue(changed)
        self.assertIn("dry-run", line)
        self.assertEqual(self.f.read_text(), ARCHIVE_FORMULA)

    def test_refs_heads_archive_is_still_skipped(self):
        self.f.write_text(ARCHIVE_FORMULA.replace("refs/tags/v1.2.0", "refs/heads/main"))
        line, changed = bf.bump(self.f, False, get=lambda *a: ARCHIVE,
                                latest=lambda o, r: {"tag_name": "v1.3.0", "assets": []})
        self.assertFalse(changed)
        self.assertIn("skipped", line)


class MultiFormulaMain(unittest.TestCase):
    """main() over a tap dir must bump EVERY release-tarball formula independently and
    skip the rest — the 'all my formulae get the same treatment' contract."""

    def test_main_discovers_and_bumps_all_matching_formulae(self):
        d = Path(tempfile.mkdtemp())
        fx = d / "Formula"
        fx.mkdir()
        for name, url in (("alpha", "https://github.com/acme/alpha/releases/download/v1.0.0/alpha-1.0.0.tar.gz"),
                          ("beta", "https://github.com/acme/beta/releases/download/v2.0.0/beta-2.0.0.tar.gz"),
                          ("gamma", "https://github.com/acme/gamma/archive/refs/heads/main.tar.gz")):
            (fx / f"{name}.rb").write_text(
                f'class X < Formula\n  url "{url}"\n  sha256 "{"0"*64}"\n  license "MIT"\nend\n')
        # alpha has a newer release; beta is current; gamma is not a release url.
        # NOTE: patch bf.bump, not bf._get/latest_release — bump()'s defaults bind those
        # names at definition time, so module-attr patching would not reach it.
        rels = {"alpha": {"tag_name": "v1.1.0",
                          "assets": [{"name": "alpha-1.1.0.tar.gz", "browser_download_url": "https://dl/alpha"}]},
                "beta": {"tag_name": "v2.0.0",
                         "assets": [{"name": "beta-2.0.0.tar.gz", "browser_download_url": "https://dl/beta"}]}}
        orig_bump = bf.bump
        bf.bump = lambda p, dr: orig_bump(p, dr, get=lambda u, a=None: ASSET,
                                          latest=lambda o, r: rels[p.stem])
        try:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = bf.main(["--tap-dir", str(d)])
            out = buf.getvalue()
        finally:
            bf.bump = orig_bump
        self.assertEqual(rc, 0, out)
        self.assertIn("alpha: 1.0.0 -> 1.1.0", out)
        self.assertIn("beta: up to date (2.0.0)", out)
        self.assertIn("gamma: skipped", out)
        self.assertIn("changed=alpha", out)
        a = (fx / "alpha.rb").read_text()
        self.assertIn("/download/v1.1.0/alpha-1.1.0.tar.gz", a)
        self.assertIn(hashlib.sha256(ASSET).hexdigest(), a)
        self.assertIn("v2.0.0/beta-2.0.0.tar.gz", (fx / "beta.rb").read_text(), "untouched formula stays")

    def test_main_formula_filter_selects_one(self):
        d = Path(tempfile.mkdtemp())
        fx = d / "Formula"
        fx.mkdir()
        for name in ("alpha", "beta"):
            (fx / f"{name}.rb").write_text(
                f'class X < Formula\n  url "https://github.com/acme/{name}/releases/download/v1.0.0/'
                f'{name}-1.0.0.tar.gz"\n  sha256 "{"0"*64}"\nend\n')
        orig_bump = bf.bump
        bf.bump = lambda p, dr: orig_bump(p, dr, get=lambda u, a=None: ASSET,
                                          latest=lambda o, r: {"tag_name": "v9.9.9", "assets": [
                                              {"name": f"{p.stem}-9.9.9.tar.gz",
                                               "browser_download_url": "https://dl/x"}]})
        try:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = bf.main(["--tap-dir", str(d), "--formula", "beta"])
            out = buf.getvalue()
        finally:
            bf.bump = orig_bump
        self.assertEqual(rc, 0, out)
        self.assertIn("beta: 1.0.0 -> 9.9.9", out)
        self.assertNotIn("alpha:", out)
        self.assertIn("v1.0.0/alpha-1.0.0.tar.gz", (fx / "alpha.rb").read_text())


class TolerantTags(unittest.TestCase):
    """Any tag carrying a trailing version must bump: v1.3.0, 1.3.0, cc-transcript-v1.3.0,
    release-1.3.0-rc1. Non-version tags (nightly) stay refused. The written url keeps the FULL
    tag and must still parse on the NEXT bump — the old v-only URL_RE lost non-v formulas after
    one bump and rejected prefixed tags outright (2026-11-27, distiller stuck at 0.8.4)."""

    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        self.f = self.d / "demo.rb"
        self.f.write_text(FORMULA)

    def bump_with(self, tag, asset="demo-1.3.0.tar.gz"):
        return bf.bump(self.f, False, get=lambda u, a=None: ASSET,
                       latest=fake_latest(tag, asset))

    def test_version_from_tag(self):
        self.assertEqual(bf.version_from_tag("v1.2.3"), "1.2.3")
        self.assertEqual(bf.version_from_tag("1.2.3"), "1.2.3")
        self.assertEqual(bf.version_from_tag("cc-transcript-v0.9.0"), "0.9.0")
        self.assertEqual(bf.version_from_tag("release-2.0.0-rc1"), "2.0.0-rc1")
        self.assertIsNone(bf.version_from_tag("nightly"))
        self.assertIsNone(bf.version_from_tag(""))

    def test_prefixed_tag_bumps_and_keeps_full_tag_in_url(self):
        line, changed = self.bump_with("cc-transcript-v1.3.0")
        self.assertTrue(changed, line)
        out = self.f.read_text()
        self.assertIn("/download/cc-transcript-v1.3.0/demo-1.3.0.tar.gz", out)
        self.assertIn(hashlib.sha256(ASSET).hexdigest(), out)
        self.assertNotIn("0" * 64, out)

    def test_bare_tag_bumps_and_next_bump_still_parses(self):
        line, changed = self.bump_with("1.3.0")
        self.assertTrue(changed, line)
        self.assertIn("/download/1.3.0/demo-1.3.0.tar.gz", self.f.read_text())
        # round-trip: the bumped formula (no literal v in the url) must still be parsed
        line2, changed2 = bf.bump(self.f, False, get=lambda u, a=None: ASSET,
                                  latest=fake_latest("1.4.0", "demo-1.4.0.tar.gz"))
        self.assertTrue(changed2, line2)
        self.assertIn("/download/1.4.0/demo-1.4.0.tar.gz", self.f.read_text())

    def test_non_version_prefixed_tag_is_refused(self):
        line, changed = self.bump_with("nightly-build")
        self.assertFalse(changed)
        self.assertIn("ERROR", line)
        self.assertEqual(self.f.read_text(), FORMULA)

    def test_archive_tag_round_trips_without_v(self):
        self.f.write_text(ARCHIVE_FORMULA)
        line, changed = bf.bump(self.f, False, get=lambda u, a=None: ARCHIVE,
                                latest=lambda o, r: {"tag_name": "pkg-2.0.0", "assets": []})
        self.assertTrue(changed, line)
        self.assertIn("/archive/refs/tags/pkg-2.0.0.tar.gz", self.f.read_text())
        line2, changed2 = bf.bump(self.f, False, get=lambda u, a=None: ARCHIVE,
                                  latest=lambda o, r: {"tag_name": "2.1.0", "assets": []})
        self.assertTrue(changed2, line2)
        self.assertIn("/archive/refs/tags/2.1.0.tar.gz", self.f.read_text())


if __name__ == "__main__":
    unittest.main()
