#!/usr/bin/env python3
"""bump_formulas.py — point each Formula/*.rb at its repo's latest GitHub release.

For every formula whose `url` is a release download of the form
  https://github.com/<owner>/<repo>/releases/download/v<X>/<name>-<X>.tar.gz
it asks the GitHub API for <owner>/<repo>'s latest (non-draft, non-prerelease) release, and if
that release carries an asset named <name>-<new>.tar.gz, rewrites `url` and `sha256` to it.
For source-build formulas whose `url` is a tag archive of the form
  https://github.com/<owner>/<repo>/archive/refs/tags/v<X>.tar.gz
it rewrites `url`/`sha256` to the latest release's tag archive (refs/heads/... never matches).
The sha256 is computed from the downloaded bytes, never trusted from anywhere else. Formulas
that match neither pattern are left alone and reported.

Usage:
  bump_formulas.py [--dry-run] [--formula NAME] [--tap-dir DIR]
  bump_formulas.py --help

Options:
  --dry-run       report what would change; write nothing
  --formula NAME  only this formula (file stem, e.g. free-agents); repeatable
  --tap-dir DIR   tap checkout root (default: the repo this script lives in)

Environment:
  GITHUB_TOKEN    optional; raises the API rate limit (Actions provides it)

Exit status: 0 = ran (changed or not), 1 = an error for at least one formula, 2 = bad usage.
Prints one line per formula; with changes it also prints `changed=<names>` last, for the workflow.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

URL_RE = re.compile(
    r'^(\s*url\s+")https://github\.com/(?P<owner>[^/]+)/(?P<repo>[^/]+)/releases/download/'
    r'v(?P<ver>[0-9][0-9A-Za-z.\-]*)/(?P<name>[A-Za-z0-9_.\-]+?)-(?P=ver)\.tar\.gz(")', re.M)
# Source-build formulas point at the git tag's archive instead of a release asset.
# refs/heads/... is deliberately NOT matched — only version tags.
ARCHIVE_URL_RE = re.compile(
    r'^(\s*url\s+")https://github\.com/(?P<owner>[^/]+)/(?P<repo>[^/]+)/archive/refs/tags/'
    r'v(?P<ver>[0-9][0-9A-Za-z.\-]*)\.tar\.gz(?P<quote>")', re.M)
SHA_RE = re.compile(r'^(\s*sha256\s+")[0-9a-f]{64}(")', re.M)


def _get(url: str, accept: str = "application/vnd.github+json") -> bytes:
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "homebrew-tap-bump"})
    tok = os.environ.get("GITHUB_TOKEN")
    if tok and url.startswith("https://api.github.com/"):
        req.add_header("Authorization", f"Bearer {tok}")
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def latest_release(owner: str, repo: str) -> dict:
    return json.loads(_get(f"https://api.github.com/repos/{owner}/{repo}/releases/latest"))


def bump(path: Path, dry_run: bool, get=_get, latest=latest_release) -> tuple[str, bool]:
    """Return (report line, changed?). `get`/`latest` are injectable for tests."""
    text = path.read_text()
    m = URL_RE.search(text)
    mm = m or ARCHIVE_URL_RE.search(text)
    if mm is None:
        return f"{path.stem}: skipped (url is not a GitHub release tarball or tag source archive)", False
    if len(SHA_RE.findall(text)) != 1:
        return f"{path.stem}: ERROR expected exactly one sha256 line", False
    owner, repo, cur = mm["owner"], mm["repo"], mm["ver"]
    rel = latest(owner, repo)
    tag = rel.get("tag_name", "")
    new = tag[1:] if tag.startswith("v") else tag
    if not re.fullmatch(r"[0-9][0-9A-Za-z.\-]*", new or ""):
        return f"{path.stem}: ERROR latest release tag {tag!r} is not a version", False
    if new == cur:
        return f"{path.stem}: up to date ({new})", False
    if m:
        asset = f"{m['name']}-{new}.tar.gz"
        hit = next((a for a in rel.get("assets", []) if a.get("name") == asset), None)
        if hit is None:
            return f"{path.stem}: ERROR release {tag} has no asset {asset}", False
        url = f"https://github.com/{owner}/{repo}/releases/download/{tag}/{asset}"
        sha = hashlib.sha256(get(hit["browser_download_url"], "application/octet-stream")).hexdigest()
        out = URL_RE.sub(lambda mm: f"{mm.group(1)}{url}{mm.group(6)}", text, count=1)
    else:
        # source archive of the tag: always exists for a published tag, no asset check
        url = f"https://github.com/{owner}/{repo}/archive/refs/tags/{tag}.tar.gz"
        sha = hashlib.sha256(get(url, "application/octet-stream")).hexdigest()
        # group("quote") is the closing quote — group(4) is `ver`; using it mangled
        # the url line into `...vX.tar.gz<old-ver>` with no closing quote (2026-11-08,
        # pinned by the exact-line assertion in test_bump_formulas.py).
        out = ARCHIVE_URL_RE.sub(lambda mm: f"{mm.group(1)}{url}{mm.group('quote')}", text, count=1)
    out = SHA_RE.sub(lambda mm: f"{mm.group(1)}{sha}{mm.group(2)}", out, count=1)
    if not dry_run:
        path.write_text(out)
    return f"{path.stem}: {cur} -> {new} (sha256 {sha[:12]}…){' [dry-run]' if dry_run else ''}", True


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("-h", "--help", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--formula", action="append", default=[])
    ap.add_argument("--tap-dir", default=str(Path(__file__).resolve().parents[2]))
    try:
        a = ap.parse_args(argv)
    except SystemExit:
        print("usage: bump_formulas.py [--dry-run] [--formula NAME] [--tap-dir DIR] (see --help)", file=sys.stderr)
        return 2
    if a.help:
        print((__doc__ or "").strip())
        return 0
    files = sorted(Path(a.tap_dir, "Formula").glob("*.rb"))
    if a.formula:
        files = [f for f in files if f.stem in a.formula]
        missing = set(a.formula) - {f.stem for f in files}
        if missing:
            print(f"no such formula: {', '.join(sorted(missing))}", file=sys.stderr)
            return 2
    changed, failed = [], False
    for f in files:
        try:
            line, did = bump(f, a.dry_run)
        except Exception as exc:  # network / API: report per formula, keep going
            line, did = f"{f.stem}: ERROR {type(exc).__name__}: {exc}", False
        failed |= "ERROR" in line
        print(line)
        if did:
            changed.append(f.stem)
    if changed:
        print("changed=" + ",".join(changed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
