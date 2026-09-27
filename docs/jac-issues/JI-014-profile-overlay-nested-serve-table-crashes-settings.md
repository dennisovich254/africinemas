# JI-014: A profile overriding a nested `[serve.*]` table makes the server's settings loader crash

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P0.7
- **Status:** open (high: would likely crash a production server at startup)

## Behaviour
With a profile such as:
```toml
[environments.production.serve.limits]
max_body_bytes = 5242880
[environments.production.serve.auth]
token_ttl_days = 1
```
`JacConfig.resolve(root, profile="production").serve.limits` is a plain **dict containing only the overridden keys** (`{'max_body_bytes': 5242880}`), not a `ServeLimitsConfig`. The other fields (`max_connections`, `backlog`, …, and for `auth`: `algorithm`, `password_hash_cost`, …) are gone. Without a profile these are proper typed objects.

The server's own loader then fails:
```text
ServeSettings.load(config=<production>)  ->  AttributeError: 'dict' object has no attribute 'max_connections'
ServeSettings.load(config=<development>) ->  OK
```
(`jaclang/server/impl/settings.impl.jac` reads `cfg.limits.max_connections`, `cfg.auth.secret`, … as attributes.) So I believe `jac run --profile production` would fail at startup. I verified this by calling `ServeSettings.load` directly, not with a full server boot.

Top-level scalar keys in a profile (`[environments.production.serve] docs_enabled = false`) work correctly.

## Workaround (in place)
Profiles only override top-level `[serve]` keys. Nested settings are set via the `JAC_SERVE_*` environment mirrors, which `ServeSettings.load` reads first (e.g. `JAC_SERVE_MAX_BODY_BYTES`, `JAC_SERVE_AUTH_TOKEN_TTL_DAYS`). These live in `deploy/production.env`.
`tests/unit/config_tests.jac` guards against re-introducing nested `[environments.*.serve.*]` tables.

## Possible improvement (suggestion)
Deep-merge profile overlays into the typed config objects instead of replacing them with partial dicts.
