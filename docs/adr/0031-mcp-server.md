# ADR-0031: AfriCinemas speaks MCP from the Jac app itself, with a movie card as an MCP App

- **Status:** Accepted (spike: confirmed in Claude by hand)
- **Date:** 2026-10-09
- **Sub-phase:** P8.2
- **Code:** `core/mcp/server.jac` (`mcp`, `respond`), `core/mcp/movie_card.jac`, `main.jac`
- **Tests:** `tests/unit/mcp_protocol_tests.jac`, `tests/integration/mcp_server_tests.jac`, `tests/isolation/isolation_tests.jac` (`route:/mcp`)

## Context
Phase 8 puts AfriCinemas inside AI chats, MCP Apps hosts first (user decision 2026-10-09). The spike has to answer whether our Jac app can be an MCP server that Claude connects to, and draw interactive UI (a movie's poster and trailer) in the chat, before 8.3 widens the browsing and 8.4 adds sign-in and booking.

## Decision
1. **One route in the app, no second service:** `@restspec(method=POST, path="/mcp", envelope=False)` answers JSON-RPC 2.0 as MCP's Streamable HTTP transport, statelessly: no session id and no event stream, one JSON answer per request. `respond(jsonrpc, method, id, params)` holds the protocol so it's unit-tested without HTTP.
   - `initialize` echoes the client's protocol version when we speak it (2025-11-25, 2025-06-18, 2025-03-26), else ours; we offer tools and resources.
   - Errors are JSON-RPC's: -32600 not 2.0, -32601 unknown method, -32602 bad tool, arguments or resource. An unknown cinema or movie is a tool error (`isError`), which the model can read and act on.
2. **Read-only and public for now:** `find_cinemas` and `whats_on` (the agent's tools, P8.1, answered as JSON text) and `show_movie`. Nothing holds seats, orders or pays: those need the customer's sign-in (8.4).
3. **`show_movie` draws the card:** its `_meta.ui.resourceUri` names `ui://africinemas/movie-card`, served as `text/html;profile=mcp-app`.
   - It accepts a movie's title (any case, or the only title containing it) as well as its key, because a chat only knows names.
   - The result carries text for the model, `structuredContent` for the card (details, showtimes, the trailer's player, the storefront's movie page) and the poster in `_meta` (a WebP data URL), so the model never reads a base64 image.
4. **The card is self-contained and treats movie text as text:** no outside script, style, font or image. It never uses `innerHTML`. Its CSP allows framing only `www.youtube-nocookie.com` and `player.vimeo.com`, the two players `trailer_embed` builds. Links open through the host (`ui/open-link`). It speaks the 2026-01-26 handshake (asking again, backing off, until the host answers), reports its height and follows the host's theme.
5. **The isolation registry covers it:** a new `mcp` scope, probed anonymously with a tool call at another cinema.

## Consequences
- **A notification gets 200 with `{}`, not 202:** a Jac endpoint can't choose its status (JI-033). MCP clients ignore the body of a reply to a notification; the manual Claude check confirms it.
- **An omitted `id` or `params` reaches Jac as the string "None"** (JI-025), so notifications are told by their method (`notifications/...`), as MCP names them all.
- **Hosts decide what a card may do:** whether Claude lets the trailer play inline depends on its sandbox. The card always offers "Trailer on the web" too.
- **Book links** use `AFRICINEMAS_PUBLIC_URL`, as ticket emails do.
- **Not yet:** sign-in and booking (OAuth, 8.4); more cards, such as showtimes and a seat map (8.3); rate limits.
