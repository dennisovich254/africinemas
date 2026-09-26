#!/usr/bin/env bash
# `jac check --lint` exits 0 even when it reports violations (docs/jac-issues/JI-010),
# so fail ourselves when any finding (⚠) or error (✖) is printed.
# Usage: scripts/jac_lint.sh [paths...]   (defaults to the whole project)
set -uo pipefail
out="$(jac check --lint "${@:-.}" 2>&1)"; rc=$?
printf '%s\n' "$out"
if (( rc != 0 )) || grep -qE '^(⚠|✖)' <<<"$out"; then
    echo "jac lint: violations found (try: jac check --lint --fix <file>)" >&2
    exit 1
fi
