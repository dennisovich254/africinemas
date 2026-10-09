#!/usr/bin/env bash
# The settings the browser tests run under (plan P0.8b), shared by scripts/e2e.sh and
# scripts/e2e_server.sh. Source it from the repository root.

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
# A throwaway database and media folder for each run, so test cinemas never reach the
# project's own data (2026-10-09; 626 had piled up). Jac gives the server a scratch
# database and drops it when the server exits; one left by a killed run is dropped at the
# next Jac start. Test posters go to a temporary folder the scripts delete afterwards.
export JAC_DB_SCRATCH="${JAC_DB_SCRATCH:-1}"
E2E_MEDIA_DIR="$(mktemp -d -t africinemas-e2e-media-XXXXXX)"
export AFRICINEMAS_MEDIA_DIR="$E2E_MEDIA_DIR"
# The storefront chat (P8.4) answers from a script the browser tests write, never the
# real model: no key, no cost (core/agent/agent.jac, SCRIPT_ENV).
export AFRICINEMAS_AGENT_SCRIPT="${AFRICINEMAS_AGENT_SCRIPT:-$PWD/e2e/artifacts/agent_script.json}"
