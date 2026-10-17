#!/usr/bin/env python3
"""test_bump_formulas.py — offline tests for bump_formulas.py (no network; API and download faked).

Usage: python3 .github/scripts/test_bump_formulas.py [-v]   (--help prints this)
"""
import hashlib
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


if __name__ == "__main__":
    unittest.main()
