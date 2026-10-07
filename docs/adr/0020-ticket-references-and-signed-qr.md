# ADR-0020: Tickets carry a claimed random reference and an HMAC-signed QR payload

- **Status:** Accepted
- **Date:** 2026-10-07
- **Sub-phase:** P6.1
- **Code:** `core/booking/ticket_codes.jac`, `core/payments/settlement.jac` (`_finalize`), `core/payments/choice.jac`, `web/storefront/PayPanel.jac` (`TicketCard`)
- **Tests:** `tests/unit/ticket_code_tests.jac`, `tests/unit/payment_choice_tests.jac`, `tests/integration/ticket_issue_tests.jac`, `e2e/payment_tests.jac`

## Context
Architecture §46 says a ticket's QR code must not contain personal or descriptive details. It should be an opaque, signed identifier, with the server deciding whether the ticket is valid. The 5.4 tickets had a 10-character hex reference that nothing kept unique, and no QR code.

## Decision
1. **Reference.** 16 random characters from a 32-letter alphabet without 0/O or 1/I, in four groups (`7K2M-9QXR-4HJN-P3WD`). That gives 80 bits, and it's easy to read out or type at the door.
2. **Unique by claim.** Before a ticket is stored, its reference is claimed (ADR-0007, namespace `ticket-ref`) for `<tenant id>|<ticket id>`, using an id given to the ticket in advance. A taken reference means drawing again, up to 5 times. The claim is provisional (60 s) until the finalize commit, then permanent, so a failed finalize leaves nothing behind. The claim is also the scanner's index (6.2): reference → cinema and ticket, without searching every cinema.
3. **QR payload.** `TKT1.<reference without dashes>.<signature>`.
   - The signature is HMAC-SHA256 over `TKT1.<reference>` with `AFRICINEMAS_TICKET_KEY`, cut to 128 bits and written in base32 (26 characters).
   - `read_qr` checks the format, then compares signatures in constant time. It returns the reference, or nothing.
   - `TKT1` is the format and key version: a rotation would add `TKT2` and accept both for a while.
4. **No key, no payments.** The key must be at least 32 characters. Without it, `payment_provider()` refuses, for the simulator and Daraja alike, so nobody pays for tickets the server can't issue. Changing the key invalidates every issued QR code.
5. **On screen.** The booked panel shows one card per ticket: the seat, the QR code (`qrcode.react`, 192 px, error correction M) and the reference under it.
   - The code is always black on a white tile with a margin, in either theme, so scanners read it.
   - It is named for screen readers.

## Consequences
- The QR code alone proves nothing about validity. 6.2 looks the reference up, then checks the cinema, showtime, status and single use atomically.
- Each environment needs its own secret key. Tests and `scripts/e2e.sh` set fixed test keys.
- Tickets issued before 6.1 (development data only) have no QR and show their reference.
