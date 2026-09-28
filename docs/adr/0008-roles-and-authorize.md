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

## Applied in P2.4: context on every call, access group + role groups

- **`resolve_context(slug)`** (`core/authz/context.jac`) builds the `AuthContext` on the server, on **every call**. It looks the slug up, then reads the caller's `MemberOf` edges to that tenant's **role groups** in the graph. Nothing comes from the token except who the caller is, so a role granted, changed or removed applies to the next call with the same token. `scoped(slug, action, venue_id)` also runs `require()`.
- **Refusals don't reveal which cinemas exist.** An unknown slug, a malformed one and a cinema the caller isn't a member of all get the same `not_found` ("No such cinema."). A member who lacks the permission gets `forbidden`.
- **Two kinds of staff group per tenant** (`core/tenancy/groups.jac`):
  - one **access group** (`role = "staff"`). It holds the graph grants: tenant nodes grant it WRITE, one entry per node whatever the number of staff (ADR-0004). Every staff member joins it once.
  - **role groups**, one per role, or per role and venue (`venue_id`). They carry **no node grants** and only express roles. A member of several venue groups for one role gets one venue-scoped assignment covering all of those venues.

  This keeps grants O(1) per node as roles and venues multiply. Adding a role never touches existing nodes.
- **`add_staff(tenant, role, venue_id)`** joins the caller to the access group, if they aren't in it yet, and to the role group. It's used by signup (the owner) and, in P2.5, by invitations. **`remove_member`** removes every membership a person holds in a tenant.
- **The tenant-isolation registry** (`tests/isolation/registry.jac`) lists every served endpoint with its scope (`public`, `caller` or `tenant`). A meta-test compares it with the app's OpenAPI routes, so an unregistered endpoint fails CI. A probe calls every `tenant` endpoint as tenant A's owner with tenant B's slug, and requires the `not_found` answer, with B unchanged.

## Revised in P2.5: roles live on the membership record

P2.4 stored roles as `MemberOf` edges to role groups. A member's edges can only be created in **their own** request (ADR-0004), so an owner or admin could never change someone else's role. P2.5 therefore moves roles to data:

- **A member has one edge**, to the tenant's access group (for the graph grants), and **one `Membership` record**. The record is owned by the tenant's principal and **readable only by that member**, through a per-record `allow_root(..., READ)`. It holds their role keys (`"usher"`, `"usher@venue-1"`) and a status (`active` or `disabled`). Role groups are gone.
- **`resolve_context`** reads the caller's own record under the access group. Owners and admins change roles, disable or remove members by editing or deleting the record, as the principal, and the member's next call reflects it.
- **Invitations** (`core/tenancy/staff_api.jac`):
  - `invite_staff` creates a principal-owned `Invite` and a one-time token from Jac's token store. It expires after `AFRICINEMAS_INVITE_TTL_S`, 72 h by default.
  - `accept_invite` runs in the invitee's request. It peeks the token, and single use is decided by an **atomic claim** on the invite id (ADR-0007). It joins the invitee, marks the invite used, and consumes the token and makes the claim permanent in `on_commit` (JI-022).
- **No privilege escalation** (`can_grant`): an actor may grant a role, or manage a member, only if their own tenant-wide roles already hold every permission of that role, or of every role the member holds. So an admin can't create owners or touch an owner's membership.
- **No self-change:** nobody can change, disable or remove their own membership through these endpoints. That prevents self-promotion and locking yourself out; another owner or admin has to do it.
- Shift sessions (ADR-0006) arrive with login in P2.7.
