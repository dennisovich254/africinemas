# JI-011: A fresh binary's first `jac --version` prints runtime-extraction lines to stdout

- **Version:** jaclang 0.37.18 (`jac-0.37.18-linux-x86_64`, sha256 `ead9f12e…134ee`)
- **Found:** 2026-09-27, P0.5
- **Status:** open (low)

## Behaviour
The first invocation of a newly downloaded `jac` binary (fresh runtime cache) prints one-time setup
messages ("first … runtime … reading … verifying … extracting … one-time …") on **stdout** before the
`jac 0.37.18` line. `$(jac --version | awk '{print $2}')` then captures several words instead of the version.
Later runs print only the version line.

## Workaround (in place)
`scripts/install_jac.sh` keeps only the `^jac [0-9]` line: `jac --version | grep -E '^jac [0-9]' | awk '{print $2}'`.

## Possible improvement (suggestion)
Send progress messages to stderr so `--version` output stays machine-parseable.
