# JI-010: `jac check --lint` exits 0 when it reports lint violations

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-26, P0.4
- **Status:** open (may be intended, since lint findings are warnings)

## Behaviour
| Command | Output | Exit |
| --- | --- | --- |
| `jac check --lint lintbad.jac` (`def f() -> int`) | `⚠ … Empty parentheses can be removed [remove-empty-parens]` | **0** |
| `jac check --lint clean.jac` | `0 errors found` | 0 |
| `jac fmt --check fmtbad.jac` | `✖ not properly formatted` | 1 |
| `jac check typeerr.jac` | `✖ error[E1002]` | 1 |

`jac check --help` has `-n/--nowarn` (suppress output) but no "treat warnings as errors" option, and `[check.lint]` only selects rules. So a pre-commit/CI step that calls `jac check --lint` directly would never block a lint violation.

## Workaround (in place)
`scripts/jac_lint.sh` runs `jac check --lint` and fails when the output contains any `⚠` finding.

## Possible improvement (suggestion)
A `--strict`/`--warnings-as-errors` flag, or a `[check.lint] fail_on = "warning"` setting.
