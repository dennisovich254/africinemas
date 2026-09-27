# JI-014: The running server ignores profile overrides for `[serve]` settings

- **Version:** jaclang 0.37.18 (`jac run`, service/workspace apps, embedded Postgres)
- **Found:** 2026-09-27, P0.7. **Corrected** the same day after testing real servers over HTTP.
- **Status:** open (high: production hardening can look configured while having no effect)

> **Correction:** the first version of this entry said a nested profile override "makes the
> server's settings loader crash" and that production "would most likely fail to start". That
> came from calling the config API directly. Real servers **start fine and silently ignore the
> profile's `[serve]` values**. Both findings are recorded below.

## 1. Real server: profile `[serve]` overrides have no effect
Throwaway project, `def:pub ping`, servers booted with `jac run`, probed with `curl`:

| Setting | Where it was set | Result |
| --- | --- | --- |
| `max_body_bytes = 5 MB` | `[environments.production.serve.limits]` + `--profile production` | 6 MB POST → **200** (ignored) |
| `max_body_bytes = 5 MB` | base `[serve.limits]` | 6 MB POST → **413** |
| `max_body_bytes = 5 MB` | env `JAC_SERVE_MAX_BODY_BYTES` | 6 MB POST → **413** |
| `docs_enabled = false` | `[environments.production.serve]` (top-level key) + `--profile production` | `/docs` → **200** (ignored) |
| `docs_enabled = false` | same, activated with `JAC_PROFILE=production` | `/docs` → **200** (ignored) |
| `docs_enabled = false` | base `[serve]` | `/docs` → **404** |
| `docs_enabled = false` | env `JAC_SERVE_DOCS=false` | `/docs` → **404** |
| `[scale.admin] enabled = false` | `[environments.production.scale.admin]` + `JAC_PROFILE=production` | admin not created, login refused ✅ (profiles **do** apply to `[scale.*]`) |

So for `[serve]`, only the base table and the `JAC_SERVE_*` environment variables take effect.

## 2. Config API: nested profile tables become partial dicts
`JacConfig.resolve(root, profile="production")` *does* apply the profile, but a nested override
(e.g. `[environments.production.serve.limits]`) replaces the typed `ServeLimitsConfig` with a
dict holding only the overridden keys (`{'max_body_bytes': 5242880}`). Passing that config to
`ServeSettings.load(config=…)` raises `AttributeError: 'dict' object has no attribute 'max_connections'`.
The running server evidently doesn't take this path, but any tooling or test that does will crash.

## Why it matters
A reader (or a test that uses the config API) sees production hardening in `jac.toml`, while the
deployed server runs with the defaults: public `/docs` and `/graph`, 100 MB bodies, 7-day tokens.

## Workaround (in place)
- **All** `[serve]` hardening lives in `deploy/production.env` as `JAC_SERVE_*` env vars
  (`JAC_SERVE_DOCS=false`, `JAC_SERVE_GRAPH=false`, `JAC_SERVE_AUTH_TOKEN_TTL_DAYS=1`, `JAC_SERVE_MAX_BODY_BYTES`).
- `jac.toml` has no `[environments.*.serve]` tables (a unit test enforces this). Profiles are used only for `[scale.*]`.
- `tests/integration/production_server_tests.jac` boots a real server with the production env and
  asserts over HTTP: `/docs`, `/openapi.json`, `/graph` → 404; 6 MB body → 413; `admin`/`changeme` refused.

## Possible improvement (suggestion)
Apply the active profile when the server builds its `[serve]` settings, and deep-merge profile
overlays into the typed config objects.
