# ADR-0036: Booking from Claude: a self-contained booking card whose tools only the card can call

- **Status:** Accepted (awaiting the Claude check)
- **Date:** 2026-10-10
- **Sub-phase:** P8.6b
- **Code:** `core/mcp/booking.jac` (`card_call`, `holder_for`), `core/mcp/booking_card.jac`, `core/mcp/server.jac` (`book_showtime`, the card tools), `core/booking/customer_tickets.jac` (`save_for_caller`)
- **Tests:** `tests/integration/mcp_booking_tests.jac`, `tests/unit/mcp_protocol_tests.jac`

## Context
Customers can sign Claude in (P8.6a). Booking needs seats that are never double-sold, a hold, server prices, an order with an idempotency key, and an M-Pesa payment confirmed with the customer's own PIN. In our storefront chat (P8.5) the card embeds the storefront's `Checkout`. A card in Claude can't: it runs in a sandbox with no access to our pages or API, only to MCP calls through the host.

## Decision
1. **The model can only open the card.** `book_showtime(cinema, showtime_id, seats)` checks the showtime is on sale and opens `ui://africinemas/booking`, with suggested seats (free ones only) chosen but not held.
2. **The card books through its own tools,** which only the card can call (`_meta.ui.visibility: ["app"]`): `card_state`, `card_hold`, `card_quote`, `card_order`, `card_pay` and `card_status`.
   - They wrap the website's own endpoints (`hold_seats`, `quote_hold`, `place_order`, `start_payment`, `my_payment`), so every rule of the website applies.
   - The model never sees these tools or their answers.
   - Their annotations say which ones change things (hold, order, pay).
3. **Signed in only, with a server-made holder.**
   - Without the customer's OAuth token every card tool refuses ("sign in"), and the card offers the website instead.
   - Each customer's holds and orders belong to `holder_for(customer)`, derived on the server. A caller never chooses it, so one customer can't touch another's.
4. **Private details stay out of the model.** The customer types their phone number and email into the card, which sends them straight to our server. Answers carry no phone number and only a masked email. The PIN is entered only on the phone.
5. **The booking is the customer's.** Once paid, `card_status` saves the booking to the linked customer (`save_for_caller`, run as them), so "my bookings" and My tickets list it.
6. **The card resumes.** Reopened, it asks `card_state` and continues from wherever the customer was: choosing, held, ordered, paying or booked.

## Consequences
- **Booking from Claude runs on the same server-side rules as the website,** through the same endpoints. Only the screen is new.
- **The card works without an outside network.** It frames nothing and loads nothing; all its data comes through MCP tool calls.
- **Still to come (8.6c):** a page where customers see and revoke Claude's access, and Client ID Metadata Documents if a client needs them.
