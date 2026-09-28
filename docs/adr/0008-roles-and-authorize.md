# ADR-0008: Tenant roles, permissions and one `authorize()` decision

- **Status:** Accepted, pending review of the role table by the product owner
- **Date:** 2026-09-28
- **Sub-phase:** P2.3
- **Code:** `core/authz/policy.jac`. **Spec:** the matrix in `tests/unit/authz_tests.jac`.

## Context

Architecture §14 and §15 ask for RBAC plus tenant scope, resource scope and sensitive-action rules, deny-by-default, with built-in roles. §129 asks for one `authorize(ctx, action, resource)` rather than role checks scattered through endpoints. §130 says roles are **not a ladder**. Graph grants already keep tenants apart (ADR-0004), but every staff member of a tenant holds the same graph-level access. So what a member may do *inside* their tenant has to be decided in code.

## Decision

1. **One policy module** holds the permissions, the roles, the role → permission table, and `authorize()` / `require()`. Endpoints never test roles directly.
2. **`authorize(ctx, action, resource)` is deny-by-default.** It allows only when all of these hold:
   - the action is a known permission (exact match; no wildcards, no case folding);
   - the resource belongs to `ctx.tenant_id`, which double-checks the graph boundary;
   - some role assignment of the member grants the action **and** covers the resource.

   `require()` raises `Forbidden` (code `forbidden`) naming the action.
3. **Venue scope.** General Manager, Box Office Manager, Box Office Agent and Usher can be limited to specific venues. A venue-scoped assignment covers only resources in those venues, never tenant-wide ones. Each assignment counts only within its own scope. Every other role is tenant-wide, because money, staff, content and settings aren't per venue.
4. **Permissions:** §15's list, plus `venues.read` and `venues.configure`, which venue setup (P3) needs.
5. **Roles now:** `owner`, `tenant_admin`, `general_manager`, `finance_manager`, `box_office_manager`, `box_office_agent`, `content_manager`, `usher`, `auditor`, `it_admin`. §15's `concession_manager`, `inventory_manager` and `marketing_manager` wait until concessions, inventory and promotions exist, rather than being roles with nothing to do.

## The role table (the part to review)

| Role | Can | Notably can't |
| --- | --- | --- |
| owner | everything | — |
| tenant_admin | movies, showtimes, seats and venues setup, bookings, tickets, staff, tenant settings | any money (payments, refunds, reports), payment settings, deleting the tenant |
| general_manager* | showtimes, bookings, tickets, read payments and reports, read staff | edit movies, configure seats or venues, refunds, manage staff |
| finance_manager | payments (read, refund, reconcile), financial reports, read bookings and catalogue | staff, settings, payment settings, tickets |
| box_office_manager* | bookings (incl. cancel), tickets (issue, invalidate, scan), read payments and staff | refunds, reports, setup |
| box_office_agent* | read catalogue and floor, create and read bookings, issue tickets | cancel bookings, invalidate tickets, anything with money |
| content_manager | movies (incl. publish), create and update showtimes, read floor | cancel showtimes, bookings, money, staff |
| usher* | scan tickets, read showtimes, venues and bookings | everything else |
| auditor | read-only: catalogue, floor, bookings, payments, reports, staff | any change |
| it_admin | tenant settings, read floor and staff | money, staff changes, content |

\* can be limited to specific venues.

**Only the owner** can delete the tenant or change payment (M-Pesa) settings. The tests assert this.

## Consequences

- The context (member, roles, venue scopes) is built server-side from the graph on every call in P2.4, so revoking a role takes effect immediately, despite long-lived JWTs (ADR-0006).
- Step-up authentication for sensitive operations (§16) layers on top later. `authorize` only answers "may this role do this here".
- Changing who can do what is a one-line table change, plus the matching matrix cell in the tests, and the tests fail until both agree.
