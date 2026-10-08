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
