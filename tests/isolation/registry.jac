"""The tenant-isolation registry (plan §2.3): every endpoint the app serves, and its scope.

- "public": needs no login and returns no tenant data.
- "caller": works on the caller's own data only (no tenant selector); `probe`, when
  given, is the request body to call it with.
- "tenant": takes a tenant selector; `probe` is a request body aimed at tenant B, with
  "{tenant}" standing for B's slug.
- "customer": a storefront endpoint; anyone may use it at any cinema, but it only ever
  returns the caller's own customer data (never staff or other customers' data).

isolation_tests.jac fails when the app serves an endpoint that isn't listed here, so no
new endpoint can skip the cross-tenant checks.
"""

glob REGISTRY: dict[str, dict[str, any]] = {  # jac:ignore[W1037]
         "app_info": {"scope": "public"},
         "create_cinema": {"scope": "caller"},
         "my_cinemas": {"scope": "caller"},
         "check_slug": {"scope": "caller", "probe": {"slug": "free-name"}},
         "my_access": {"scope": "tenant", "probe": {"tenant": "{tenant}"}},
         "rename_cinema": {
             "scope": "tenant",
             "probe": {"tenant": "{tenant}", "name": "Probe"}
         },
         "invite_staff": {
             "scope": "tenant",
             "probe": {"tenant": "{tenant}", "role": "usher", "venue_id": ""}
         },
         "accept_invite": {"scope": "caller", "probe": {"token": "not-a-real-token"}},
         "list_staff": {"scope": "tenant", "probe": {"tenant": "{tenant}"}},
         "start_shift": {"scope": "tenant", "probe": {"tenant": "{tenant}"}},
         "end_shift": {"scope": "tenant", "probe": {"tenant": "{tenant}"}},
         "change_staff_roles": {
             "scope": "tenant",
             "probe": {"tenant": "{tenant}", "member_id": "x", "roles": ["owner"]}
         },
         "set_staff_status": {
             "scope": "tenant",
             "probe": {"tenant": "{tenant}", "member_id": "x", "status": "disabled"}
         },
         "remove_staff": {
             "scope": "tenant",
             "probe": {"tenant": "{tenant}", "member_id": "x"}
         },
         "join_as_customer": {
             "scope": "customer",
             "probe": {"tenant": "{tenant}", "display_name": "Probe"}
         },
         "my_customer_profile": {"scope": "customer", "probe": {"tenant": "{tenant}"}}
     };
