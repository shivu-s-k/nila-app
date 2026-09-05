#!/usr/bin/env bash
#
# Simulate the GitHub Actions run locally, against the current commit.
#
# The workflow in .github/workflows/ci.yml calls the same `make` targets in the
# same order, so this is the same gate -- just without pushing anywhere.
#
#   ./scripts/simulate-ci.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Not a git repository -- nothing to validate."
    exit 1
fi

COMMIT=$(git rev-parse --short HEAD)
SUBJECT=$(git log -1 --pretty=%s)
BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "=============================================="
echo " Simulating: MyTemplate CI"
echo "  branch  ${BRANCH}"
echo "  commit  ${COMMIT}  ${SUBJECT}"
echo "=============================================="
echo

if [ -n "$(git status --porcelain)" ]; then
    echo "Note: working tree has uncommitted changes; validating them as-is."
    echo
fi

START=$(date +%s)
if make ci; then
    echo
    echo "PASS  ($(( $(date +%s) - START ))s)  reports/ has the artifacts."
else
    STATUS=$?
    echo
    echo "FAIL  the gate rejected ${COMMIT}. See reports/ for details."
    exit "${STATUS}"
fi
