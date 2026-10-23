#!/usr/bin/env bash
# Checks that AfriCinemas' three sites answer on their addresses (plan 13.1b.d; ADR-0057):
# the back office on the domain, the platform on admin.<domain>, a cinema's storefront on
# <slug>.<domain>, and an address that's no cinema's as no site. Each address is asked,
# over its own URL, which site it is (site_for_host), so DNS, the certificate and the
# proxy's Host header are all checked on the way.
#   scripts/check_sites.sh africinemas.co.ke anga      after a deploy
#   scripts/check_sites.sh localhost:8000 anga         a dev server (http on *.localhost)
# The slug is optional: without it, the storefront check is skipped.
set -uo pipefail
domain="${1:?usage: scripts/check_sites.sh <domain> [cinema-slug]}"
slug="${2:-}"
case "${domain%%:*}" in
    localhost|*.localhost) scheme=http ;;
    *) scheme=https ;;
esac
failed=0

check() {
    # check <host> <wanted site> [wanted slug]
    local host="$1" wanted="$2" wanted_slug="${3:-}" body site got_slug
    body="$(curl -sS --max-time 20 -X POST -H 'Content-Type: application/json' \
        -d "{\"host\": \"$host\"}" "$scheme://$host/function/site_for_host" 2>&1)" || {
        echo "FAIL $host: no answer ($body)"; failed=1; return; }
    site="$(sed -nE 's/.*"site": *"([a-z]*)".*/\1/p' <<<"$body")"
    got_slug="$(sed -nE 's/.*"slug": *"([a-z0-9-]*)".*/\1/p' <<<"$body")"
    if [[ "$site" == "$wanted" && "$got_slug" == "$wanted_slug" ]]; then
        echo "ok   $host: $site${got_slug:+ ($got_slug)}"
    else
        echo "FAIL $host: wanted $wanted${wanted_slug:+ ($wanted_slug)}, got ${site:-?}${got_slug:+ ($got_slug)}: ${body:0:200}"
        failed=1
    fi
}

check "$domain" main
check "admin.$domain" platform
if [[ -n "$slug" ]]; then
    check "$slug.$domain" storefront "$slug"
fi
check "no-such-cinema-$RANDOM.$domain" none
exit "$failed"
