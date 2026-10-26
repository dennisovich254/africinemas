# ADR-0076: Extra snacks on an existing booking

- **Status:** Accepted
- **Date:** 2026-10-26
- **Sub-phase:** P12.14

## Decision

A confirmed booking can buy more snacks before its showtime starts, through its
private tickets link (also reached from My tickets), or through an on-shift box
office agent with `bookings.create` at its venue. A booking reference is accepted
only by the authenticated staff endpoint. Cancelled and started screenings refuse
additions; closing ticket sales alone does not prevent an existing customer buying snacks.

Each addition is a separate `Order` with `booking_id` pointing to the original.
It has no ticket lines or seat hold. It is attached to both the original order
(for pickup) and the screening (for the existing reporting and settlement paths).
Its own price snapshot, stock reservation, payment and ledger entry preserve the
original ticket purchase. Reports count each sale once. The payment deadline is
the earlier of the normal payment window and showtime start. A payment settling
after the start needs attention and a refund task; it cannot add collectible items.
The existing resolver releases expired reservations.

All paid batches share the original pickup code. If there was no original snack
purchase, the first addition allocates a code; an atomic booking-to-code claim
keeps concurrent attempts on the same code. Failed or unpaid additions are never
shown as purchased snacks. Updated emails use the original tickets link.

Collection is recorded per paid batch. The snack counter shows outstanding items
separately from previously collected items. Handover claims every outstanding
batch before committing, releasing its claims if another counter won or saving
fails. Staff can send the displayed collection token with handover; a changed
batch list is refused and must be reviewed again. This preserves once-only pickup
when another batch is bought after the first was collected.

The shared snack-sale component serves walk-ins and additions. Customer additions
offer M-Pesa; counter additions offer cash or M-Pesa. The server prices both and
binds payment idempotency to the booking, selling identity and browser sale id.
Dedicated glasses variants cannot be added through this flow: issued ticket
entitlements remain unchanged.

## Validation

Unit tests cover the exact start boundary and confirmed-booking requirement.
Integration tests cover separate payments, callback and cash replays, stock,
expiry, private-link and tenant access, unchanged tickets and pickup, later
collection, and late-payment refund handling. Browser tests cover My tickets
through M-Pesa payment and counter lookup through cash payment on phone and desktop.
CI captures 375/768/1440 px screenshots in light and dark themes and checks overflow
and touch targets. Heavy integration and browser tests run in GitHub CI only.
