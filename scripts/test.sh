#!/usr/bin/env bash
# Run the Jac test suite the way CI and the pre-push hook do.
#   - JAC_TEST_STRICT=1: a test file whose import fails is an ERROR, never a silent skip
#     (without it, jac test can mistake a missing local module for an optional dependency).
#   - One worker locally (the dev box has ~2.3 GB RAM); CI (CI=true) uses one per core.
# Extra arguments are passed to `jac test`, e.g. scripts/test.sh tests/unit -v
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export JAC_TEST_STRICT=1
if [[ -z "${JAC_TEST_JOBS:-}" ]]; then
    if [[ "${CI:-}" == "true" ]]; then export JAC_TEST_JOBS=auto; else export JAC_TEST_JOBS=1; fi
fi

exec jac test "$@"
