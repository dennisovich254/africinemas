# ADR-0032: Browsing in the chat: a connector per cinema, a programme card, and only what's on sale

- **Status:** Accepted (awaiting the Claude check)
- **Date:** 2026-10-09
- **Sub-phase:** P8.3
- **Code:** `core/mcp/server.jac` (`cinema_mcp`, `_tools`, `_whats_on`, `_movie_poster`, `_brand`), `core/mcp/card_kit.jac`, `core/mcp/movie_card.jac`, `core/mcp/programme_card.jac`, `core/catalog/storefront.jac` (`public_programme`), `web/backoffice/ConnectSection.jac`
- **Tests:** `tests/unit/mcp_protocol_tests.jac`, `tests/integration/mcp_server_tests.jac`, `tests/isolation/isolation_tests.jac` (`route:/c/{slug}/mcp`), `e2e/connect_tests.jac`

## Context
8.2 proved a card renders in Claude through one platform connector (`/mcp`). For 8.3 the user decided each cinema should also have its own connector: a cinema wants its own customers to add *it*, not a directory of every cinema. The 8.2 check also found two problems: `whats_on` offered showtimes that had already started, and the trailer frame stayed black in Claude.

## Decision
1. **A connector per cinema, served by the same code:** `POST /c/{slug}/mcp` calls `respond` with the cinema fixed.
   - Its tools have no `cinema` argument and `find_cinemas` isn't offered. Any cinema a caller names is replaced by the server, so a cinema's connector can't be talked into another cinema's data.
   - It introduces itself with the cinema's name. An unknown or unopened cinema's connector refuses every request.
   - The platform connector (`/mcp`) stays, for a directory listing.
2. **Only showtimes on sale:** `public_programme`, which only the agent and MCP read, now uses the storefront's `upcoming`, so a started showtime never reaches a chat.
3. **A programme card:** `whats_on` draws `ui://africinemas/whats-on`, showing days as rows of poster tiles with that day's times.
   - The posters load one at a time through `movie_poster`, a tool marked for the cards only (`_meta.ui.visibility: ["app"]`). The model never sees the tool or the images.
   - Tapping a movie asks the chat to show it (`ui/message`), which draws its movie card.
4. **Cinema colours on cards:** each card result carries the cinema's light and dark `accent`/`on_accent` from its published theme. The theme validator has already contrast-checked them, and the card applies them only if they're plain hex colours.
5. **Trailers open through the host, with no embedded player.**
   - claude.ai ignores MCP Apps' `frameDomains` ([anthropics/claude-code#59351](https://github.com/anthropics/claude-code/issues/59351)), so the embedded YouTube player stayed black even after the user pressed Play.
   - The movie card's **Watch trailer** therefore opens the trailer's page (`ui/open-link`), and the cards' CSP frames nothing.
   - The storefront website still embeds trailers on its own pages.
6. **One card kit:** both cards share the base look and the host bridge (`card_kit.jac`). Each card supplies only its own styles and rendering.
7. **The back office shows the link:** Settings › AI chat shows the cinema's connector link, a Copy button and the steps to add it in Claude.

## Consequences
- **The isolation registry covers the new route:** Nova's connector is asked about the other tenant and must leak nothing.
- **Inline trailers in chat need either Claude to honour `frameDomains`, or self-hosted trailer files** played by the card's own `<video>` from a `resourceDomains` origin. Self-hosting needs object storage (Jac can't serve video, JI-033), so it comes with deployment.
- **Not yet:** sign-in and booking (8.4), rate limits (8.4).
