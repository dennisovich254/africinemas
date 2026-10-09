#!/usr/bin/env bash
# Builds and serves the app for the browser tests, once, in the foreground (Ctrl-C stops
# it). Then, in another terminal, run tests one at a time against it:
#   E2E_BASE_URL=http://127.0.0.1:8870 scripts/e2e.sh e2e/x_tests.jac -t <test_name>
# so each run skips the build. Same settings as scripts/e2e.sh (scripts/e2e_env.sh),
# including a scratch database that's dropped when this server stops.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p e2e/artifacts
source scripts/e2e_env.sh
port="${E2E_PORT:-8870}"
echo "Building and serving the app on :$port (production bundle). Ready when /healthz answers."
# Not exec: the trap deletes the run's test posters when the server stops. Its scratch
# database is dropped by Jac itself (scripts/e2e_env.sh).
trap 'rm -rf "$E2E_MEDIA_DIR"' EXIT
jac run --no-dev --port "$port" < /dev/null
