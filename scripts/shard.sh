#!/usr/bin/env bash
# Run one CI shard of a test suite: its share of the test files, so the shards can run
# side by side on separate runners (each with its own Postgres).
#   scripts/shard.sh test <index> <count> [jac test args]   e.g. scripts/shard.sh test 0 3 -v
#   scripts/shard.sh e2e  <index> <count> [jac test args]
# Files are dealt out in turn, the slowest first (tests that boot a real server, or for
# e2e the screenshot reviews), so each shard gets a fair share of them. Every file runs
# in exactly one shard.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
suite="$1"; index="$2"; count="$3"; shift 3

case "$suite" in
    test) all=$(find tests -name '*_tests.jac' | sort); slow_pattern='RealServer|real_server' ;;
    e2e)  all=$(find e2e -maxdepth 1 -name '*_tests.jac' | sort); slow_pattern='review screenshots' ;;
    *) echo "unknown suite: $suite (test or e2e)" >&2; exit 2 ;;
esac
slow=$(grep -lE "$slow_pattern" $all | sort || true)
rest=$(comm -23 <(printf '%s\n' $all) <(printf '%s\n' $slow))

files=()
i=0
for f in $slow $rest; do
    if (( i % count == index )); then
        files+=("$f")
    fi
    i=$((i + 1))
done
echo "shard $index of $count: ${#files[@]} files"
printf '  %s\n' "${files[@]}"

if [[ "$suite" == test ]]; then
    exec scripts/test.sh "${files[@]}" "$@"
fi
exec scripts/e2e.sh "${files[@]}" "$@"
