# ADR-0033: A cinema's own chat on its storefront, with cards from tool results

- **Status:** Accepted (awaiting the live Gemini check)
- **Date:** 2026-10-09
- **Sub-phase:** P8.4
- **Code:** `core/agent/agent_api.jac` (`cinema_chat`, limits), `core/agent/agent.jac` (`cinema_reply`, `_converse_at`, `_scripted`), `core/agent/tools.jac` (`CINEMA`, `SEEN`), `core/agent/cards.jac`, `web/storefront/ChatPanel.jac`, `web/storefront/chat_cards.jac`, `web/storefront/TrailerPlayer.jac`
- **Tests:** `tests/unit/agent_cards_tests.jac`, `tests/unit/agent_script_tests.jac`, `tests/integration/storefront_chat_tests.jac`, `e2e/storefront_chat_tests.jac`

## Context
OAuth for Claude (now 8.6) can't be served compliantly by Jac 0.37.18: a function endpoint can't answer 401 with `WWW-Authenticate` and can't read request headers. The user chose to build our own chat first (2026-10-09). There we already have a login (or guest checkout), and our own pages can play trailers.

## Decision
1. **One chat per cinema, on its storefront.** `cinema_chat(slug, message, history, holder)` fixes the cinema for every tool (`tools.CINEMA`), whatever the model names.
   - It offers browsing tools only (what's on, movie details, seat map, ticket types, the customer's own bookings): no directory, and no booking until 8.5.
   - A server-made first turn tells the model which cinema it serves.
2. **Cards come from tool results, never from the model.** During a turn the tools record what they returned (`tools.SEEN`). `cards_from` turns that into at most three cards: the programme first, then movies.
   - A reply that names a showtime no tool returned shows no card.
   - The MCP programme card uses the same `programme_card`.
3. **Limits protect the model bill.** A conversation gets 20 customer messages, and each cinema a cap on model calls per minute (`AFRICINEMAS_CHAT_PER_MINUTE`, default 30, counted per server). Over either, the reply points to the cinema's website instead of calling the model. A message that fails comes back to the box to try again.
4. **The UI.**
   - An "Ask <cinema>" button on every storefront page except a showtime's, whose seat bar is fixed to the bottom.
   - A Sheet panel (focus kept inside, Escape closes) with a polite live log, a "Thinking…" status and suggestion chips.
   - The cards use the storefront's own pieces (posters, links to showtime and movie pages).
   - The conversation is kept in `sessionStorage` per cinema for the visit.
5. **Trailers on the storefront at last.** `TrailerPlayer` frames only the server's checked player URLs (youtube-nocookie, Vimeo), and only after the visitor presses Play. It's used in the chat's movie card and on the movie page.
6. **Browser tests use a scripted model.** When `AFRICINEMAS_AGENT_SCRIPT` names a JSON script (set only by `scripts/e2e_env.sh`), the storefront chat answers from it. Production never sets it, like the clock control.

## Consequences
- **The per-minute cap is per server replica.** With several replicas the total is the cap times the replica count. A shared counter can come with deployment if needed.
- **Live behaviour with Gemini is checked by hand.** Tests use the scripted model.
- **Next, 8.5:** seat picking, hold, order and the payment panel inside the chat.
