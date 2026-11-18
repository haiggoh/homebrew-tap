#!/usr/bin/env bash
# push_bump.sh — commit the Formula/ changes reported in a bump log and push to origin/main.
#
# The bump workflow checks out with fetch-depth: 1, and its concurrency group lets runs
# overlap (hourly schedule + workflow_dispatch + repository_dispatch), so origin/main may
# have moved since this checkout. A bare `git push` then fails with
# "! [rejected] main -> main (fetch first)" (actions run 44092258642). So: fetch, rebase
# our commit onto the current origin/main (dropping it when the same bump already landed
# and the rebase makes it empty), then push. A conflicting concurrent bump aborts the
# rebase and skips the push with a warning — the next run re-evaluates from fresh main.
#
# Usage:
#   push_bump.sh [--bump-log FILE] [-h | --help]
#
# Arguments:
#   --bump-log FILE  bump log to build the commit message from (default: bump.log)
#   -h, --help       print this help and exit without running any git command
#
# Environment:
#   none read. `origin` must already be configured with push credentials
#   (in CI: actions/checkout persist-credentials, the default).
#
# Exit status:
#   0  pushed, or cleanly skipped (concurrent run already pushed)
#   1  a git command failed
#   2  bad usage (unknown flag, missing bump log, no ' -> ' lines to commit)
set -euo pipefail

usage() {
  cat <<'EOF'
push_bump.sh — commit the Formula/ changes from a bump log and push to origin/main,
rebasing onto the current origin/main first so a concurrent bump run cannot reject
the push ("! [rejected] main -> main (fetch first)").

Usage: push_bump.sh [--bump-log FILE] [-h | --help]

  --bump-log FILE  bump log to build the commit message from (default: bump.log)
  -h, --help       print this help and exit without running any git command

Environment: none read. `origin` must already carry push credentials (CI: actions/checkout).
Exit status: 0 pushed / cleanly skipped, 1 git failure, 2 bad usage.
EOF
}

BUMP_LOG=bump.log
while [ $# -gt 0 ]; do
  case "$1" in
    --bump-log)
      if [ $# -lt 2 ]; then
        echo "push_bump.sh: --bump-log needs a file argument" >&2
        usage >&2
        exit 2
      fi
      BUMP_LOG=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "push_bump.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$BUMP_LOG" ]; then
  echo "push_bump.sh: bump log not found: $BUMP_LOG" >&2
  exit 2
fi
# grep exits 1 when there is no match; that only means an empty message, checked next.
msg=$(grep -E ' -> ' "$BUMP_LOG" | sed 's/ (sha256.*//' | paste -sd ';' - | sed 's/;/; /g' || true)
if [ -z "$msg" ]; then
  echo "push_bump.sh: no ' -> ' lines in $BUMP_LOG — nothing to commit" >&2
  exit 2
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add Formula/
git commit -m "bump: $msg" -m "Automated by .github/workflows/bump-formulas.yml"

# A concurrent run may have pushed since our fetch-depth:1 checkout; replay on top of it.
git fetch origin main
if ! git rebase --empty=drop origin/main; then
  git rebase --abort
  echo "::warning::origin/main moved with a conflicting bump; skipping this push (the next run re-evaluates from fresh main)"
  exit 0
fi
git push origin main
