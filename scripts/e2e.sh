#!/usr/bin/env bash
# End-to-end browser tests (plan P0.8b). Builds and serves the production bundle, runs the
# Playwright tests in e2e/ against it, and always stops the server.
#   scripts/e2e.sh                 build + serve on $E2E_PORT (default 8870), then test
#   scripts/e2e.sh e2e/x_tests.jac  the same, running only the given test file(s)
#   E2E_BASE_URL=http://... ...    test an already-running server instead
#   scripts/e2e.sh e2e/x_tests.jac -t <name>   one test (with scripts/e2e_server.sh
#                                  running, set E2E_BASE_URL to skip the build)
# Screenshots and the server log land in e2e/artifacts/ (git-ignored).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p e2e/artifacts

# The test settings the server and the tests share (scripts/e2e_env.sh).
source scripts/e2e_env.sh

server_pid=""
cleanup() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    # Drop test databases whose folder is gone (see scripts/test.sh).
    # Only when this script started the server: a server from scripts/e2e_server.sh
    # keeps its databases until it stops.
    if [[ -n "$server_pid" && "${JAC_KEEP_TEST_DBS:-}" != "1" ]]; then
        jac db prune -y > /dev/null 2>&1 || true
    fi
    # The run's test posters (scripts/e2e_env.sh).
    rm -rf "$E2E_MEDIA_DIR"
}
trap cleanup EXIT

if [[ -z "${E2E_BASE_URL:-}" ]]; then
    port="${E2E_PORT:-8870}"
    echo "Building and serving the app on :$port (production bundle, no dev server)..."
    jac run --no-dev --port "$port" < /dev/null > e2e/artifacts/server.log 2>&1 &
    server_pid=$!
    # Up to 10 minutes: the first build of the client bundle takes about 6 on a small machine.
    for _ in $(seq 1 300); do
        if curl -sf -o /dev/null "http://127.0.0.1:$port/healthz"; then break; fi
        if ! kill -0 "$server_pid" 2>/dev/null; then
            echo "server exited early; log:" >&2; tail -40 e2e/artifacts/server.log >&2; exit 1
        fi
        sleep 2
    done
    curl -sf -o /dev/null "http://127.0.0.1:$port/healthz" || { echo "server did not become healthy" >&2; tail -40 e2e/artifacts/server.log >&2; exit 1; }
    export E2E_BASE_URL="http://127.0.0.1:$port"
fi

# With test files as arguments (scripts/e2e.sh e2e/branding_tests.jac), run only those.
if [[ $# -gt 0 && "$1" == *.jac ]]; then
    JAC_TEST_STRICT=1 JAC_TEST_JOBS="${JAC_TEST_JOBS:-1}" jac test "$@"
else
    JAC_TEST_STRICT=1 JAC_TEST_JOBS="${JAC_TEST_JOBS:-1}" jac test -d e2e "$@"
fi
