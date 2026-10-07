#!/usr/bin/env bash
# Checks the Daraja adapter against Safaricom's real sandbox (plan P5.7): login, a KES 1
# STK push to DARAJA_TEST_PHONE, and its status query. Loads .env if present (never
# committed); the test skips itself when a setting is missing.
#   scripts/sandbox.sh                   run the check
#   DARAJA_RECORD=1 scripts/sandbox.sh   also save Safaricom's replies (redacted) to
#                                        tests/fixtures/daraja/recorded/
# The full journey, a real payment producing a ticket, is manual:
# docs/runbooks/daraja-sandbox.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi
status=0
rm -f sandbox/artifacts/last_run.txt
JAC_TEST_STRICT=1 jac test sandbox/daraja_sandbox_tests.jac -v "$@" || status=$?
if [[ -f sandbox/artifacts/last_run.txt ]]; then
    echo "Safaricom's answer: $(cat sandbox/artifacts/last_run.txt)"
fi
exit "$status"
