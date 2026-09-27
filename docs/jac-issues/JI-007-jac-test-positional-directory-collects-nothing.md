# JI-007: `jac test <dir>` (positional) collects nothing; only `-d <dir>` works

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-26, P0.3
- **Status:** open

## Behaviour
`jac test --help` describes positional `paths` as "More test files or directories". But `jac test checks` printed `No tests ran (no test files collected)` and exited **5**, while `jac test -d checks` collected and ran the file. In a workspace, a bare `jac test` also collected nothing until `[test] directory = "tests"` was set.

## Workaround
Always use `-d <dir>`, and set `[test] directory` in `jac.toml` (done).
