# JI-015: `${VAR}` and `${VAR:?msg}` keep the literal text when the variable is unset

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P0.7. **Counter-checked** the same day against real servers, with a token-forgery test.
- **Status:** open (high: secrets referenced this way become published strings)

## Docs vs behaviour
The config reference says `${VAR}` means "Use variable (error if not set)" and `${VAR:?error}` means
"Custom error if not set". In practice both **silently keep the literal placeholder text**.
`${VAR:-default}` works as documented.

## Root cause (source)
`interpolate_env_vars()` (`jaclang/project/impl/config.impl.jac`) **does raise** `ValueError` for
an unset `${VAR}` / `${VAR:?msg}`, as documented. But the config loader calls it through
`_interpolate_recursive()`, which catches that error and returns the original string:
```jac
impl _interpolate_recursive(`obj: any) -> any {
    if isinstance(`obj, str) {
        try { return interpolate_env_vars(`obj); }
        except ValueError { return `obj; }     # <- documented error swallowed; literal kept
    } ...
```
`_parse_toml_data()` runs every `jac.toml` value through `_interpolate_recursive`.

## Evidence
**Config API / CLI** (isolated project): an unset `${NOT_SET_PLAIN}` and `${NOT_SET:?msg}` resolve to their
literal text, in a base section and in a profile, and `jac config get` shows the literal.

**Real servers** (`jac run`, fresh project database each, `JAC_SERVE_AUTH_SECRET` unset):

| `[serve.auth] secret =` | Env | Registration token signed with… |
| --- | --- | --- |
| `"${AFRI_UNSET_SECRET:?must be set}"` | unset | the **literal string** `${AFRI_UNSET_SECRET:?must be set}` ✔ verifies |
| `"${AFRI_UNSET_SECRET}"` | unset | the **literal string** `${AFRI_UNSET_SECRET}` ✔ verifies |
| `"${AFRI_SET_SECRET:?must be set}"` | set | the env value (correct) |
| `"${AFRI_UNSET_SECRET:-fallback-secret}"` | unset | `fallback-secret` (correct) |

Control: the same verifier with a wrong key reports "does not verify".

**Token forgery, end to end:** using only the literal placeholder text as the HMAC key, I minted a
JWT for another registered user (`bob`: `sub`/`user_id` set to bob's id). `GET /user/me` with the
forged token returned **bob's account** (same `user_id`). The same token with a corrupted signature → `401`.

**Admin password:** `[scale.admin] default_password = "${AFRI_UNSET_PW:?admin password required}"`
(unset) → the bootstrap admin's password is the **literal placeholder**: logging in as `admin` with that
exact string succeeds (`changeme` is refused).

## Why it matters
A committed `jac.toml` that *looks* safe (it refuses to run without the secret) instead runs with a
password or signing key that anyone who can read the repo knows. With `[serve.auth] secret`, anyone can
**impersonate any user whose id they know**.

## Workaround (in place)
No required-variable interpolation in `jac.toml`. Secrets come only from environment variables that the
runtime reads directly (`JAC_SERVE_AUTH_SECRET`); if it's unset, Jac mints a random per-project secret.
The built-in admin bootstrap is disabled in production. `tests/unit/config_tests.jac` fails if `jac.toml`
contains `${VAR}` or `${VAR:?…}` without a default.

## Possible improvement (suggestion)
Let the documented `ValueError` propagate from `_interpolate_recursive` (at least for `:?`), or refuse
to start when a security-relevant setting (`serve.auth.secret`, `scale.admin.default_password`) still
contains an unresolved `${…}` placeholder.
