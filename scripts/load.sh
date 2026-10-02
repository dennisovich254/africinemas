#!/usr/bin/env bash
# Seat-hold load test (plan P4.7, spike S5; ADR-0014). Not part of the test suite: it
# boots a real server and sends hundreds of holds at once, which takes a few minutes
# and most of a small machine. Results land in load/artifacts/s5-*.json (git-ignored).
#   scripts/load.sh                  both scenarios, 200 visitors each
#   LOAD_VISITORS=50 scripts/load.sh a lighter run
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p load/artifacts
status=0
JAC_TEST_STRICT=1 JAC_TEST_JOBS=1 jac test load/hold_load_tests.jac -v "$@" || status=$?
if [[ "${JAC_KEEP_TEST_DBS:-}" != "1" ]]; then
    jac db prune -y > /dev/null 2>&1 || true
fi
exit "$status"
