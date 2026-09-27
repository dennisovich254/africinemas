#!/usr/bin/env bash
# Type-check the whole workspace. Fails on any error, and on more warnings than the
# committed baseline (.jac-warnings-baseline). The count may only go down.
#   scripts/check_warnings.sh            check against the baseline
#   scripts/check_warnings.sh --update   write the current count as the new baseline
#   WARNING_BASELINE=N ...               override the baseline (used by the hook self-test)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
BASELINE_FILE=.jac-warnings-baseline

out="$(jac check 2>&1)"; rc=$?
count="$(grep -c '^⚠' <<<"$out")"

if (( rc != 0 )); then
    grep -E '^✖|error\[' <<<"$out" | head -20
    echo "jac check: errors found (see above)." >&2
    exit 1
fi

if [[ "${1:-}" == "--update" ]]; then
    echo "$count" > "$BASELINE_FILE"; echo "Baseline set to $count warning(s)."; exit 0
fi

baseline="${WARNING_BASELINE:-$(tr -d '[:space:]' < "$BASELINE_FILE" 2>/dev/null)}"
baseline="${baseline:-0}"
if (( count > baseline )); then
    echo "jac check: $count warnings, baseline is $baseline. New warnings were introduced." >&2
    echo "Warnings by file and code:" >&2
    awk '/^⚠/ { match($0, /\[[A-Z][0-9]+\]/); code = substr($0, RSTART + 1, RLENGTH - 2) }
         /^ *-->/ { sub(/^ *--> */, ""); sub(/:[0-9]+:[0-9]+$/, ""); if (code != "") print code "  " $0; code = "" }' \
        <<<"$out" | sort | uniq -c | sort -rn >&2
    exit 1
elif (( count < baseline )); then
    echo "jac check: $count warnings (baseline $baseline). Nice! Lock it in: scripts/check_warnings.sh --update"
else
    echo "jac check: 0 errors, $count warnings (= baseline)."
fi
