#!/usr/bin/env bash
# Run the Jac test suite the way CI and the pre-push hook do.
#   - JAC_TEST_STRICT=1: a test file whose import fails is an ERROR, never a silent skip
#     (without it, jac test can mistake a missing local module for an optional dependency).
#   - One worker, locally and on CI. Parallel workers each start the shared embedded
#     Postgres at the same moment, and on CI that intermittently failed every test file
#     with "postgres not ready after 60.0s: No such file or directory" (main run
#     36341715355). The dev box also has only ~2.3 GB RAM. Override with JAC_TEST_JOBS.
# Extra arguments are passed to `jac test`, e.g. scripts/test.sh tests/unit -v
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export JAC_TEST_STRICT=1
export JAC_TEST_JOBS="${JAC_TEST_JOBS:-1}"

exec jac test "$@"
