# ADR-0050: One design across the whole storefront; the page reviewed before it is kept

- **Status:** Accepted
- **Date:** 2026-10-21
- **Sub-phase:** Deferred AI features: AI brand-theme generator, phase (g)
- **Code:**
  - `core/theming/branding_api.jac`: `design_storefront`, `brand_system`.
  - `core/theming/pagecode.jac`: `brand_brief`, `brief`, `write_page`.
  - `core/theming/brandkit.jac`: `FONT_FAMILIES`.
- **Tests:** `tests/unit/pagecode_tests.jac`

## Context
On warui's storefront (2026-10-21), the AI-written home page and the movie page between its header and footer looked like two sites:
- **Fonts:** the page chose Raleway; the movie page wore the kit's pairing, Sora.
- **Colours:** the page used its own golds; the movie page used the theme's.
- **Corners:** the page was square; the movie page had rounded cards.

The page writer ran at the same time as the colours and the brand plan, so it never saw them.

## Decision
1. **The colours and brand plan come first.** `design_storefront` runs the theme and the kit side by side (about 20 s), then writes the page in that system (`brand_system`):
   - the colours of the scheme visitors see (background, surface, raised, border, ink, muted, accent, on-accent, accent ink, link, focus ring);
   - the kit's font pairing, as families (`FONT_FAMILIES`, exactly what `styles/design.css` uses for the rest of the storefront);
   - the corner style from the kit's card shape;
   - the figures in the motif slots, and the tagline.
2. **The brief says to use them exactly** (`brand_brief`): define the colours as CSS custom properties on `.ai-page` and use only those, plus transparent tints, because the movie, checkout and ticket pages wear the same. A logo with no figures is told to leave out the motif slots, so none are left empty.
3. **One scheme for every page.** A written page has one palette. A theme left on `auto` is pinned to the mode its light background suits, so the device's mode can't flip our pages while the written page stays the same.

## Consequences
- Header, home page, footer and the booking pages between them share colours, fonts and corners.
- A design takes about 20 s longer: the page starts after the colours and plan instead of beside them.
