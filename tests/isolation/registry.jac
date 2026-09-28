"""The tenant-isolation registry (plan §2.3): every endpoint the app serves, and its scope.

- "public": needs no login and returns no tenant data.
- "caller": works on the caller's own data only (no tenant selector).
- "tenant": takes a tenant selector; `probe` is a request body aimed at tenant B, with
  "{tenant}" standing for B's slug.

isolation_tests.jac fails when the app serves an endpoint that isn't listed here, so no
new endpoint can skip the cross-tenant checks.
"""

glob REGISTRY: dict[str, dict[str, any]] = {  # jac:ignore[W1037]
         "app_info": {"scope": "public"},
         "create_cinema": {"scope": "caller"},
         "my_cinemas": {"scope": "caller"},
         "my_access": {"scope": "tenant", "probe": {"tenant": "{tenant}"}},
         "rename_cinema": {
             "scope": "tenant",
             "probe": {"tenant": "{tenant}", "name": "Probe"}
         }
     };
