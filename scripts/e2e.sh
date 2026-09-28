#!/usr/bin/env bash
# End-to-end browser tests (plan P0.8b). Builds and serves the production bundle, runs the
# Playwright tests in e2e/ against it, and always stops the server.
#   scripts/e2e.sh                 build + serve on $E2E_PORT (default 8870), then test
#   E2E_BASE_URL=http://... ...    test an already-running server instead
# Screenshots and the server log land in e2e/artifacts/ (git-ignored).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p e2e/artifacts

server_pid=""
cleanup() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    # Drop test databases whose folder is gone (see scripts/test.sh).
    if [[ "${JAC_KEEP_TEST_DBS:-}" != "1" ]]; then
        jac db prune -y > /dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if [[ -z "${E2E_BASE_URL:-}" ]]; then
    port="${E2E_PORT:-8870}"
    echo "Building and serving the app on :$port (production bundle, no dev server)..."
    jac run --no-dev --port "$port" < /dev/null > e2e/artifacts/server.log 2>&1 &
    server_pid=$!
    for _ in $(seq 1 180); do
        if curl -sf -o /dev/null "http://127.0.0.1:$port/healthz"; then break; fi
        if ! kill -0 "$server_pid" 2>/dev/null; then
            echo "server exited early; log:" >&2; tail -40 e2e/artifacts/server.log >&2; exit 1
        fi
        sleep 2
    done
    curl -sf -o /dev/null "http://127.0.0.1:$port/healthz" || { echo "server did not become healthy" >&2; tail -40 e2e/artifacts/server.log >&2; exit 1; }
    export E2E_BASE_URL="http://127.0.0.1:$port"
fi

JAC_TEST_STRICT=1 JAC_TEST_JOBS="${JAC_TEST_JOBS:-1}" jac test -d e2e "$@"
