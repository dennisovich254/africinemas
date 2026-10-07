# ADR-0021: Tickets are redeemed by an atomic claim, for the showtime being checked, inside a door window

- **Status:** Accepted
- **Date:** 2026-10-07
- **Sub-phase:** P6.2
- **Code:** `core/booking/redeem_api.jac`, `core/booking/ticket_codes.jac` (`typed_reference`), `core/booking/models.jac` (`Ticket.used_at`, `used_by`)
- **Tests:** `tests/integration/redeem_tests.jac`, `tests/integration/redeem_concurrency_tests.jac`, `tests/unit/ticket_code_tests.jac`

## Context
Architecture §47 says that a ticket, once scanned, is used, and that a second scan is refused as `ALREADY_REDEEMED`, atomically, so two scanners can't both admit one ticket. §48 says the scanner works for one selected showtime. Tickets carry a claimed reference and a signed QR payload (ADR-0020).

## Decision
1. **One endpoint, `redeem_ticket(tenant, screening_id, code)`.**
   - **Who:** staff on shift with `tickets.scan` at the showtime's venue: ushers, box office managers, general managers, admins and owners. A venue-limited role only works at its venues; box office agents can't scan.
   - **`code`:** a scanned QR payload or a typed reference. Case, spaces and dashes don't matter.
2. **Checks, in this order:**
   1. the code is valid;
   2. the ticket exists at this cinema (another cinema's ticket reads as unknown);
   3. it's for this showtime (otherwise its showtime is named);
   4. the showtime is on;
   5. the time is inside the door window;
   6. the ticket isn't voided or refunded;
   7. it isn't already used.
3. **Door window:** from 120 minutes before the start until the showtime's `ends_at`, which includes the cleaning buffer.
4. **Exactly once:** the scan claims the ticket (namespace `ticket-used`, ADR-0007) before marking it used.
   - The claim's owner records the staff member and the time, so a losing scan answers `already_redeemed` with when it happened and who scanned it.
   - The ticket is then saved with `commit_now`. If that fails, the claim is released before the error propagates, so a replayed request claims it again rather than refusing its own scan.
5. **`used_by` is the staff member.** Scanner devices (§48: registration, remote disable) come later.

## Consequences
- Voiding and refunds don't exist yet; the door already refuses their statuses.
- The window is fixed in code. Making it a per-cinema setting is a later change if cinemas need it.
- Audit events for redemptions come with 7.2.
