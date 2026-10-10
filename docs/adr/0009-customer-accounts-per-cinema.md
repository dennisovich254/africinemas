# ADR-0009: One login, a customer profile per cinema

- **Status:** Accepted; decision 1 (one platform login) superseded by ADR-0037 (customer accounts belong to one cinema)
- **Date:** 2026-09-28
- **Sub-phase:** P2.6
- **Code:** `core/tenancy/customer_api.jac`
- **Tests:** `tests/integration/customer_tests.jac`, `tests/isolation/`

## Context

Customers book on a cinema's storefront. Architecture §12 wants one identity that can relate to many cinemas, and §4 wants each cinema's data to stay in its own subgraph. The plan (P2.6) asks for:
- a customer registering on cinema A to get a profile at A only;
- the same person at B to get a separate profile;
- customers never to reach staff endpoints.

## Decision

1. **One platform login** (Jac's built-in `/user/register`). Joining a storefront creates a **`CustomerProfile` at that cinema**, via `join_as_customer(tenant, display_name)`.
2. **The profile belongs to the cinema.** It's owned by the cinema's principal (ADR-0003) and attached to the Tenant.
   - The customer gets **READ on their own profile only**.
   - The cinema's staff reach it through the access group, via `attach_to_tenant`, the one place a new tenant node gets its grant (ADR-0004 rule 2).
   - Bookings and tickets in P4 and P6 will follow the same shape.
3. **One profile per (cinema, person)** is an **atomic claim** (ADR-0007) whose value is the profile's id, assigned before the profile exists.
   - The claim is both the uniqueness guard (a double-click can't create two) and the index `my_customer_profile` uses. The customer needs no graph edge, so their root gains no link that could count as a group (ADR-0004 rule 5).
   - It's provisional (5 minutes) until the request commits, then permanent. A failure releases it.
4. **Storefronts** accept customers while the cinema is `configuring`, `ready_for_go_live` or `active`, so owners can make test bookings before go-live (§135). Unknown, malformed and closed storefronts all answer `not_found`.
5. **Customers aren't staff.** Every tenant-scoped endpoint answers them `not_found`, and `my_cinemas` is empty for them. The isolation registry gains a `customer` scope: usable at any cinema, but it only ever returns the caller's own data.

## Consequences

- A customer's profiles at different cinemas are unrelated records. Cinema B learns nothing about the person's activity at A.
- Customer-facing endpoints resolve the storefront as the system root (a customer can't read the Tenant node), then act as the cinema's principal to write. That's the same pattern as receipts (ADR-0005).
