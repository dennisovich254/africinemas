# ADR-0051: The snack menu at a venue, and a cart's price from the server

- **Status:** Accepted
- **Date:** 2026-10-22
- **Sub-phase:** P12.6
- **Code:** `core/snacks/menu.jac` (`menu_of`, `price_cart`), `core/snacks/menu_api.jac` (`public_snacks`, `price_snacks`, `public_snack_image`)
- **Tests:** `tests/integration/snack_menu_tests.jac`

## Context
Customers add snacks on the storefront (P12.8), and staff at the box office (P12.10). Both need to know what's on sale at one venue and what a cart costs there. The catalog (P12.1–P12.5) already decides each piece: `offer` (on at a venue, with a price), `combo_on_sale`, add-on options off at a venue, and stock with its at-zero rule.

## Decision
1. **One module decides the menu and the price** (`core/snacks/menu.jac`), read once per request into a *shelf*: every variant on sale at the venue with its price there and how many can still be sold. The storefront and the box office both use it, so they can't disagree.
2. **On sale** means: the product and variant are active and on at the venue, with a price (the venue's own, else the variant's), and stock allows one more. Untracked variants, and tracked ones whose at-zero rule is "allow", have no limit. A combo is on sale when its own variant is and every component can be filled. A product whose required add-ons can't be met at the venue is left out, and so is a category with nothing on sale. "Few left" (5 or fewer) is shown.
3. **A cart is priced on the server only.** A line is a variant, a quantity (1–20), add-on option ids (repeated for a repeatable group) and, for a combo, the variants chosen for each component (a fixed component can be left out). A unit costs the variant's price there plus its add-ons. A combo's choices don't change its price (ADR-0040). Stock is checked across the whole cart, with combo components counted, so two lines can't add up to more than is left.
4. **Every problem is reported at once**, naming the snack ("Only 3 Coca-Cola left."), and the cart is refused (`snacks_unavailable`). Pricing changes nothing: stock is reserved by the order (P12.7).
5. **The endpoints are public storefront endpoints.** The venue is the venue of a showtime on the storefront that hasn't started, and anything else is `not_found`. Product images are public only while the product is active.

## Consequences
- Prices shown are the prices charged. The order (P12.7) reprices the cart with `price_cart` when it's placed and keeps that snapshot.
- Reading the shelf reads every product's variants and each tracked variant's counters. That's fine at a cinema's scale (dozens of products), and a cache can come later without changing callers.
