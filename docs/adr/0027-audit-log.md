# ADR-0027: Every staff change is one audit event in Jac's shared store, readable by owners and auditors, writable by nobody

- **Status:** Accepted
- **Date:** 2026-10-08
- **Sub-phase:** P7.2
- **Code:** `core/audit/log.jac` (`audited`, `record`, the store), `core/audit/audit_api.jac` (`audit_log`), `core/authz/policy.jac` (`audit.read`), every audited endpoint
- **Tests:** `tests/integration/audit_meta_tests.jac`, `tests/integration/audit_tests.jac`, `tests/isolation/registry.jac` (`audit`)

## Context
Plan 7.2 (architecture §66, §67): every sensitive endpoint emits exactly one `AuditEvent`, checked by a meta-test driven by the endpoint registry; owners can read audit events but not delete them. An event holds the time, tenant, actor, action, resource, result and a correlation id, and never a password, token, secret or payment credential.

## Decision
1. **What is audited:** every staff endpoint that changes something, 43 of them:
   - creating and renaming the cinema; shifts;
   - staff: invitations, joining, roles, status, removal;
   - venues, screens, layouts, movies and their images, showtimes, price lists;
   - branding and the home page;
   - box office sales (cash, M-Pesa) and door scans.

   Reads, and customers' own actions (holds, orders, payments, saving bookings), aren't: they aren't security events, and they would fill the log with customer data.
2. **One wrapper, one event:** an audited endpoint answers through `audited(tenant, action, resource_type, resource_id, work)`, which writes the event `pending` before the work and finishes it once after:
   - **result:** `ok`, or the refusal's code (`forbidden`, `not_found`, `no_shift`, …), so refused attempts are recorded too;
   - **resource:** from the request, or, for something created, from the response (`made`);
   - **detail:** a short note the endpoint chose (the roles given, a status); never a secret, ticket code or customer contact.

   `create_cinema` and `accept_invite` record in the cinema they make or join, on success.
3. **Events live outside the graph,** in Jac's shared store: one document per event in `jac_docs` (`collection` = the cinema, `id` = time and a random part), on the store's own connection, committed at once (as our claims are, ADR-0007). A first version kept them as graph nodes under one `AuditTrail` per cinema, and that failed two ways:
   - **Every audited request read and wrote the same trail node,** so concurrent staff actions aborted each other with Postgres serialization failures, which Jac answers as 500s in function endpoints (JI-031). The concurrency tests for screenings, scans, layouts and publishing failed.
   - **The event's result was a graph write after the endpoint's work,** and some work commits part-way (a sale, a scan); that write made Jac re-run the whole request, doing the sale or scan twice (JI-042).

   In the store each event is its own row: an insert, then one guarded update (`pending` to its result, only once). No shared row, no graph write.
4. **A failed request keeps its event:** the store commits at once, so work that fails after starting leaves its event `pending`. The attempt is on record either way.
5. **Only the cinema's own staff write to its log:** an event is recorded only when the caller is active staff of that cinema. An outsider's attempt, refused as `not_found`, records nothing, so nobody can fill another cinema's log.
6. **Reading:** `audit_log(tenant, limit, before, action)`, newest first, 1 to 100 per page, optionally one action. It needs an open shift and the new permission `audit.read`: owners and auditors.
7. **Nobody can change or delete an event:** staff requests never reach the store; only `core/audit/log.jac` writes these documents (an insert, and finishing a `pending` one once), and only `audit_log` reads them. No endpoint changes or deletes them.
8. **Events carry the real time,** not `core.clock`'s, which tests freeze and move, fixed-width so that ids sort in time order.
9. **The registry decides:** each entry in `tests/isolation/registry.jac` says what its endpoint audits (`"audit": "<action>"` or `""`). The meta-test calls every endpoint and checks it adds exactly one finished event of that action, or none. A new endpoint can't be added without deciding.

## Consequences
- **Not recorded yet:**
  - **source IP and device:** our endpoints don't receive the request; revisit in 11.1 (security pass);
  - **sign-ins:** `/user/login` is Jac's own endpoint;
  - **refunds, voided tickets and cancelled bookings:** these endpoints don't exist yet. When they are added, the registry makes them choose an action.
- **The shared store is the database's:** events are in the same Postgres as the graph, so backups cover them; but they aren't graph data, so `jac` graph tools don't show them.
- **Retention and archiving** (§67, platform administrators) aren't built: events are kept for good.
- **Rule for this app (JI-042):** in an endpoint that commits part-way (`commit_now()`), don't make a graph write after the commit.
