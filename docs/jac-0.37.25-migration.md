# Jac 0.37.25 migration

The project previously targeted 0.37.18. Running it with 0.37.25 produced E5082
(client imports of private server functions) and E2086 (edges without endpoint types).
Both `.jac-version` and `jac.toml` now target 0.37.25.

## Endpoint exposure

Jac 0.37.25 uses explicit declarations:

- `def:pub`: an endpoint callable anonymously.
- `def:protect`: an endpoint requiring a valid session.
- Plain `def` and `def:priv`: internal functions, not HTTP/RPC endpoints.

Authenticated application endpoints and the authenticated test fixture endpoints
have been changed to `:protect`. Invitation acceptance also requires authentication:
its membership must attach to an identified caller, never the anonymous root.
Public catalog, guest checkout, and provider callback functions retain `:pub`.
Scheduled tasks remain plain functions; importing them registers their schedules
without making them HTTP endpoints.

Server placement pins control where code runs. They do not make private functions
accessible to browser imports. Existing historical ADRs and Jac issue reports describe
the older runtime; use the installed `jac guide jac-sv-endpoints` and
`jac guide jac-sv-auth` for current exposure rules.

## Typed edges

The production graph declares `MemberOf: Root --> StaffGroup` and
`ForTenant: StaffGroup --> Tenant`. Spike fixture edges also declare their existing
source/target types. These declarations describe the existing topology; no graph data
reset is required by this source change.

## Dependencies and development

Python packages use `[dependencies.pypi]` and `[dev-dependencies.pypi]` in `jac.toml`.
The existing local changes to those tables are preserved.

```bash
jac --version                       # expected: 0.37.25
jac install                         # when dependencies need installation
jac check --app web
scripts/test.sh tests/api/smoke_tests.jac -v
jac run --dev main.jac
```

The endpoint-default guard now recognizes `:protect`, so authenticated endpoints
remain covered by that regression check. Startup/authentication smoke coverage also
checks that invitation acceptance requires a session and scheduler functions are private.
Scheduled jobs are absent from OpenAPI; requests to their missing routes may return
404 or 405 when the web app's SPA fallback rejects POST.

This migration does not remove older runtime workarounds. Their ownership,
transaction, and protocol contracts need separate verification before removal.

The warning counter and lint wrapper recognize both legacy symbol-prefixed output
and 0.37.25 bracketed diagnostic prefixes, so the upgrade does not silently disable
their checks. The warning ratchet's detailed report also recognizes both formats,
including bracketed error output. The warning baseline is not increased by this migration.
