# ADR-0010: Guest checkout by default; customer accounts are optional

- **Status:** Accepted (product owner decision, 2026-09-28)
- **Date:** 2026-09-28
- **Decided during:** P2.6. **Applies to:** Phase 4 (storefront and checkout), Phase 5 (payments), Phase 6 (tickets).

## Context

Architecture §11 says a booking "should not require collecting unnecessary personal information". §126 planned **guest checkout**, but required a customer account until spike S4 showed an anonymous request can safely write data that becomes the cinema's own. S4 passed (ADR-0005). Most customers book on a phone and pay with M-Pesa, which already verifies a phone number with every payment.

## Decision

1. **Nobody has to sign up to book.** A guest:
   1. picks seats;
   2. enters a phone number, which is the M-Pesa STK push number;
   3. pays;
   4. gets the tickets.
2. **A guest booking is stored in the cinema's data**, written through the system-inbox pattern (ADR-0005), and owned by the cinema's principal. The guest receives a **booking reference plus a secret**, on screen and by SMS, and uses them to view or re-open their tickets later. The secret is random and long, and it's shown to the guest but stored only as a hash.
3. **Accounts stay optional.** After a purchase, the customer is offered "save your tickets". An account (P2.6, ADR-0009) keeps their bookings in one place per cinema. A guest booking can be attached to an account later, by proving the booking secret.
4. **Phone verification from M-Pesa or SMS is enough to retrieve tickets,** and nothing more sensitive (§11: SMS alone shouldn't guard high-value actions).

## Consequences

- Phase 4's checkout and Phase 6's ticket views must work without a login. Their endpoints are storefront endpoints: anonymous, so either `def:pub` or through the inbox, and authorized by the booking secret. They need their own isolation checks, including that a booking reference without its secret reveals nothing.
- Booking references must be unguessable, and lookups rate-limited (threat model §131: "attacker enumerates booking IDs").
