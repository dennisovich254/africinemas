# ADR-0034: Booking in the chat embeds the storefront's own checkout; the assistant only opens it

- **Status:** Accepted (awaiting the live check)
- **Date:** 2026-10-09
- **Sub-phase:** P8.5
- **Code:** `core/agent/tools.jac` (`book_showtime`, `my_bookings`), `core/agent/cards.jac` (`booking_card`, `bookings_card`), `core/agent/agent.jac`, `web/storefront/chat_cards.jac` (`BookingCard`, `BookingsCard`), `web/storefront/Checkout.jac` (`suggested`)
- **Tests:** `tests/unit/agent_cards_tests.jac`, `tests/unit/agent_tools_tests.jac`, `tests/integration/storefront_chat_tests.jac`, `e2e/storefront_chat_tests.jac`

## Context
8.5 lets a customer book from the storefront chat. A booking involves seats that must not be double-sold, a hold with a countdown, server-side prices, an order with an idempotency key, and an M-Pesa payment the customer confirms with their own PIN. The storefront's checkout already does all of that, and the box office reuses it.

## Decision
1. **The chat embeds the storefront's own checkout; the assistant can't book.**
   - `book_showtime(showtime_id, seats)` checks the showtime is on sale at this cinema and opens a booking card. Inside it, `Checkout` runs as on the showtime page, for the same visitor (holder).
   - The chat has no hold, order or pay tool. Seats, prices, the hold, the order and the payment are the server's and the customer's, never the model's.
2. **Seats are suggested, not chosen silently.** The assistant may suggest seats. The server keeps only those free at that moment, and they start chosen but not held (`Checkout(suggested=...)`). The customer continues, or changes them, themselves.
3. **"What have I booked?"** For a signed-in customer, `my_bookings` becomes a bookings card: movie, time, place and seats only, with a link to My tickets. Signed out, the assistant asks them to sign in.
4. **Cards still come only from tool results.** The booking and bookings cards always fit within the three; movie cards give way.

## Consequences
- **The chat's booking matches the direct UI's by construction:** the same component, endpoints and holder. The e2e books in the chat, then sees the same booking on the showtime page.
- **The checkout's seat bar sticks to the bottom of the chat's scroll area,** not the screen.
- **Not here:** booking from Claude (8.6, OAuth).
