# ADR-0039: Snack availability and prices per venue

- **Status:** Accepted
- **Date:** 2026-10-11
- **Sub-phase:** P12.2
- **Code:** `core/snacks/catalog.jac` (`offer`, `check_venue_price`), `core/snacks/venue_api.jac`, `web/backoffice/SnackVenues.jac`
- **Tests:** `tests/unit/snack_venue_tests.jac`, `tests/integration/snack_venue_tests.jac`, `e2e/snack_venue_tests.jac`

## Context
The design guide (§3F, §7) wants each location to control what it sells and, when needed, what it charges, without duplicating products. In AfriCinemas a cinema's venues are the guide's locations.

## Decision
1. **Sold everywhere until switched off.** A product keeps `off_at`, the venues that don't sell it, so a new venue sells the catalog. A variant keeps its own `off_at`, plus `venue_prices`, venue-specific prices that override its price.
2. **One rule decides what a venue sells** (`offer`, pure). A variant is on sale at a venue when all of these hold:
   - the product is active and on there;
   - the variant is available and on there;
   - there is a price: the venue's own, else the variant's.

   The storefront menu (P12.6) and orders (P12.7) use this rule.
3. **Who changes what:**
   - Where a product is sold, and venue prices, are managers' (`concessions.manage`).
   - A variant's availability at a venue is also the box office's (`concessions.availability` at that venue). A venue-scoped agent flips it only where they work.
4. **A venue price is whole cents from KES 1 to KES 100,000, or none** (back to the variant's price; `invalid_price` otherwise). Every venue, product and variant id is checked against the cinema. Every change is audited (`snack_product.venues_set`, `snack_variant.*`).
5. **The editor's "At each venue" section** has:
   - a "Sold at" checklist;
   - per venue, each variant's "Unavailable at <venue>" switch, a button whose pressed state matches its label;
   - per venue, each variant's price there, where empty means the variant's own price.

   It shows once the product is saved, so it never mixes with unsaved edits.

## Consequences
- Archiving a venue or deleting one doesn't clean these lists. An id for a venue that no longer exists is harmless, because no showtime can be there.
- Stock per venue (P12.4) adds to the same variant-and-venue pair.
