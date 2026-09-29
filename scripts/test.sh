#!/usr/bin/env bash
# Run the Jac test suite the way CI and the pre-push hook do.
#   - JAC_TEST_STRICT=1: a test file whose import fails is an ERROR, never a silent skip
#     (without it, jac test can mistake a missing local module for an optional dependency).
#   - One worker, locally and on CI. Parallel workers each start the shared embedded
#     Postgres at the same moment, and on CI that intermittently failed every test file
#     with "postgres not ready after 60.0s: No such file or directory" (main run
#     36341715355). The dev box also has only ~2.3 GB RAM. Override with JAC_TEST_JOBS.
# Extra arguments are passed to `jac test`, e.g. scripts/test.sh tests/unit -v
#   scripts/test.sh --quick   the fast tier only (unit, isolation, API smoke; a few minutes):
#                             what the pre-push hook runs. CI runs the full suite on every
#                             PR, including the integration and real-server tests, and a
#                             PR can't merge until it passes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export JAC_TEST_STRICT=1
export JAC_TEST_JOBS="${JAC_TEST_JOBS:-1}"

status=0
if [[ "${1:-}" == "--quick" ]]; then
    shift
    # One folder per run: `jac test` takes a single -d folder, and its -i doesn't exclude
    # folders from a -d tests run.
    for dir in tests/unit tests/isolation tests/api; do
        jac test -d "$dir" "$@" || status=$?
    done
else
    jac test "$@" || status=$?
fi

# Every in-process test app gets its own embedded-Postgres database, keyed by a temp
# folder that the test deletes afterwards. Drop those orphaned databases, pass or fail,
# or they pile up on disk (~8 MB each; 800 of them had reached 6 GB). `prune` only
# drops databases whose folder is gone. JAC_KEEP_TEST_DBS=1 keeps them for debugging.
if [[ "${JAC_KEEP_TEST_DBS:-}" != "1" ]]; then
    jac db prune -y > /dev/null 2>&1 || echo "note: jac db prune failed" >&2
fi
exit "$status"
