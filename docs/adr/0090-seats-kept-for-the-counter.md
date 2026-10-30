# ADR-0090: Seats kept for the counter

- **Status:** Accepted
- **Date:** 2026-10-30

## Context

Many cinemas already sell at their counter, on paper and by phone, and hand over paper
tickets. If they also sell online through AfriCinemas without changing how the counter
works, both can sell the same seat. The owner chose to let them keep seats for the
counter first, with no change at the counter, and move the counter onto the Box office
screen later.

## Decision

- **Counter seats** (`core/booking/counter_seats.jac`):
  - chosen once per screen (`Auditorium.counter_seats`, on the screen's page,
    `seats.configure`);
  - changeable for one showtime (`Screening.counter_add` and `counter_free`, from the
    Screenings board, `showtimes.update`). A showtime keeps its changes, not a copy, so
    a later change to the screen still applies to it.
  - They're kept on the screen, not in the seat layout: published layouts never change,
    and showtimes keep the version they were published with.
- **Kept until the release time.** They stay counter-only until the cinema's release
  time before the showtime (`Tenant.counter_release_hours`: 2 hours by default, 0 to 72,
  in Settings → Box office). After that, unsold ones are for anyone.
- **Online** (the storefront, the chat booking card, AI apps: everything through
  `hold_seats`):
  - kept seats show as "Sold at the box office";
  - a hold that includes one is refused (`counter_seats`), all or nothing.
- **The Box office** has its own seat map (`counter_seat_availability`) and hold
  (`counter_hold_seats`), for staff who sell at the venue on shift. Counter seats are
  bookable there, marked with a ring and "counter seat" for screen readers.

## Consequences

- A counter that sells more than its seats still clashes with online sales; it needs to
  know which seats are its own. The door list (17.2) will show them.
- Phone bookings that pay later, receipt-printer tickets and SMS tickets are separate,
  later pieces.
