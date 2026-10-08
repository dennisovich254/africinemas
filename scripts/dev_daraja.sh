#!/usr/bin/env bash
# The app with real M-Pesa (Safaricom's sandbox), for the manual journey in
# docs/runbooks/daraja-sandbox.md. Loads the filled-in settings from .env (an empty
# line never blanks one out), and needs DARAJA_CALLBACK_BASE to be the current tunnel.
# Serves the built app on :8000 (no Vite dev server, so no hot reload): Vite's dev
# server refuses requests for hosts it doesn't know ("Blocked request. This host ... is
# not allowed"), which would block Safaricom's callback and phones through the tunnel.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck disable=SC1091
. scripts/load_env.sh
export AFRICINEMAS_PAYMENTS=daraja
echo "M-Pesa callbacks go to: ${DARAJA_CALLBACK_BASE:-<not set: see the runbook, step 3>}/hooks/mpesa/..."
exec jac run --no-dev --port 8000 "$@"
