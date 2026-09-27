# Contributing to AfriCinemas

AfriCinemas is built in [Jac](https://www.jaseci.org/) following `docs/IMPLEMENTATION_PLAN.md`,
one sub-phase at a time, test-first.

## One-time setup

```bash
scripts/install_jac.sh          # the Jac version pinned in .jac-version, checksum-verified
scripts/install_gitleaks.sh     # secret scanner used by the pre-commit hook
scripts/install_actionlint.sh   # GitHub Actions linter used by the pre-commit hook
uv tool install pre-commit      # or: pipx install pre-commit
pre-commit install              # installs the pre-commit, commit-msg and pre-push hooks
jac install                     # project dependencies (Python + npm)
cp .env.example .env            # then fill in the values you need
scripts/doctor.sh               # must end with "All checks passed."
```

If `jac install` fails with "bun install failed" on an older CPU, see `docs/jac-issues/JI-002`
(set `JAC_BUN` to bun's baseline build). `scripts/doctor.sh` detects this.

## The workflow: one sub-phase = one PR

1. **Branch:** `git switch -c feat/p<phase>.<sub>-<slug>` (e.g. `feat/p4.3-seat-holds`).
2. **RED:** write the tests listed for the sub-phase in the plan. Run `scripts/test.sh` and confirm
   they fail for the right reason. Commit them, e.g. `test(p4.3): seat hold concurrency`.
3. **GREEN:** implement the minimum to make them pass, with no regressions.
4. **Refactor** with the tests green.
5. **Push and open a PR.** The pre-push hook runs the type-check ratchet and the full test suite;
   CI must pass all required checks.
6. **Squash-merge** into `main`, delete the branch, tick the plan checkbox. Then start the next sub-phase.

Run tests with `scripts/test.sh` (not bare `jac test`): it turns on strict mode, so a broken import
fails instead of being silently skipped (`docs/jac-issues/JI-001`).

## Commits and PR titles

[Conventional Commits](https://www.conventionalcommits.org/) are enforced by a commit-msg hook and
the `pr-title` check: `feat|fix|test|refactor|docs|chore|ci|style|perf|build|revert(scope): summary`.
The PR title becomes the squash commit on `main`.

## Quality gates

| When | What runs |
| --- | --- |
| every commit | formatting, `jac fmt --check`, lint (`scripts/jac_lint.sh`), YAML/TOML/JSON checks, private keys, gitleaks, actionlint, no commits to `main` |
| every commit message | Conventional Commits |
| every push | `scripts/check_warnings.sh` (0 errors; warnings ≤ `.jac-warnings-baseline`) and `scripts/test.sh` |
| every PR | the CI checks in `.github/workflows/ci.yml` (required to merge) |

`scripts/hooks_selftest.sh` proves each local gate rejects bad input and accepts clean input.
`scripts/check_governance.sh` checks these repository files.

## Found a problem in Jac itself?

Log it in `docs/jac-issues/` (verified, with version, repro and workaround); see its README.

## Security

Never commit secrets: `.env` is git-ignored, and hooks plus CI scan for leaks. To report a
vulnerability, see `SECURITY.md`.
