# ADR-0010: Guest checkout by default; customer accounts are optional

- **Status:** Accepted (product owner decision, 2026-09-28)
- **Date:** 2026-09-28
- **Decided during:** P2.6. **Applies to:** Phase 4 (storefront and checkout), Phase 5 (payments), Phase 6 (tickets).

## Context

Architecture §11 says a booking "should not require collecting unnecessary personal information". §126 planned **guest checkout**, but required a customer account until spike S4 showed an anonymous request can safely write data that becomes the cinema's own. S4 passed (ADR-0005). Most customers book on a phone and pay with M-Pesa, which already verifies a phone number with every payment.

## Decision

1. **Nobody has to sign up to book.** A guest:
   1. picks seats;
   2. enters an **email address**, where the tickets are sent, and an **M-Pesa phone number**, for the STK push;
   3. pays;
   4. gets the tickets on screen and **by email**.
2. **A guest booking is stored in the cinema's data**, written through the system-inbox pattern (ADR-0005), and owned by the cinema's principal. The guest receives a **booking reference plus a secret**, on screen and **in the ticket email**, and uses them to view or re-open their tickets later. The secret is random and long, and it's shown to the guest but stored only as a hash.
3. **Accounts stay optional.** After a purchase, the customer is offered "save your tickets". An account (P2.6, ADR-0009) keeps their bookings in one place per cinema. A guest booking can be attached to an account later, by proving the booking secret.
4. **Tickets go by email, not SMS** (product owner decision, 2026-09-28: simpler, no SMS gateway or per-message cost). The email carries the QR tickets and the booking link. Jac's built-in SMTP emailer (`EMAILER_SMTP_*` settings) sends it, in `on_commit` after payment is confirmed, so it goes once (reference/persistence). A mistyped address is recoverable from the confirmation screen, which shows the tickets and lets the guest resend them to a corrected address.
5. **Holding the booking secret is enough to view and resend tickets,** and nothing more sensitive (§11).
6. **One AfriCinemas sender for every cinema** (product owner decision, 2026-09-28: signup to selling in minutes, not weeks). Cinemas configure nothing for email:
   - **From:** the cinema's name as the display name on our address, e.g. `Nova Cinemas <tickets@africinemas.co.ke>`.
   - **Reply-To:** the cinema's contact email, if the owner adds one in settings. It's optional and needs no verification.
   - **Content:** the cinema's name, logo and colours (per-cinema branding, P3.8), with a small "Tickets by AfriCinemas" footer.
   - **Platform setup, once:** a transactional email provider reached over SMTP, with SPF, DKIM and DMARC on our domain. Its credentials are environment secrets.
   - **Later, optional:** a cinema can verify its own sending domain (for example `tickets@novacinemas.co.ke`). It's never required at signup.

## Consequences

- Phase 4's checkout and Phase 6's ticket views must work without a login. Their endpoints are storefront endpoints: anonymous, so either `def:pub` or through the inbox, and authorized by the booking secret. They need their own isolation checks, including that a booking reference without its secret reveals nothing.
- Booking references must be unguessable, and lookups rate-limited (threat model §131: "attacker enumerates booking IDs").
- Email delivery needs SMTP settings in production (secrets in the environment, never in `jac.toml`, JI-015). Tests use a fake sender that records messages; they never send real email.
- **To verify when building ticket delivery (Phases 5 and 6):** whether Jac's built-in emailer can set a per-message display name and Reply-To. If it can't, we send through the provider's SMTP with Python's standard library instead.
