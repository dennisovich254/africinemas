# ADR-0023: "My tickets" lists bookings a signed-in customer saved by their link; the page saves them by itself

- **Status:** Accepted
- **Date:** 2026-10-07
- **Sub-phase:** P6.3b
- **Code:** `core/booking/customer_tickets.jac`, `core/tenancy/customer_api.jac` (`join_customer`), `web/storefront/TicketDelivery.jac` (`SaveToAccount`), `web/storefront/MyTicketsPage.jac`, `web/auth/session.jac` (`next_path`)
- **Tests:** `tests/integration/customer_tickets_tests.jac`, `e2e/my_tickets_tests.jac`

## Context
Guest checkout is the default and accounts are optional (ADR-0010). A guest booking can be attached to an account by proving its secret, which is the ticket link (ADR-0022). Plan 6.3's test is that a customer sees only their own tickets. Payments are public endpoints, so the server can't simply attach a booking to "the signed-in caller" while paying, without telling signed-in and anonymous callers apart inside a public endpoint.

## Decision
1. **`save_booking(slug, token)` (login-only) attaches a booking to the caller's account at that cinema.** It proves the link exactly as resending does, and makes the caller's customer profile there if they have none. The profile logic moved to a plain `join_customer`, which `join_as_customer` now calls.
2. **The index.** Each saved booking is a permanent claim in the caller's own namespace, `customer-orders:<tenant id>:<customer root id>`, keyed by the order. Saving twice is one claim.
3. **`my_tickets(slug)` (login-only) reads only that namespace.** It lists the caller's confirmed bookings at the cinema, upcoming first (soonest first), then past (latest first), each with its link and tickets.
4. **The page saves by itself.** When a signed-in visitor sees their tickets (on "You're booked" or the tickets page), the browser calls `save_booking` with that booking's link.
   - On success it says "Saved to your account" and links to My tickets.
   - If the call fails (for example, an expired sign-in) it offers a Save button.
   - A visitor who isn't signed in is offered to sign in. The sign-in and sign-up pages now return to storefront pages (`/c/…`) as well as invitations, never to an outside address, so they come back to the tickets and those are saved then.
5. **My tickets** (`/c/<slug>/my-tickets`) is linked from the storefront footer. It asks a visitor who isn't signed in to sign in.

## Consequences
- **A booking paid as a guest and never opened while signed in** stays out of My tickets. The email and the link still hold it.
- **Saving is per cinema**, like customer profiles (ADR-0009).
- **Removing a booking from My tickets isn't offered yet.**
