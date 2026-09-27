# JI-015: `${VAR}` and `${VAR:?msg}` keep the literal text when the variable is unset

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P0.7
- **Status:** open (high for secrets)

## Docs vs behaviour
The config reference says: `${VAR}` means "Use variable (error if not set)", and `${VAR:?error}` means "Custom error if not set".
Observed with `JacConfig.resolve()` (a base section and a profile overlay behave the same) and `jac config get`:

| jac.toml | VAR unset → resolved value |
| --- | --- |
| `host = "${NOT_SET_PLAIN}"` | `'${NOT_SET_PLAIN}'` (no error) |
| `host = "${NOT_SET:?base var missing}"` | `'${NOT_SET:?base var missing}'` (no error) |
| `session = "${NOT_SET:-fallback}"` | `'fallback'` (correct) |

## Why it matters
`secret = "${JAC_SERVE_AUTH_SECRET:?…}"` in a committed `jac.toml` would, if the variable were missing, make the JWT signing secret the **published literal string**, so anyone could forge tokens. The same goes for `[scale.admin] default_password`. The config looks safe but isn't.

## Workaround (in place)
No required-variable interpolation in `jac.toml`. Secrets come only from environment variables the runtime reads directly (`JAC_SERVE_AUTH_SECRET`), and the built-in admin bootstrap is disabled in production. `tests/unit/config_tests.jac` fails if `jac.toml` contains `${VAR}` or `${VAR:?…}` without a default.

## Possible improvement (suggestion)
Raise a clear error at config resolution, as documented, or at least log a warning when a placeholder stays unresolved.
