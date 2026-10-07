#!/usr/bin/env bash
# End-to-end browser tests (plan P0.8b). Builds and serves the production bundle, runs the
# Playwright tests in e2e/ against it, and always stops the server.
#   scripts/e2e.sh                 build + serve on $E2E_PORT (default 8870), then test
#   scripts/e2e.sh e2e/x_tests.jac  the same, running only the given test file(s)
#   E2E_BASE_URL=http://... ...    test an already-running server instead
# Screenshots and the server log land in e2e/artifacts/ (git-ignored).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p e2e/artifacts

# Payments in the browser tests (plan P5.6): the simulated M-Pesa (its test numbers fail,
# cancel or time out; any other number pays), and the resolver settling every 2 seconds
# with no wait, since the simulator sends no callbacks.
export AFRICINEMAS_PAYMENTS="${AFRICINEMAS_PAYMENTS:-simulator}"
export AFRICINEMAS_STUCK_SECONDS="${AFRICINEMAS_STUCK_SECONDS:-0}"
export AFRICINEMAS_RESOLVE_SECONDS="${AFRICINEMAS_RESOLVE_SECONDS:-2}"
# Tickets are signed (plan P6.1); a fixed key for test runs only.
export AFRICINEMAS_TICKET_KEY="${AFRICINEMAS_TICKET_KEY:-e2e-only-ticket-key-0123456789abcdef}"
# Ticket emails (plan P6.3): never sent for real; the server keeps them in an outbox
# beside the screenshots, and the mail job runs every 2 seconds.
unset AFRICINEMAS_SMTP_HOST
export AFRICINEMAS_OUTBOX_DIR="${AFRICINEMAS_OUTBOX_DIR:-$PWD/e2e/artifacts/outbox}"
export AFRICINEMAS_MAIL_SECONDS="${AFRICINEMAS_MAIL_SECONDS:-2}"

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
