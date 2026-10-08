# ADR-0027: Every staff change is one audit event, readable by owners and auditors, writable by nobody

- **Status:** Accepted
- **Date:** 2026-10-08
- **Sub-phase:** P7.2
- **Code:** `core/audit/models.jac`, `core/audit/log.jac` (`audited`, `record`), `core/audit/audit_api.jac` (`audit_log`), `core/authz/policy.jac` (`audit.read`), every audited endpoint
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
2. **One wrapper, one event:** an audited endpoint answers through `audited(tenant, action, resource_type, resource_id, work)`. It runs the work as `answer` does and records one event:
   - **result:** `ok`, or the refusal's code (`forbidden`, `not_found`, `no_shift`, …), so refused attempts are recorded too;
   - **resource:** from the request, or, for something created, from the response (`made`);
   - **detail:** a short note the endpoint chose (the roles given, a status); never a secret, ticket code or customer contact.

   `create_cinema` and `accept_invite` record in the cinema they make or join, on success.

   **The event is written before the work, `pending`, and finished after it.** Some work commits part-way (a sale, a scan); a request's first write after such a commit makes Jac re-run the whole request, doing the sale or scan twice (JI-042). To rule that out, Jac's read tier is turned off for every app (`JAC_DB_RO_UNITS=0`, set in `core/tenancy/principal.jac`): requests run at SERIALIZABLE from the start and are never re-run to upgrade. Writing first remains: work that commits part-way and then fails leaves its event `pending`.

   **Each write is made as the principal** (`flush_now()` while acting as it): the end-of-request save runs as the caller, who may only read the event.
3. **Only the cinema's own staff write to its log:** an event is recorded only when the caller is active staff of that cinema. An outsider's attempt, refused as `not_found`, records nothing, so nobody can fill another cinema's log.
4. **Reading:** `audit_log(tenant, before, limit, action)`, newest first, up to 100 per page, optionally one action. It needs an open shift and the new permission `audit.read`: owners and auditors.
5. **Nobody can change or delete an event:**
   - events live under the cinema's `AuditTrail`, owned by its principal;
   - unlike every other tenant node, they are granted to the access group READ, not WRITE;
   - no endpoint changes or deletes them.
6. **Events carry the real time,** not `core.clock`'s, which tests freeze and move: when it happened, and the order the log is read in.
7. **The registry decides:** each entry in `tests/isolation/registry.jac` says what its endpoint audits (`"audit": "<action>"` or `""`). The meta-test calls every endpoint and checks it adds exactly one event of that action, or none. A new endpoint can't be added without deciding.

## Consequences
- **Not recorded yet:**
  - **source IP and device:** our endpoints don't receive the request; revisit in 11.1 (security pass);
  - **sign-ins:** `/user/login` is Jac's own endpoint;
  - **refunds, voided tickets and cancelled bookings:** these endpoints don't exist yet. When they are added, the registry makes them choose an action.
- **A failed request records nothing:** work that raises an unexpected error rolls back with its event.
- **Retention and archiving** (§67, platform administrators) aren't built: events are kept for good.
- **The log is read whole and then paged:** fine at a cinema's size; a busy one would need an index by time.
