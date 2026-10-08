#!/usr/bin/env bash
# Start the shared embedded Postgres and wait until it answers, before any test needs
# it. On a fresh CI runner its first start (download and initdb) can take longer than
# the 60 s a test file waits, which failed the first files of a shard with "postgres not
# ready after 60.0s: No such file or directory". Once it's up, every test finds it ready.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
jac db fetch > /dev/null 2>&1 || true
for attempt in $(seq 1 10); do
    if jac db sql "SELECT 1" > /dev/null 2>&1; then
        echo "Postgres is ready (attempt $attempt)"
        exit 0
    fi
    echo "Postgres not ready yet (attempt $attempt of 10); waiting..."
    sleep 20
done
echo "Postgres never became ready" >&2
exit 1
