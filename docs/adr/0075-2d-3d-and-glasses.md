# ADR-0075: 2D and 3D showtimes, with glasses as a snack sale

- **Status:** Accepted
- **Date:** 2026-10-25
- **Sub-phase:** P12.13
- **Code:** `core/catalog/formats.jac`, `core/catalog/movie_api.jac`, `core/catalog/screening_api.jac`, `core/snacks/glasses_api.jac`, `core/booking/order_api.jac`
- **Tests:** `tests/unit/format_tests.jac`, `tests/integration/format_glasses_tests.jac`, `e2e/format_glasses_tests.jac`

## Context

A film may normally be 3D while individual showtimes run in either 2D or 3D. The
format must remain clear from programme discovery through the issued ticket. Cinemas
may also sell reusable 3D glasses at different prices and stock levels per venue.
Glasses are optional for every customer because they may bring their own pair.

## Decision

1. A movie has a checked 2D or 3D default. A new showtime copies that value, then
   keeps its own value so staff can change the showtime without changing the movie or
   other showtimes. Orders and issued tickets snapshot the showtime format.
2. One cinema-owned, active, stock-tracked snack product represents 3D glasses. A
   per-venue configuration controls whether it is offered and supplies the venue
   price. The product is excluded from the ordinary snack grid and is offered only
   beside tickets for a 3D showtime when stock is available.
3. Each ticket has an unchecked glasses choice. The submitted seat labels must be
   unique, belong to that order and refer to a 3D showtime. The server adds one
   glasses snack line with the selected quantity; callers cannot add the dedicated
   variant through the ordinary snack cart.
4. The glasses line uses the existing reservation, sale movement and reporting paths.
   It does not create a snack pickup code: the issued ticket says whether glasses were
   bought, and Admit tells the usher to hand over a pair only for that ticket.
5. The same checkout component serves the storefront, chat booking card and box
   office, so the default and per-ticket behavior remain identical in all three.

## Validation

Pure rules cover accepted formats, unchecked choices, seat ownership and the 2D
refusal. Endpoint fixtures cover inheritance, independent showtime changes, venue
pricing, stock, order lines, reports, ticket snapshots and Admit data. Browser coverage
checks the unchecked choice, price and responsive layout on phone and desktop. Full
integration and browser execution are delegated to GitHub CI.
